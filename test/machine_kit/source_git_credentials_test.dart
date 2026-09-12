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
  _extraheaderValueRedaction();
  _helperOperationGuard();
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

    test(
        'malformed identities are rejected, real ones accepted — by the script',
        () async {
      // Execute the regex SHIPPED IN the script, not a Dart re-implementation
      // of it (review thread 14): a hand-copied mirror tests the copy, so a
      // regex drift in the script (e.g. losing the `+`) goes unnoticed. Dart
      // RegExp has no POSIX classes ([^[:space:]@]), so run the real guard
      // through grep and judge its exit status.
      final script = _read(_scriptPath);
      final match = RegExp("grep -qE '([^']+)'").firstMatch(script);
      expect(match, isNotNull,
          reason: 'the script must contain its grep identity guard');
      final guard = match!.group(1)!;
      const good = ['123456+octocat', '1+a'];
      const bad = [
        '123x+login', // id must be digits
        '123+log in', // login has a space
        '123+log@in', // login has an @
        '',
      ];
      for (final vector in good) {
        expect(await _scriptGrepMatches(guard, vector), isTrue,
            reason: 'a real <id>+<login> identity must pass the script guard '
                '(`$guard`): "$vector"');
      }
      for (final vector in bad) {
        expect(await _scriptGrepMatches(guard, vector), isFalse,
            reason: 'a malformed identity must be rejected by the script '
                'guard (`$guard`): "$vector"');
      }
    });
  });
}

/// Runs the exact grep pattern extracted from the script against [input] and
/// reports whether the guard accepts it (the shipped regex is the one under
/// test — review thread 14).
Future<bool> _scriptGrepMatches(String pattern, String input) async {
  final process = await Process.start('grep', ['-qE', pattern]);
  process.stdin.write(input);
  await process.stdin.close();
  return await process.exitCode == 0;
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
          source.contains(RegExp(
              r"--show-origin --get-all http\.https://github\.com/\.extraheader \| sed -E '")),
          isTrue,
          reason: 'the post-agent trace must name the config origin — '
              'redacted, because on a leftover the raw dump prints the '
              'base64 App token (review threads 11 and 12) — so the '
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

/// Review threads 11+12 (round 3): the purge gates' FAILURE paths printed the
/// raw `http.https://github.com/.extraheader` value —
/// `AUTHORIZATION: basic <base64(x-access-token:<APP_TOKEN>)>`. GitHub's log
/// masking matches the raw token string, not its base64 form, so in exactly
/// the failure scenario the gate exists to catch, the run log ends up with a
/// working, trivially decodable App installation token. Everywhere the value
/// could print (the LEFTOVER probe echo, every `--show-origin` dump of the
/// extraheader — trace step AND memory-persist step, workflow AND template)
/// the value must be redacted while the origin/submodule path stays visible.
void _extraheaderValueRedaction() {
  group('extraheader value is redacted everywhere it could print (gh-63)', () {
    for (final path in _credentialYamlFiles) {
      _leftoverProbeRedaction(path);
      _showOriginDumpsRedacted(path);
      _showOriginRedactionActuallyWorks(path);
    }
  });
}

/// The LEFTOVER probe names the armed submodule but must never echo the
/// extraheader VALUE it found (threads 11+12).
void _leftoverProbeRedaction(String path) {
  test('$path LEFTOVER probe never echoes the raw value', () {
    final source = _read(path);
    expect(
      source.contains(r'LEFTOVER ${sm_path}: <redacted>'),
      isTrue,
      reason: 'on a still-armed submodule config the probe echoes the '
          'extraheader value — AUTHORIZATION: basic <base64(App token)>, '
          'decodable and NOT masked by GitHub log redaction; keep the '
          'submodule path, redact the value (review threads 11 and 12)',
    );
    expect(
      source.contains(r'LEFTOVER ${sm_path}: ${c}'),
      isFalse,
      reason: 'the raw extraheader value must never reach the run log',
    );
  });
}

/// Every `--show-origin` dump of the extraheader must pipe through a
/// redacting sed, or the raw value prints on a leftover (threads 11+12).
void _showOriginDumpsRedacted(String path) {
  test('$path redacts every extraheader --show-origin dump', () {
    final dumps = _read(path)
        .split('\n')
        .where((line) => line.contains(
            '--show-origin --get-all http.https://github.com/.extraheader'))
        .toList();
    expect(dumps, isNotEmpty,
        reason: 'the trace evidence must keep naming the config origin (ticket '
            'Task 1)');
    for (final dump in dumps) {
      expect(
        dump.contains(RegExp(r"\|\s*sed\s+-E\s+'")),
        isTrue,
        reason: 'a --show-origin dump prints the raw extraheader VALUE on a '
            'leftover — pipe it through a redacting sed '
            '(review threads 11 and 12); offending line: '
            '${dump.trim()}',
      );
    }
  });
}

/// Behavior, not a hand-copied pattern (review thread 14's lesson): run the
/// sed program SHIPPED IN the dump line against a poisoned `--show-origin`
/// output line and assert the value cannot survive. (git prints
/// `<origin>\t<value>` — no `key=` — so the initially suggested
/// `sed 's/=.*$/=<redacted>/'` trimmed only from the first `=` INSIDE the
/// base64 and leaked the rest; this test fails for it.)
void _showOriginRedactionActuallyWorks(String path) {
  test('$path redacting sed provably redacts a poisoned dump line', () async {
    final dumpLine = _read(path).split('\n').map((l) => l.trim()).firstWhere(
        (l) => l.contains(
            '--show-origin --get-all http.https://github.com/.extraheader'));
    final sedMatch =
        RegExp(r"\| sed -E '((?:[^'\\]|\\.)*)'").firstMatch(dumpLine);
    expect(sedMatch, isNotNull,
        reason: "the dump must pipe through `sed -E '…'` — line: $dumpLine");
    final sedProgram = sedMatch!.group(1)!;
    final poisoned = 'file:.git/config\tAUTHORIZATION: basic QUJDREVGRw==';
    final result = await Process.run('bash', [
      '-c',
      'printf "%s\\n" "\$DUMP_LINE" | sed -E "\$SED_PROGRAM"',
    ], environment: {
      'DUMP_LINE': poisoned,
      'SED_PROGRAM': sedProgram,
    });
    final out = '${result.stdout}';
    expect(out, contains('file:.git/config'),
        reason: 'the origin must stay visible (ticket Task 1 evidence)');
    expect(out, contains('<redacted>'),
        reason: 'the value must be replaced with the redaction marker');
    expect(
      out.contains('QUJDREVGRw'),
      isFalse,
      reason: 'the sed program shipped in the dump line leaked the '
          'poisoned extraheader value: program `$sedProgram` produced $out',
    );
  });
}

/// Review thread 13 (round 3): git invokes credential helpers as
/// `f <operation>` where the operation is `get`, `store`, or `erase`. The
/// helper must answer only `get` — answering store/erase is discarded by git
/// today, but the guard keeps the contract explicit and keeps the evidence
/// log free of phantom "served" lines if anything ever runs
/// `git credential approve`/`reject`.
void _helperOperationGuard() {
  group('the SOURCE helper answers only the get operation (gh-63)', () {
    final script = _read(_scriptPath);

    test(r'the helper guards on $1 = get before reading stdin', () {
      expect(
        script.contains(r'[ "$1" = "get" ] || return 0;'),
        isTrue,
        reason: 'git invokes helpers as `f get|store|erase` — the helper '
            'must answer only `get` so store/erase can never log a served '
            'line (review thread 13)',
      );
      final guard = script.indexOf(r'[ "$1" = "get" ] || return 0;');
      final stdinRead = script.indexOf(r'input="$(cat)"');
      expect(guard, greaterThan(-1));
      expect(stdinRead, greaterThan(-1));
      expect(
        guard,
        lessThan(stdinRead),
        reason: 'the operation guard must run before the stdin read — a '
            'store/erase invocation must not consume input or log anything',
      );
    });
  });
}
