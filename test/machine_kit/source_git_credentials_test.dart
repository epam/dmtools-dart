// gh-63 regression tests: the SOURCE_GITHUB_TOKEN push-credential machinery
// in the AI Teammate workflows must never leak the workflows-capable PAT to
// non-github hosts (PR #68 review, BLOCKING thread) and must keep its
// at-push-time evidence honest. This file pins the INSTALLER side of the
// machinery:
//   .github/workflows/ai-teammate-issues.yml
//   machine-kit/templates/ai-teammate-issues.yml
//   machine-kit/scripts/install-source-git-credentials.sh
// The trace-script side is pinned in trace_git_credentials_test.dart, the
// behavioral sandbox in credential_sandbox_test.dart — so a future edit
// cannot silently reintroduce the generic-helper leak, weaken the purge
// evidence, or resurrect a drifted inline copy (review thread 18).
import 'dart:io';

import 'package:test/test.dart';

import 'credential_sources.dart';

void main() {
  _hostScopingYaml();
  _hostScopingScript();
  _deduplicationIntoScript();
  _artifactSeesFinalPush();
  _identityRegex();
  _purgeTargetsRealCredentialSources();
  _persistStepGateBeforeRepurge();
  _checkoutStopsPersistingAppToken();
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
    for (final path in credentialYamlFiles) {
      test(
          '$path never installs the helper on the generic credential.helper key',
          () {
        final genericHelperWrites = readSource(path)
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
    final script = readSource(installerPath);

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

/// Review thread 6: the ~40-line purge + helper block existed 6x across the
/// workflow and the template — the helper body must live in the shared script
/// only, and both files must invoke it.
void _deduplicationIntoScript() {
  group('credential machinery is deduplicated into the shared script (gh-63)',
      () {
    test('the helper one-liner exists exactly once — in the script', () {
      expect(readSource(installerPath),
          contains('credential.https://github.com.helper'));
      final occurrences = credentialYamlFiles
          .map(readSource)
          .expand((source) => source.split('\n'))
          .where((line) => line.contains(r'password=${SOURCE_GITHUB_TOKEN}'))
          .length;
      expect(
        occurrences,
        0,
        reason: 'the helper body must live in '
            '$installerPath only — every duplicated copy drifts',
      );
    });

    test('both files call the shared script', () {
      for (final path in credentialYamlFiles) {
        expect(
          readSource(path).split('\n').where((l) => l.contains(installerPath)),
          isNotEmpty,
          reason: '$path must invoke the shared install script',
        );
      }
    });

    test('the shared script exists and is valid bash', () {
      final script = readSource(installerPath);
      expect(script, startsWith('#!'));
      expect(script, contains('set -euo pipefail'));
    });
  });
}

/// Review thread 5: the artifact upload must run AFTER the memory-persist
/// push, or the durable copy of the run misses the final helper invocation.
void _artifactSeesFinalPush() {
  test('artifact upload runs after the memory-persist step (gh-63)', () {
    final source = readSource(workflowPath);
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
        readSource(installerPath),
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
      final script = readSource(installerPath);
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
        readSource(installerPath),
        isNot(contains('git-credentials-*.config')),
        reason: 'no actions/checkout release writes '
            'RUNNER_TEMP/git-credentials-*.config — the rm is a no-op and '
            'the comment around it documents a mechanism that does not '
            'exist (review threads 7 and 13)',
      );
    });

    test('the script purges submodule local configs too', () {
      final script = readSource(installerPath);
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

/// Review thread 10 + 15: the memory-persist step is the last push path and
/// runs AFTER the agent session, so it must re-assert the extraheader
/// emptiness — and the gate must run BEFORE the installer re-invocation:
/// the installer purges the extraheader as its step 1, so the previous
/// order (installer, then gate) silently wiped any mid-run re-assertion and
/// made the gate dead code (review thread 15). The gate's script-side
/// content is pinned in trace_git_credentials_test.dart.
void _persistStepGateBeforeRepurge() {
  group('the memory-persist push re-asserts the purge post-agent (gh-63)', () {
    for (final path in credentialYamlFiles) {
      test('$path gates the post-agent extraheader BEFORE the re-purge', () {
        final source = readSource(path);
        // The memory-persist step hosts the LAST installer call in the file.
        final persistStep =
            source.indexOf('Persist fa project memory into the repository');
        final installerCall = source.lastIndexOf('bash $installerPath');
        final postAgentGate = source.indexOf('$traceScriptPath --post-agent');
        expect(persistStep, greaterThan(-1),
            reason: '$path must have the memory-persist step');
        expect(installerCall, greaterThan(-1),
            reason: '$path must invoke the shared installer');
        expect(postAgentGate, greaterThan(-1),
            reason: 'the persist step must run the post-agent gate through '
                'the shared trace script');
        expect(
          postAgentGate,
          greaterThan(persistStep),
          reason: 'the gate must run in the memory-persist step (after the '
              'agent ran) — pre-agent evidence cannot catch a mid-run '
              're-assertion (review thread 10)',
        );
        expect(
          postAgentGate,
          lessThan(installerCall),
          reason: 'the gate must run BEFORE the installer re-invocation: the '
              'installer purges the extraheader as its step 1, so running it '
              'first silently wipes any mid-run re-assertion, makes this '
              'gate dead code and destroys the Task-1 origin evidence '
              '(review thread 15)',
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
    for (final path in credentialYamlFiles) {
      test('$path checks out with persist-credentials: false', () {
        final source = readSource(path);
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

/// Review thread 13 (round 3): git invokes credential helpers as
/// `f <operation>` where the operation is `get`, `store`, or `erase`. The
/// helper must answer only `get` — answering store/erase is discarded by git
/// today, but the guard keeps the contract explicit and keeps the evidence
/// log free of phantom "served" lines if anything ever runs
/// `git credential approve`/`reject`.
void _helperOperationGuard() {
  group('the SOURCE helper answers only the get operation (gh-63)', () {
    final script = readSource(installerPath);

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
