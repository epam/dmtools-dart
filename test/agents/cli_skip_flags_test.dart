/// Tests for the CliAgent JS-action skip flags (gh-319, Java epam/dm.ai#266
/// parity): `skipPreJSAction` / `skipPreCliJSAction` / `skipPostJSAction`
/// each guard the corresponding hook invocation. Defaults preserve the
/// existing behavior (all hooks run); a set flag prevents only its own hook
/// and composes with the strict-mode postJSAction skip (gh-316).
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  skipPreJSActionTests();
  skipPreCliJSActionTests();
  skipPostJSActionTests();
  skipFlagDefaultsTests();
  skipFlagCompositionTests();
  skipFlagParsingTests();
}

// ======================================================================
// Each flag prevents exactly its own hook
// ======================================================================

void skipPreJSActionTests() {
  group('CliAgent skipPreJSAction', () {
    test('skips the preJSAction hook when set', () async {
      final h = await _harness(
        skipPreJSAction: true,
      );
      try {
        final result = await h.agent.run();
        expect(
          h.preLog.existsSync(),
          isFalse,
          reason: 'skipPreJSAction=true must prevent the preJSAction hook',
        );
        expect(result['success'], isTrue,
            reason: 'a skipped hook is not a failed run');
      } finally {
        await h.dispose();
      }
    });

    test('runs the preJSAction hook when unset (default)', () async {
      final h = await _harness();
      try {
        await h.agent.run();
        expect(h.preLog.existsSync(), isTrue);
      } finally {
        await h.dispose();
      }
    });
  });
}

void skipPreCliJSActionTests() {
  group('CliAgent skipPreCliJSAction', () {
    test('skips the preCliJSAction hook when set', () async {
      final h = await _harness(
        skipPreCliJSAction: true,
      );
      try {
        final result = await h.agent.run();
        expect(
          h.preCliLog.existsSync(),
          isFalse,
          reason:
              'skipPreCliJSAction=true must prevent the preCliJSAction hook',
        );
        expect(result['success'], isTrue);
      } finally {
        await h.dispose();
      }
    });

    test('runs the preCliJSAction hook when unset (default)', () async {
      final h = await _harness();
      try {
        await h.agent.run();
        expect(h.preCliLog.existsSync(), isTrue);
      } finally {
        await h.dispose();
      }
    });

    test('does not stop the CLI commands from running', () async {
      final h = await _harness(skipPreCliJSAction: true);
      try {
        final result = await h.agent.run();
        expect(result['response'], contains('done'));
      } finally {
        await h.dispose();
      }
    });
  });
}

void skipPostJSActionTests() {
  group('CliAgent skipPostJSAction', () {
    test('skips the postJSAction hook when set', () async {
      final h = await _harness(
        skipPostJSAction: true,
      );
      try {
        final result = await h.agent.run();
        expect(
          h.postLog.existsSync(),
          isFalse,
          reason: 'skipPostJSAction=true must prevent the postJSAction hook',
        );
        expect(result['success'], isTrue);
      } finally {
        await h.dispose();
      }
    });

    test('runs the postJSAction hook when unset (default)', () async {
      final h = await _harness();
      try {
        await h.agent.run();
        expect(h.postLog.existsSync(), isTrue);
      } finally {
        await h.dispose();
      }
    });
  });
}

// ======================================================================
// Defaults preserve existing behavior — all hooks fire together
// ======================================================================

void skipFlagDefaultsTests() {
  group('CliAgent skip flags — defaults', () {
    test('all three hooks run when no skip flag is set', () async {
      final h = await _harness();
      try {
        await h.agent.run();
        expect(h.preLog.existsSync(), isTrue, reason: 'preJSAction ran');
        expect(h.preCliLog.existsSync(), isTrue, reason: 'preCliJSAction ran');
        expect(h.postLog.existsSync(), isTrue, reason: 'postJSAction ran');
      } finally {
        await h.dispose();
      }
    });

    test('fromJson defaults every flag to false', () {
      final params = CliAgentParams.fromJson({
        'cliCommands': ['echo'],
      });
      expect(params.skipPreJSAction, isFalse);
      expect(params.skipPreCliJSAction, isFalse);
      expect(params.skipPostJSAction, isFalse);
    });
  });
}

// ======================================================================
// Composition with the strict-mode postJSAction skip (gh-316)
// ======================================================================

void skipFlagCompositionTests() {
  group('CliAgent skip flags — composition', () {
    test('skipPostJSAction composes with the strict-mode guard', () async {
      // Strict mode + missing output file already skips postJSAction; the
      // flag must not crash or double-run anything, and the strict-mode
      // error summary still reports the failure.
      final h = await _harness(
        skipPostJSAction: true,
        requireCliOutputFile: true,
        cliCommands: ['echo crashed && exit 7'],
      );
      try {
        final result = await h.agent.run();
        expect(h.postLog.existsSync(), isFalse);
        expect(
          result['response'],
          startsWith('CLI command executed but did not produce output file'),
        );
      } finally {
        await h.dispose();
      }
    });

    test('a set flag with no hook configured does not fail the run', () async {
      final tmp = await Directory.systemTemp.createTemp('cli_skip_test_');
      try {
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..skipPreJSAction = true
            ..skipPreCliJSAction = true
            ..skipPostJSAction = true
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(result['success'], isTrue);
        expect(result['response'], contains('done'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

// ======================================================================
// CliAgentParams.fromJson parsing
// ======================================================================

void skipFlagParsingTests() {
  group('CliAgentParams.fromJson — skip flags', () {
    test('parses all three flags from JSON', () {
      final params = CliAgentParams.fromJson({
        'cliCommands': ['echo'],
        'skipPreJSAction': true,
        'skipPreCliJSAction': true,
        'skipPostJSAction': true,
      });
      expect(params.skipPreJSAction, isTrue);
      expect(params.skipPreCliJSAction, isTrue);
      expect(params.skipPostJSAction, isTrue);
    });

    test('parses string booleans like the other flags', () {
      final params = CliAgentParams.fromJson({
        'skipPostJSAction': 'true',
      });
      expect(params.skipPostJSAction, isTrue);
    });
  });
}

// ======================================================================
// Harness
// ======================================================================

/// Agent under test plus the three hook spy logs.
class _Harness {
  _Harness(this.agent, this.preLog, this.preCliLog, this.postLog, this.tmpDir);

  /// The agent configured with the three JS hooks, each recording its
  /// invocation in its own temp log.
  final CliAgent agent;

  /// preJSAction spy log — its existence proves the hook ran.
  final File preLog;

  /// preCliJSAction spy log.
  final File preCliLog;

  /// postJSAction spy log.
  final File postLog;

  /// Temporary working directory.
  final Directory tmpDir;

  Future<void> dispose() => tmpDir.delete(recursive: true);
}

/// Builds an agent whose preJSAction / preCliJSAction / postJSAction each
/// write an invocation marker to a temp log file.
Future<_Harness> _harness({
  bool skipPreJSAction = false,
  bool skipPreCliJSAction = false,
  bool skipPostJSAction = false,
  bool requireCliOutputFile = false,
  List<String> cliCommands = const ['echo done'],
}) async {
  final tmp = await Directory.systemTemp.createTemp('cli_skip_test_');
  File spy(String name) {
    final log = File('${tmp.path}/$name.log');
    File('${tmp.path}/$name.js').writeAsStringSync(
      'function action(params) { '
      'file_write({path: "${log.path}", '
      'content: String(params.response || "ran")}); }',
    );
    return log;
  }

  final preLog = spy('pre');
  final preCliLog = spy('precli');
  final postLog = spy('post');
  final agent = CliAgent(
    params: CliAgentParams()
      ..cliCommands = cliCommands
      ..requireCliOutputFile = requireCliOutputFile
      ..skipPreJSAction = skipPreJSAction
      ..skipPreCliJSAction = skipPreCliJSAction
      ..skipPostJSAction = skipPostJSAction
      ..preJSAction = preLog.path.replaceAll(RegExp(r'\.log$'), '.js')
      ..preCliJSAction = preCliLog.path.replaceAll(RegExp(r'\.log$'), '.js')
      ..postJSAction = postLog.path.replaceAll(RegExp(r'\.log$'), '.js')
      ..cleanupInputFolder = false,
    workingDirectory: tmp.path,
  );
  return _Harness(agent, preLog, preCliLog, postLog, tmp);
}
