// gh-63 regression tests — the TRACE side of the push-credential machinery.
// The trace/gate block (redacting --show-origin sed, submodule LEFTOVER
// probe, git var idents, capture-then-assert dry-run) used to exist 4x —
// pre- and post-agent, in the workflow and the machine-kit template — and
// the inline copies had already drifted once (review threads 11/12). Since
// review thread 18 the block lives in ONE shared script,
//   machine-kit/scripts/trace-git-credentials.sh
// and the YAML files only invoke it. This file pins the script's gates, the
// redaction of every extraheader dump, and the thread-16 conditional on the
// dry-run gate. The installer side is pinned in
// source_git_credentials_test.dart, the behavioral sandbox in
// credential_sandbox_test.dart.
import 'dart:io';

import 'package:test/test.dart';

import 'credential_sources.dart';

void main() {
  _purgeEvidenceGate();
  _evidenceLogTagging();
  _dryRunFallbackReachable();
  _traceBlockInvokedFromBothYamls();
  _traceBlockNoInlineCopies();
  _traceScriptCarriesBothModes();
  _submodulePurgeGate();
  _dryRunAssertsHelperServedUsername();
  _dryRunGateConditionalOnPat();
  _postAgentGateKeepsOriginEvidence();
  _extraheaderValueRedaction();
}

/// Review thread 2: the trace step must ASSERT the purge (`::error::` +
/// exit 1), not just print the value — a renamed checkout include file has to
/// fail the run instead of silently resurrecting the App token. Since review
/// thread 18 the gate lives in the shared trace script; the YAML files must
/// invoke it (inline copies drift).
void _purgeEvidenceGate() {
  group('purge evidence is a gate, not a printout (gh-63, trace step)', () {
    test('the trace script asserts the extraheader purge and fails otherwise',
        () {
      final script = readSource(traceScriptPath);
      expect(
        script,
        contains('::error::App-token extraheader still present after purge'),
        reason: 'a silent print lets a renamed checkout include file '
            'resurrect the App token unnoticed',
      );
      expect(
        script.contains(
          r'git config --get-all http.https://github.com/.extraheader | grep -q .',
        ),
        isTrue,
        reason: 'the trace step must turn the purge proof into a failing gate',
      );
    });

    for (final path in credentialYamlFiles) {
      test('$path gates through the shared trace script', () {
        expect(
          readSource(path).contains('bash $traceScriptPath'),
          isTrue,
          reason: '$path must run the shared trace script — the inline copy '
              'of the gate drifted from the template copy before (thread 18)',
        );
      });
    }
  });
}

/// Review thread 3: trace dry-runs must tag their evidence-log lines
/// (CRED_HELPER_CONTEXT) so they cannot be mistaken for real pushes. Since
/// review thread 18 the dry-run lives in the shared trace script.
void _evidenceLogTagging() {
  group(
      'trace dry-runs are tagged so they cannot pollute push evidence (gh-63)',
      () {
    test('the trace script dry-run sets CRED_HELPER_CONTEXT=trace-dry-run', () {
      expect(
        readSource(traceScriptPath),
        contains('CRED_HELPER_CONTEXT=trace-dry-run'),
        reason: 'each untagged dry-run logs a line indistinguishable from a '
            'real push, inflating the at-push-time evidence',
      );
    });

    test('the helper tags every log line with CRED_HELPER_CONTEXT', () {
      final script = readSource(installerPath);
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
/// can never fire. Require the capture-then-branch form (now in the shared
/// trace script, thread 18).
void _dryRunFallbackReachable() {
  group('trace dry-run failure fallback is reachable (gh-63)', () {
    test(
        'the trace script captures git credential fill output before branching',
        () {
      final source = readSource(traceScriptPath);
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
  });
}

/// Review thread 18 (round 4), part 1: both YAML files must run the shared
/// trace script in both modes — the full pre-agent trace and the post-agent
/// gate in the memory-persist step.
void _traceBlockInvokedFromBothYamls() {
  group('the trace/gate block is deduplicated into the trace script (gh-63)',
      () {
    test('both YAML files run the shared trace script in both modes', () {
      for (final path in credentialYamlFiles) {
        final calls = readSource(path)
            .split('\n')
            .where((l) => l.contains('bash $traceScriptPath'))
            .toList();
        expect(calls, isNotEmpty,
            reason: '$path must invoke the shared trace script');
        expect(
          calls.any((l) => !l.contains('--post-agent')),
          isTrue,
          reason: '$path must run the full pre-agent trace (before the agent '
              'step) through the shared script',
        );
        expect(
          calls.any((l) => l.contains('--post-agent')),
          isTrue,
          reason: '$path must run the post-agent gate in the memory-persist '
              'step through the shared script',
        );
      }
    });
  });
}

/// Review thread 18 (round 4), part 2: no inline copy of the moved machinery
/// may remain in the YAML files — that is how the workflow and template
/// copies drifted before (threads 11/12).
void _traceBlockNoInlineCopies() {
  group('the trace/gate block is deduplicated into the trace script (gh-63)',
      () {
    test('no inline copy of the trace machinery remains in the YAML files', () {
      for (final path in credentialYamlFiles) {
        // Only CODE lines count — comments may name the commands they
        // document; the invariant is that no executable copy drifted back.
        final code = readSource(path)
            .split('\n')
            .where((l) => !l.trim().startsWith('#'))
            .join('\n');
        expect(
          code.contains('git credential fill'),
          isFalse,
          reason: '$path must not re-inline the dry-run — it lives in '
              '$traceScriptPath (thread 18); inline copies drift',
        );
        expect(
          code.contains('submodule foreach --quiet --recursive'),
          isFalse,
          reason: '$path must not re-inline the submodule LEFTOVER probe — '
              'it lives in $traceScriptPath (thread 18)',
        );
        expect(
          code.contains(
              '--show-origin --get-all http.https://github.com/.extraheader'),
          isFalse,
          reason: '$path must not re-inline the extraheader dump — the only '
              'extraheader prints are the redacting ones in '
              '$traceScriptPath (threads 11/12 + 18)',
        );
      }
    });
  });
}

/// Review thread 18 (round 4), part 3: the shared script must carry both
/// modes and every gate the four inline copies used to enforce.
void _traceScriptCarriesBothModes() {
  group('the trace/gate block is deduplicated into the trace script (gh-63)',
      () {
    test('the trace script carries both modes and every moved gate', () {
      final script = readSource(traceScriptPath);
      expect(script, startsWith('#!'));
      expect(script, contains('set -euo pipefail'));
      expect(
        script.contains('--post-agent'),
        isTrue,
        reason: 'the memory-persist call sites run the script in its '
            'post-agent mode (thread 15)',
      );
      expect(
        script.contains(
            '::error::App-token extraheader reappeared after the agent session'),
        isTrue,
        reason: 'the post-agent mode keeps the run-killing gate on a mid-run '
            're-assertion (review thread 10)',
      );
      expect(
        script.contains('git submodule foreach --quiet --recursive'),
        isTrue,
        reason: 'the full mode keeps the submodule LEFTOVER probe '
            '(review thread 8)',
      );
    });
  });
}

/// Review thread 8 (trace-gate side): the workflow's purge evidence used to
/// inspect only the main repo — it passes while a submodule stays armed.
/// The trace must probe every submodule local config and fail the run on a
/// leftover. Since review thread 18 the probe lives in the shared trace
/// script (the YAML files invoke it — pinned by `_traceBlockInvokedFromBothYamls`).
void _submodulePurgeGate() {
  group('the trace step gates on submodule extraheaders too (gh-63)', () {
    test('the trace script probes submodule configs for the App token', () {
      final script = readSource(traceScriptPath);
      expect(
        script.contains('git submodule foreach --quiet --recursive'),
        isTrue,
        reason: 'the trace gate must inspect every submodule local config '
            '— a leftover there arms pushes made from inside the submodule',
      );
      expect(
        script.contains('submodule config after purge'),
        isTrue,
        reason: 'a submodule leftover must fail the run (::error:: + '
            'exit 1), not just print',
      );
    });
  });
}

/// Review thread 9: with GIT_ASKPASS=echo, `git credential fill` exits 0 even
/// when no credential helper answered (echo prints its prompt argument back
/// and git accepts it as a bogus credential) — so the dry-run's exit status
/// proves nothing. The dry-run must ASSERT that the winning credential is the
/// SOURCE helper's (`username=x-access-token`) and fail the run otherwise.
void _dryRunAssertsHelperServedUsername() {
  group('trace dry-run is a real gate on the winning credential (gh-63)', () {
    test('the trace script asserts the SOURCE helper served the dry-run', () {
      final script = readSource(traceScriptPath);
      expect(
        script.contains(r"grep -q '^username=x-access-token$'"),
        isTrue,
        reason: 'GIT_ASKPASS=echo makes git credential fill "succeed" even '
            'when no helper answered — only the helper-served username '
            'proves the SOURCE credential wins (review thread 9)',
      );
      expect(
        script.contains('dry-run credential was NOT served'),
        isTrue,
        reason: 'an un-served dry-run must fail the run (::error:: + exit 1)',
      );
    });
  });
}

/// Review thread 16 (round 4): when `SOURCE_GITHUB_TOKEN` is not configured,
/// the installer installs no helper and the dry-run assertion failed —
/// `::error::` + exit 1 — killing run kinds that never push at all (review
/// runs post their comments with the `github.token` fallback; the
/// memory-persist push already tolerates rejection). The gate must key on
/// the secret's presence: warn + skip when it is unset, keep the hard
/// `::error::` + exit 1 when it is set.
void _dryRunGateConditionalOnPat() {
  group('the trace dry-run gate is conditional on SOURCE_GITHUB_TOKEN (gh-63)',
      () {
    final script = readSource(traceScriptPath);

    test('PAT-less environments degrade to a warning instead of dying', () {
      expect(
        script.contains(r'-z "${SOURCE_GITHUB_TOKEN:-}"'),
        isTrue,
        reason: 'the gate must key on the secret being set — without this '
            'check a missing PAT kills runs that never push (thread 16)',
      );
      expect(
        script.contains('::warning::SOURCE_GITHUB_TOKEN not set'),
        isTrue,
        reason: 'the skip must be visible on the run page (::warning::), not '
            'silent',
      );
    });

    test('the skip branch runs first; the hard gate stays for PAT-present runs',
        () {
      final skipBranch = script.indexOf(r'-z "${SOURCE_GITHUB_TOKEN:-}"');
      final hardGate = script.indexOf(r"grep -q '^username=x-access-token$'");
      final hardFail = script.indexOf('dry-run credential was NOT served');
      expect(skipBranch, greaterThan(-1));
      expect(hardGate, greaterThan(-1));
      expect(hardFail, greaterThan(-1));
      expect(
        skipBranch,
        lessThan(hardGate),
        reason: 'the unset check must precede the helper-served assertion — '
            'otherwise PAT-less runs die at the gate before the warning can '
            'fire (thread 16)',
      );
    });
  });
}

/// Review thread 15 (round 4): the post-agent gate lives in the trace
/// script's --post-agent mode and must keep its run-killing error plus the
/// redacted --show-origin evidence — the origin answers WHICH source
/// re-asserted the credential (ticket Task 1); the YAML-side ordering
/// (gate BEFORE the installer re-invocation) is pinned in
/// source_git_credentials_test.dart.
void _postAgentGateKeepsOriginEvidence() {
  group('the post-agent gate keeps the origin evidence, redacted (gh-63)', () {
    test('the trace script errors on a mid-run re-assertion', () {
      final script = readSource(traceScriptPath);
      expect(
        script.contains(
            '::error::App-token extraheader reappeared after the agent session'),
        isTrue,
        reason: 'a mid-run resurrection must fail the run with the reason on '
            'the run page (review thread 10)',
      );
      final postAgent = script.indexOf('post-agent extraheader trace');
      final dump = script.indexOf(
          '--show-origin --get-all http.https://github.com/.extraheader',
          postAgent);
      expect(postAgent, greaterThan(-1));
      expect(
        dump,
        greaterThan(postAgent),
        reason: 'the --show-origin line answers WHICH source re-asserted the '
            'credential (ticket Task 1) — redacted per threads 11/12',
      );
    });
  });
}

/// Review threads 11+12 (round 3): the purge gates' FAILURE paths printed the
/// raw `http.https://github.com/.extraheader` value —
/// `AUTHORIZATION: basic <base64(x-access-token:<APP_TOKEN>)>`. GitHub's log
/// masking matches the raw token string, not its base64 form, so in exactly
/// the failure scenario the gate exists to catch, the run log ends up with a
/// working, trivially decodable App installation token. Since review thread
/// 18 every extraheader print (LEFTOVER probe echo, every `--show-origin`
/// dump — trace step AND memory-persist step) lives in the shared trace
/// script, so the redaction invariants are pinned on that one file.
void _extraheaderValueRedaction() {
  group('extraheader value is redacted everywhere it could print (gh-63)', () {
    _leftoverProbeRedaction(traceScriptPath);
    _showOriginDumpsRedacted(traceScriptPath);
    _showOriginRedactionActuallyWorks(traceScriptPath);
  });
}

/// The LEFTOVER probe names the armed submodule but must never echo the
/// extraheader VALUE it found (threads 11+12).
void _leftoverProbeRedaction(String path) {
  test('$path LEFTOVER probe never echoes the raw value', () {
    final source = readSource(path);
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
    final dumps = readSource(path)
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

/// Behavior, not a hand-copied pattern (review thread 14's lesson): run each
/// sed program SHIPPED IN the dump lines against a poisoned `--show-origin`
/// output line and assert the value cannot survive. (git prints
/// `<origin>\t<value>` — no `key=` — so the initially suggested
/// `sed 's/=.*$/=<redacted>/'` trimmed only from the first `=` INSIDE the
/// base64 and leaked the rest; this test fails for it.) Every dump line in
/// the script — full mode AND post-agent mode — is exercised.
void _showOriginRedactionActuallyWorks(String path) {
  test('$path redacting sed provably redacts a poisoned dump line', () async {
    final dumpLines = readSource(path)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.contains(
            '--show-origin --get-all http.https://github.com/.extraheader'))
        .toList();
    expect(dumpLines, isNotEmpty,
        reason: 'the script must keep the --show-origin evidence dumps');
    for (final dumpLine in dumpLines) {
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
    }
  });
}
