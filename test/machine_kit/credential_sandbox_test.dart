// gh-63 sandbox tests: execute the REAL shared scripts against a poisoned
// temp checkout. Review thread 17 asked for exactly this — "valid bash" by
// string-matching is not parsing, and the PR body's claimed offline
// reproduction deserves a permanent pin. The sandbox also proves the
// thread-16 fix behaviorally: without SOURCE_GITHUB_TOKEN the trace warns
// and passes; with the PAT but no helper it still hard-fails.
//
// All git state is sandboxed: HOME points at a throwaway dir so neither the
// developer's global git config leaks in nor does the installer's
// `git config --global` leak out.
import 'dart:io';

import 'package:test/test.dart';

import 'credential_sources.dart';

/// A throwaway git repo plus the isolated environment the scripts run in.
class _Sandbox {
  final Directory repo;
  final Directory home;

  _Sandbox(this.repo, this.home);

  Future<ProcessResult> git(List<String> args) async {
    final result = await Process.run('git', args,
        workingDirectory: repo.path, environment: {'HOME': home.path});
    expect(result.exitCode, 0,
        reason: 'git ${args.join(" ")} failed: ${result.stderr}');
    return result;
  }

  /// stdout of a config query; exit 1 = key unset (treated as empty —
  /// exactly the state the purge is supposed to produce).
  Future<String> gitOut(List<String> args) async {
    final result = await Process.run('git', args,
        workingDirectory: repo.path, environment: {'HOME': home.path});
    expect(result.exitCode, anyOf(0, 1),
        reason: 'git ${args.join(" ")} failed: ${result.stderr}');
    return '${result.stdout}'.trim();
  }

  /// Arms the extraheader the way actions/checkout (configureToken) does:
  /// written DIRECTLY into the repo's local .git/config.
  Future<void> poisonExtraheader() {
    return git([
      'config',
      '--local',
      'http.https://github.com/.extraheader',
      'AUTHORIZATION: basic QUJDREVGRw==',
    ]);
  }

  /// Runs a shipped script from this package inside the sandbox repo.
  /// GITHUB_WORKSPACE pins the helper's evidence log to the sandbox; extra
  /// [env] entries override the parent environment.
  Future<ProcessResult> runScript(
    String script,
    Map<String, String> env, {
    List<String> args = const [],
  }) {
    return Process.run(
      'bash',
      [File(script).absolute.path, ...args],
      workingDirectory: repo.path,
      environment: {'HOME': home.path, 'GITHUB_WORKSPACE': repo.path, ...env},
    );
  }
}

Future<_Sandbox> _freshSandbox() async {
  final repo = await Directory.systemTemp.createTemp('gh63_sandbox_');
  final home = await Directory.systemTemp.createTemp('gh63_home_');
  addTearDown(() async {
    await repo.delete(recursive: true);
    await home.delete(recursive: true);
  });
  final sandbox = _Sandbox(repo, home);
  await sandbox.git(['init', '-q']);
  await sandbox.git(['config', 'user.name', 'sandbox']);
  await sandbox.git(['config', 'user.email', 'sandbox@example.com']);
  await sandbox.git(['commit', '--allow-empty', '-q', '-m', 'seed']);
  return sandbox;
}

/// A `git credential fill` run whose helper query is [host], tagged with
/// [context] (the helper's evidence-log marker); the caller supplies the
/// askpass so no terminal prompt can ever block the suite.
Future<ProcessResult> _credentialFill(
  _Sandbox sandbox,
  String host,
  String context,
  String askpass,
) {
  return Process.run(
    'bash',
    [
      '-c',
      'printf "protocol=https\\nhost=$host\\n" | '
          'CRED_HELPER_CONTEXT=$context GIT_TERMINAL_PROMPT=0 '
          'GIT_ASKPASS=$askpass git credential fill 2>&1; true',
    ],
    workingDirectory: sandbox.repo.path,
    environment: {
      'HOME': sandbox.home.path,
      'GITHUB_WORKSPACE': sandbox.repo.path
    },
  );
}

void main() {
  _sharedScriptsParse();
  _installerPurgesAndHostScopes();
  _sourceHelperServesGithubOnly();
  _traceDryRunGatePatMatrix();
  _traceGreenPathAfterInstaller();
}

/// Review thread 17: a syntax error in either shared script (the
/// highest-risk artifacts of this PR — shell one-liners stored in git
/// config, plus the trace gates) would pass a string-matching suite and
/// only surface as a failed live workflow run. Parse the shipped files.
void _sharedScriptsParse() {
  group('the shared scripts parse (bash -n, review thread 17)', () {
    for (final path in [installerPath, traceScriptPath]) {
      test('$path parses', () async {
        final result = await Process.run('bash', ['-n', path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      });
    }
  });
}

/// gh-63 invariant (a): the checkout-poisoned extraheader is purged, and
/// the helper registrations stay host-scoped (generic list reset, scoped
/// key installed) — the blocking-thread-1 shape.
void _installerPurgesAndHostScopes() {
  group('the installer purges a poisoned checkout (gh-63 sandbox)', () {
    test('extraheader gone; generic list reset; scoped helper installed',
        () async {
      final sandbox = await _freshSandbox();
      await sandbox.poisonExtraheader();
      final install = await sandbox.runScript(
          installerPath, {'SOURCE_GITHUB_TOKEN': 'ghp_sandbox_fake'});
      expect(install.exitCode, 0, reason: '${install.stderr}');

      expect(
        await sandbox.gitOut(
            ['config', '--get-all', 'http.https://github.com/.extraheader']),
        isEmpty,
        reason: 'the installer must purge the checkout-poisoned extraheader',
      );
      expect(
        await sandbox.gitOut(['config', '--get-all', 'credential.helper']),
        isEmpty,
        reason: 'the generic helper list must stay reset (blocking thread 1)',
      );
      expect(
        await sandbox.gitOut(
            ['config', '--get-all', 'credential.https://github.com.helper']),
        contains('x-access-token'),
      );
    });
  });
}

/// gh-63 invariants (b)+(c): the SOURCE helper serves the github.com
/// credential (and tags the evidence log), while a foreign host — the
/// prompt-injected clone target of the blocking thread — is served nothing.
void _sourceHelperServesGithubOnly() {
  group('the SOURCE helper serves github.com only (gh-63 sandbox)', () {
    test('github.com gets the credential; evil.example gets nothing', () async {
      final sandbox = await _freshSandbox();
      await sandbox.poisonExtraheader();
      final install = await sandbox.runScript(
          installerPath, {'SOURCE_GITHUB_TOKEN': 'ghp_sandbox_fake'});
      expect(install.exitCode, 0, reason: '${install.stderr}');

      final fill =
          await _credentialFill(sandbox, 'github.com', 'e2e-test', 'echo');
      expect('${fill.stdout}', contains('username=x-access-token'),
          reason: 'the SOURCE helper must serve the github.com credential — '
              'the gh-63 acceptance criterion');
      final log = File('${sandbox.repo.path}/.dmtools/credential-helper.log');
      expect(log.readAsStringSync(), contains('(e2e-test)'),
          reason: 'the helper log must carry the CRED_HELPER_CONTEXT tag');

      final evil =
          await _credentialFill(sandbox, 'evil.example', 'e2e-test', 'true');
      expect(
        '${evil.stdout}',
        isNot(contains('ghp_sandbox_fake')),
        reason: 'a prompt-injected clone against a foreign host must never '
            'receive the workflows-capable PAT (blocking thread 1)',
      );
    });
  });
}

/// Review thread 16, both branches of the dry-run gate: PAT-less runs must
/// SURVIVE the trace (they may be review runs that never push), while a
/// configured PAT with no serving helper must still fail the run loudly.
void _traceDryRunGatePatMatrix() {
  group('the trace dry-run gate keys on SOURCE_GITHUB_TOKEN (thread 16)', () {
    test('PAT-less: warns and exits 0 — runs that never push survive',
        () async {
      // persist-credentials: false means nothing was persisted — a clean
      // checkout, no helper (the installer's PAT-less branch installs none).
      final sandbox = await _freshSandbox();
      final trace =
          await sandbox.runScript(traceScriptPath, {'SOURCE_GITHUB_TOKEN': ''});
      expect(
        trace.exitCode,
        0,
        reason: 'review runs that never push were fully viable without the '
            'PAT — the dry-run gate must not kill them at the trace step: '
            '${trace.stdout}${trace.stderr}',
      );
      expect(
        '${trace.stdout}${trace.stderr}',
        contains('::warning::SOURCE_GITHUB_TOKEN not set'),
        reason: 'the degradation must be visible on the run page',
      );
    });

    test('PAT present but helper absent: the dry-run still hard-fails',
        () async {
      final sandbox = await _freshSandbox();
      final trace = await sandbox.runScript(
          traceScriptPath, {'SOURCE_GITHUB_TOKEN': 'ghp_sandbox_fake'});
      expect(trace.exitCode, isNot(0),
          reason: 'with the PAT configured, an un-served dry-run must fail '
              'the run loudly: ${trace.stdout}${trace.stderr}');
      expect(
        '${trace.stdout}${trace.stderr}',
        contains('dry-run credential was NOT served'),
      );
    });
  });
}

/// The full green path: poison → installer → trace passes every gate, and
/// the dry-run evidence names the winning helper without printing it.
void _traceGreenPathAfterInstaller() {
  group('trace passes all gates behind the installer (gh-63 sandbox)', () {
    test('poison → installer → trace exits 0 with redacted evidence', () async {
      final sandbox = await _freshSandbox();
      await sandbox.poisonExtraheader();
      final install = await sandbox.runScript(
          installerPath, {'SOURCE_GITHUB_TOKEN': 'ghp_sandbox_fake'});
      expect(install.exitCode, 0, reason: '${install.stderr}');

      final trace = await sandbox.runScript(
          traceScriptPath, {'SOURCE_GITHUB_TOKEN': 'ghp_sandbox_fake'});
      expect(trace.exitCode, 0, reason: '${trace.stdout}${trace.stderr}');
      expect(
        '${trace.stdout}',
        contains(
            'password=<redacted — served by the SOURCE_GITHUB_TOKEN helper>'),
        reason: 'the dry-run evidence must name the winning helper without '
            'printing the credential',
      );
    });
  });
}
