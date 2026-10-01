/// Tests for the strict-mode postJSAction guard (gh-316, Java epam/dm.ai#409
/// / PR epam/dm.ai#622): when `requireCliOutputFile=true` and the CLI run
/// produces no `outputs/response.md`, postJSAction must not run — mirroring
/// the Java `skipFieldUpdate` behavior. A post action like
/// closeQuestionTicket would otherwise move tickets to Done on a genuine CLI
/// failure; the error-summary response reports the failure instead.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  group('CliAgent strict-mode postJSAction guard (gh-316)', () {
    skipsWhenStrictModeCliProducesNoOutput();
    runsWhenStrictModeCliWritesOutput();
    stillRunsInPermissiveModeWithoutOutput();
    skipsInStrictModeEvenOnZeroExit();
  });
}

/// RED-case: strict mode + failed CLI without response.md → postJSAction
/// must not run; the error summary keeps reporting the failure.
void skipsWhenStrictModeCliProducesNoOutput() {
  test('skips postJSAction when strict-mode CLI produces no output file',
      () async {
    final h = await _harness(
      cliCommands: ['echo agent crashed && exit 7'],
      requireCliOutputFile: true,
    );
    try {
      final result = await h.agent.run();
      expect(
        h.postLog.existsSync(),
        isFalse,
        reason: 'postJSAction must not run against the failed/missing '
            'strict-mode response (Java skipFieldUpdate parity)',
      );
      expect(
        result['response'],
        startsWith('CLI command executed but did not produce output file'),
        reason: 'the error summary must still report the failure',
      );
    } finally {
      await h.dispose();
    }
  });
}

/// Control: output file present → postJSAction runs unchanged.
void runsWhenStrictModeCliWritesOutput() {
  test('runs postJSAction when the strict-mode CLI writes the output file',
      () async {
    final h = await _harness(
      cliCommands: [
        'mkdir -p outputs && '
            'printf "generated answer" > outputs/$responseFileName',
      ],
      requireCliOutputFile: true,
    );
    try {
      final result = await h.agent.run();
      expect((await h.postLog.readAsString()).trim(), 'generated answer');
      expect(result['response'], 'generated answer');
    } finally {
      await h.dispose();
    }
  });
}

/// The guard is strict-mode only — permissive mode stays backwards compatible.
void stillRunsInPermissiveModeWithoutOutput() {
  test('still runs postJSAction in permissive mode without an output file',
      () async {
    final h = await _harness(
      cliCommands: ['exit 7'],
      requireCliOutputFile: false,
    );
    try {
      await h.agent.run();
      expect(
        h.postLog.existsSync(),
        isTrue,
        reason: 'the guard applies to strict mode only '
            '(requireCliOutputFile=false is backwards compatible)',
      );
    } finally {
      await h.dispose();
    }
  });
}

/// The Java skipFieldUpdate condition ignores the exit code: strict mode +
/// no output response skips postJSAction even on a clean exit.
void skipsInStrictModeEvenOnZeroExit() {
  test('skips postJSAction in strict mode even on a zero exit code', () async {
    final h = await _harness(
      cliCommands: ['echo finished but forgot the output file'],
      requireCliOutputFile: true,
    );
    try {
      await h.agent.run();
      expect(
        h.postLog.existsSync(),
        isFalse,
        reason: 'the Java skipFieldUpdate condition is strict mode + no '
            'output response, regardless of the exit code',
      );
    } finally {
      await h.dispose();
    }
  });
}

/// Agent under test plus the postJSAction spy log.
class _Harness {
  _Harness(this.agent, this.postLog, this.tmpDir);

  /// The agent configured with a postJSAction that writes the response (or
  /// `ran` when there is none) to [postLog].
  final CliAgent agent;

  /// The spy log — its existence proves postJSAction ran.
  final File postLog;

  /// Temporary working directory.
  final Directory tmpDir;

  Future<void> dispose() => tmpDir.delete(recursive: true);
}

/// Builds an agent whose postJSAction records its invocation in a temp log.
Future<_Harness> _harness({
  required List<String> cliCommands,
  required bool requireCliOutputFile,
}) async {
  final tmp = await Directory.systemTemp.createTemp('cli_strict_mode_test_');
  final log = File('${tmp.path}/post.log');
  final js = File('${tmp.path}/post_cb.js')
    ..writeAsStringSync(
      'function action(params) { '
      'file_write({path: "${log.path}", '
      'content: String(params.response || "ran")}); }',
    );
  final agent = CliAgent(
    params: CliAgentParams()
      ..cliCommands = cliCommands
      ..requireCliOutputFile = requireCliOutputFile
      ..postJSAction = js.path
      ..cleanupInputFolder = false,
    workingDirectory: tmp.path,
  );
  return _Harness(agent, log, tmp);
}
