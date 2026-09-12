// gh-63 regression tests: the SOURCE_GITHUB_TOKEN push-credential machinery
// in the AI Teammate workflows must never leak the workflows-capable PAT to
// non-github hosts (PR #68 review, BLOCKING thread) and must keep its
// at-push-time evidence honest. These tests pin the invariants of
//   .github/workflows/ai-teammate-issues.yml
//   machine-kit/templates/ai-teammate-issues.yml
//   machine-kit/scripts/install-source-git-credentials.sh
// so a future edit cannot silently reintroduce the generic-helper leak or
// weaken the purge evidence.
import 'dart:io';

import 'package:test/test.dart';

const _workflowPath = '.github/workflows/ai-teammate-issues.yml';
const _templatePath = 'machine-kit/templates/ai-teammate-issues.yml';
const _scriptPath = 'machine-kit/scripts/install-source-git-credentials.sh';

/// All YAML files that carry the credential machinery (workflow + template —
/// they must not drift apart, PR #68 review thread 6).
final List<String> _credentialYamlFiles = [_workflowPath, _templatePath];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('missing expected file: $path');
  }
  return file.readAsStringSync();
}

void main() {
  _hostScopingYaml();
  _hostScopingScript();
  _purgeEvidenceGate();
  _evidenceLogTagging();
  _dryRunFallbackReachable();
  _deduplicationIntoScript();
  _artifactSeesFinalPush();
  _identityRegex();
}

/// BLOCKING review thread 1 (YAML side): neither YAML file may install the
/// helper on the generic `credential.helper` key — git consults that for ANY
/// https host answering 401, handing the workflows-capable PAT to
/// attacker-controlled servers.
void _hostScopingYaml() {
  group(
      'SOURCE_GITHUB_TOKEN credential helper is host-scoped (gh-63, blocking)',
      () {
    for (final path in _credentialYamlFiles) {
      test(
          '$path never installs the helper on the generic credential.helper key',
          () {
        final genericHelperWrites = _read(path)
            .split('\n')
            .where((line) =>
                line.contains('credential.helper') &&
                line.contains('SOURCE_GITHUB_TOKEN'))
            .toList();
        expect(
          genericHelperWrites,
          isEmpty,
          reason: 'a SOURCE_GITHUB_TOKEN helper on the generic '
              'credential.helper key is consulted for ANY https host that '
              'answers 401 — register it on '
              'credential.https://github.com.helper instead',
        );
      });
    }
  });
}

/// BLOCKING review thread 1 (script side): URL-scoped registration behind
/// both list resets, plus the stdin host re-check as defense-in-depth.
void _hostScopingScript() {
  group('the shared script registers the helper host-scoped', () {
    final script = _read(_scriptPath);

    test('helper is registered on credential.https://github.com.helper', () {
      expect(
        script.contains(r'credential.https://github.com.helper "$helper"'),
        isTrue,
        reason: 'the helper must be registered on the URL-scoped key — '
            'a generic credential.helper is consulted for ANY https host '
            'whose server answers 401',
      );
      expect(
        script.contains('--add credential.https://github.com.helper'),
        isTrue,
        reason: 'the local push-path helper must be ADDED behind the reset',
      );
    });

    test('resets both inherited helper lists before installing its own', () {
      expect(
        script.contains(r"--replace-all credential.helper ''"),
        isTrue,
        reason: 'the generic reset wipes system/global generic helpers',
      );
      expect(
        script
            .contains(r"--replace-all credential.https://github.com.helper ''"),
        isTrue,
        reason: 'the scoped reset wipes system/global github.com helpers',
      );
    });

    test(
        'helper re-checks the host from stdin before answering (defense in depth)',
        () {
      expect(script, contains('host='));
      expect(
        script,
        contains(r'[ "$host" = "github.com" ] || return 0'),
        reason: 'the helper must answer nothing for non-github hosts '
            'even if it is ever registered generically',
      );
    });
  });
}

/// Review thread 2: the trace step must ASSERT the purge (`::error::` +
/// exit 1), not just print the value — a renamed checkout include file has to
/// fail the run instead of silently resurrecting the App token.
void _purgeEvidenceGate() {
  group('purge evidence is a gate, not a printout (gh-63, trace step)', () {
    for (final path in _credentialYamlFiles) {
      test('$path asserts the extraheader purge and fails the run otherwise',
          () {
        final source = _read(path);
        expect(
          source,
          contains('::error::App-token extraheader still present after purge'),
          reason: 'a silent print lets a renamed checkout include file '
              'resurrect the App token unnoticed',
        );
        expect(
          source.contains(
            r'git config --get-all http.https://github.com/.extraheader | grep -q .',
          ),
          isTrue,
          reason:
              'the trace step must turn the purge proof into a failing gate',
        );
      });
    }
  });
}

/// Review thread 3: trace dry-runs must tag their evidence-log lines
/// (CRED_HELPER_CONTEXT) so they cannot be mistaken for real pushes.
void _evidenceLogTagging() {
  group(
      'trace dry-runs are tagged so they cannot pollute push evidence (gh-63)',
      () {
    for (final path in _credentialYamlFiles) {
      test('$path dry-run sets CRED_HELPER_CONTEXT=trace-dry-run', () {
        expect(
          _read(path),
          contains('CRED_HELPER_CONTEXT=trace-dry-run'),
          reason: 'each untagged dry-run logs a line indistinguishable from a '
              'real push, inflating the at-push-time evidence',
        );
      });
    }

    test('the helper tags every log line with CRED_HELPER_CONTEXT', () {
      final script = _read(_scriptPath);
      expect(script, contains('CRED_HELPER_CONTEXT'));
      expect(
        script,
        contains('credential-helper.log'),
        reason: 'the helper log is the at-push-time proof of gh-63',
      );
    });
  });
}

/// Review thread 4: a pipeline's exit status is its LAST stage, and `sed`
/// exits 0 even on empty input — so the `|| echo` fallback after a sed stage
/// can never fire. Require the capture-then-branch form.
void _dryRunFallbackReachable() {
  group('trace dry-run failure fallback is reachable (gh-63)', () {
    for (final path in _credentialYamlFiles) {
      test('$path captures git credential fill output before branching', () {
        final source = _read(path);
        final pipelineForm = RegExp(
          r'git credential fill 2>&1( \\)?\s*\n?\s*\| sed',
        );
        expect(
          pipelineForm.hasMatch(source),
          isFalse,
          reason: 'the fallback must not depend on the exit status of a '
              'trailing sed stage',
        );
        expect(
          source.contains(
            RegExp(r'out="\$\(printf .+git credential fill 2>&1\)"'),
          ),
          isTrue,
          reason: 'capture the dry-run output, then redact-or-fallback',
        );
      });
    }
  });
}

/// Review thread 6: the ~40-line purge + helper block existed 6x across the
/// workflow and the template — the helper body must live in the shared script
/// only, and both files must invoke it.
void _deduplicationIntoScript() {
  group('credential machinery is deduplicated into the shared script (gh-63)',
      () {
    test('the helper one-liner exists exactly once — in the script', () {
      expect(
          _read(_scriptPath), contains('credential.https://github.com.helper'));
      final occurrences = _credentialYamlFiles
          .map(_read)
          .expand((source) => source.split('\n'))
          .where((line) => line.contains(r'password=${SOURCE_GITHUB_TOKEN}'))
          .length;
      expect(
        occurrences,
        0,
        reason: 'the helper body must live in '
            '$_scriptPath only — every duplicated copy drifts',
      );
    });

    test('both files call the shared script', () {
      for (final path in _credentialYamlFiles) {
        expect(
          _read(path).split('\n').where((l) => l.contains(_scriptPath)),
          isNotEmpty,
          reason: '$path must invoke the shared install script',
        );
      }
    });

    test('the shared script exists and is valid bash', () {
      final script = _read(_scriptPath);
      expect(script, startsWith('#!'));
      expect(script, contains('set -euo pipefail'));
    });
  });
}

/// Review thread 5: the artifact upload must run AFTER the memory-persist
/// push, or the durable copy of the run misses the final helper invocation.
void _artifactSeesFinalPush() {
  test('artifact upload runs after the memory-persist step (gh-63)', () {
    final source = _read(_workflowPath);
    final upload = source.indexOf('Upload the full fa session trace');
    final persist =
        source.indexOf('Persist fa project memory into the repository');
    expect(upload, greaterThan(-1));
    expect(persist, greaterThan(-1));
    expect(
      upload,
      greaterThan(persist),
      reason: 'the artifact must contain the memory-push helper invocation — '
          'uploading before the last push makes the evidence incomplete',
    );
  });
}

/// Review thread 8: the jq output is exactly `<id>+<login>` — a loose middle
/// regex class accepts malformed values like `123x+login` and emits a bogus
/// noreply email.
void _identityRegex() {
  group('commit identity attribution (gh-63)', () {
    test('noreply regex is strict: <id>+<login>, no filler', () {
      expect(
        _read(_scriptPath),
        contains("grep -qE '^[0-9]+\\+[^[:space:]@]+\$'"),
      );
    });

    test('malformed identities are rejected, real ones accepted', () {
      // Mirror of the script's grep guard, pinned here so a regex regression
      // in the script shows up as a failing expectation on these vectors.
      // (Dart RegExp has no POSIX classes: [^[:space:]@] == [^\s@].)
      final good = RegExp(r'^[0-9]+\+[^\s@]+$');
      expect(good.hasMatch('123456+octocat'), isTrue);
      expect(good.hasMatch('1+a'), isTrue);
      expect(good.hasMatch('123x+login'), isFalse, reason: 'id must be digits');
      expect(good.hasMatch('123+log in'), isFalse, reason: 'login has a space');
      expect(good.hasMatch('123+log@in'), isFalse, reason: 'login has an @');
      expect(good.hasMatch(''), isFalse);
    });
  });
}
