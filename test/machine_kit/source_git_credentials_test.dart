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
  _purgeTargetsRealCredentialSources();
  _submodulePurgeGateYaml();
  _dryRunAssertsHelperServedUsername();
  _persistStepReassertsPurge();
  _checkoutStopsPersistingAppToken();
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

/// PR #68 review threads 7+8: actions/checkout (verified against the shipped
/// v4.2.2 and v5.0.0 dist) NEVER writes a RUNNER_TEMP
/// `git-credentials-*.config` include file — it writes the App-token
/// extraheader DIRECTLY into the repo local .git/config and, with
/// `submodules: true`, into each submodule's local config
/// (.git/modules/<name>/config). The purge must target those real sources
/// and must not chase the phantom include file (an earlier version of the
/// script's root-cause comment claimed an include file existed and `rm`ed a
/// matching glob — a silent no-op that sent debugging rounds chasing a file
/// that does not exist).
void _purgeTargetsRealCredentialSources() {
  group('purge targets the credential sources checkout actually writes', () {
    test('the script does not chase the phantom checkout include file', () {
      expect(
        _read(_scriptPath),
        isNot(contains('git-credentials-*.config')),
        reason: 'no actions/checkout release writes '
            'RUNNER_TEMP/git-credentials-*.config — the rm is a no-op and '
            'the comment around it documents a mechanism that does not '
            'exist (review threads 7 and 13)',
      );
    });

    test('the script purges submodule local configs too', () {
      final script = _read(_scriptPath);
      expect(
        script.contains('git submodule foreach --recursive'),
        isTrue,
        reason: 'checkout with submodules: true arms every submodule local '
            'config with the App-token extraheader — a push from inside '
            'agents/ would still authenticate as github-actions[bot] '
            '(review thread 8)',
      );
      expect(
        script.contains(
            r"--unset-all http.https://github.com/.extraheader || true'"),
        isTrue,
        reason: 'the submodule foreach must unset the extraheader while '
            'tolerating an already-clean config',
      );
    });
  });
}

/// Review thread 8 (trace-gate side): the workflow's purge evidence used to
/// inspect only the main repo — it passes while a submodule stays armed.
/// The trace step must probe every submodule local config and fail the run
/// on a leftover.
void _submodulePurgeGateYaml() {
  group('the trace step gates on submodule extraheaders too (gh-63)', () {
    for (final path in _credentialYamlFiles) {
      test('$path probes submodule configs for the App token', () {
        final source = _read(path);
        expect(
          source.contains('git submodule foreach --quiet --recursive'),
          isTrue,
          reason: 'the trace gate must inspect every submodule local config '
              '— a leftover there arms pushes made from inside the submodule',
        );
        expect(
          source.contains('submodule config after purge'),
          isTrue,
          reason: 'a submodule leftover must fail the run (::error:: + '
              'exit 1), not just print',
        );
      });
    }
  });
}

/// Review thread 9: with GIT_ASKPASS=echo, `git credential fill` exits 0 even
/// when no credential helper answered (echo prints its prompt argument back
/// and git accepts it as a bogus credential) — so the dry-run's exit status
/// proves nothing. The dry-run must ASSERT that the winning credential is the
/// SOURCE helper's (`username=x-access-token`) and fail the run otherwise.
void _dryRunAssertsHelperServedUsername() {
  group('trace dry-run is a real gate on the winning credential (gh-63)', () {
    for (final path in _credentialYamlFiles) {
      test('$path asserts the SOURCE helper served the dry-run', () {
        final source = _read(path);
        expect(
          source.contains(r"grep -q '^username=x-access-token$'"),
          isTrue,
          reason: 'GIT_ASKPASS=echo makes git credential fill "succeed" even '
              'when no helper answered — only the helper-served username '
              'proves the SOURCE credential wins (review thread 9)',
        );
        expect(
          source.contains('dry-run credential was NOT served'),
          isTrue,
          reason: 'an un-served dry-run must fail the run (::error:: + exit 1)',
        );
      });
    }
  });
}

/// Review thread 10: the purge gate used to run only BEFORE the agent — a
/// mid-run re-assertion (gh auth setup-git, submodule config writes) slipped
/// through until push time. The memory-persist step is the last push path and
/// runs AFTER the agent session: it must re-assert the extraheader emptiness
/// (and --show-origin the config so the log shows WHEN/WHERE it reappeared).
void _persistStepReassertsPurge() {
  group('the memory-persist push re-asserts the purge post-agent (gh-63)', () {
    for (final path in _credentialYamlFiles) {
      test('$path re-asserts the extraheader purge after the agent session',
          () {
        final source = _read(path);
        // The memory-persist step hosts the LAST installer call in the file.
        final installerCall = source.lastIndexOf(
            'bash machine-kit/scripts/install-source-git-credentials.sh');
        final reassert = source.indexOf('reappeared after the agent session');
        expect(installerCall, greaterThan(-1),
            reason: '$path must invoke the shared installer');
        expect(
          reassert,
          greaterThan(installerCall),
          reason: 'the gate must run in the memory-persist step (after the '
              'agent ran) — pre-agent evidence cannot catch a mid-run '
              're-assertion (review thread 10)',
        );
        expect(
          source.contains(
              'git config --show-origin --get-all http.https://github.com/.extraheader || true'),
          isTrue,
          reason: 'the post-agent trace must name the config origin, so the '
              'run log answers WHEN the extraheader reappeared '
              '(ticket Task 1)',
        );
      });
    }
  });
}

/// Review thread 11 (optional simplification) + ticket Task 2: the cleanest
/// way to make SOURCE_GITHUB_TOKEN win is to stop persisting the competing
/// App token at the source — actions/checkout must run with
/// `persist-credentials: false` (which also skips the submodule extraheader
/// writes). The explicit purge in the shared script stays as
/// defense-in-depth for runners/actions that ignore the flag.
void _checkoutStopsPersistingAppToken() {
  group('checkout stops persisting the App token at the source (gh-63)', () {
    for (final path in _credentialYamlFiles) {
      test('$path checks out with persist-credentials: false', () {
        final source = _read(path);
        final checkout = source.indexOf('uses: actions/checkout@');
        expect(checkout, greaterThan(-1));
        final persist = source.indexOf('persist-credentials: false', checkout);
        expect(
          persist,
          greaterThan(checkout),
          reason: 'persist-credentials: false removes the App-token '
              'extraheader (main repo + submodules) at the source — the '
              'script purge stays as defense-in-depth (review thread 11)',
        );
      });
    }
  });
}
