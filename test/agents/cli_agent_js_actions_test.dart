/// Tests for the CliAgent JS-action surface — setup/preCli/post JS hooks,
/// the timer/error/line context actions, and the action() contract enforced
/// by JsJobRunner (Java `JobJavaScriptBridge` parity).
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  lifecycleJsActionTests();
  timerJsActionTests();
  cliErrorJsActionTests();
  cliOutputLineJsActionTests();
}

// ======================================================================
// AgentFactory
// ======================================================================

void lifecycleJsActionTests() {
  group('CliAgent JS actions', () {
    test('setup .js hook is executed via JsJobRunner', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_setup.log';
      try {
        final js = _actionJs(
          tmp,
          'setup_hook.js',
          'file_write({path: "$log", content: "ran"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..setup = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect((await File(log).readAsString()).trim(), 'ran');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('preCliJSAction is executed via JsJobRunner', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_precli.log';
      try {
        final js = _actionJs(
          tmp,
          'pre_cli.js',
          'file_write({path: "$log", content: "ok"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..preCliJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect((await File(log).readAsString()).trim(), 'ok');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

// ======================================================================
// CliAgent — context JS actions (timer / error / line)
// ======================================================================

void timerJsActionTests() {
  group('CliAgent timerJSAction', () {
    test('fires during execution and on final tick', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/timer.log';
      try {
        final js = _actionJs(
          tmp,
          'timer.js',
          'file_append({path: "$log", '
              'content: "len=" + currentCliOutput.length + "\\n"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            // 4s window for a 1s interval: ≥1 periodic tick lands even when
            // the suite's parallel load delays timer delivery past 1–2s.
            ..cliCommands = ['sleep 4; echo done']
            ..timerJSAction = js.path
            ..timerIntervalSeconds = 1
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        final lines = (await File(log).readAsString())
            .trim()
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList();
        // At least one periodic tick (during the 2s command) + the final tick.
        expect(lines.length, greaterThanOrEqualTo(2));
        // The final tick runs after the batch, so it sees the full output.
        expect(lines.last, isNot('len=0'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void cliErrorJsActionTests() {
  group('CliAgent cliExecutionErrorJSAction', () {
    test('runs with errorMessage on failure', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/error.log';
      try {
        final js = _actionJs(
          tmp,
          'error.js',
          'file_write({path: "$log", content: errorMessage});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['exit 7']
            ..cliExecutionErrorJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect((await File(log).readAsString()), contains('exit code 7'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('is skipped on success', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/error_ok.log';
      try {
        final js = _actionJs(
          tmp,
          'error_ok.js',
          'file_write({path: "$log", content: "ran"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ok']
            ..cliExecutionErrorJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(File(log).existsSync(), isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void cliOutputLineJsActionTests() {
  group('CliAgent cliOutputLineJSAction', () {
    test('runs for each output line', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/lines.log';
      try {
        final js = _actionJs(
          tmp,
          'lines.js',
          'file_append({path: "$log", content: line + "\\n"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ["printf 'a\\nb\\nc\\n'"]
            ..cliOutputLineJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(
          (await File(log).readAsString()).trim().split('\n'),
          ['a', 'b', 'c'],
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('returning true stops the batch', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/stop.log';
      final marker = File('${tmp.path}/marker');
      try {
        final js = File('${tmp.path}/stop.js');
        await js.writeAsString(
          'function action(params) {'
          '  file_append({path: "$log", content: line + "\\n"});'
          '  return line === "stop";'
          '}',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ["printf 'go\\nstop\\n'", 'echo ran > marker']
            ..cliOutputLineJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        // The action saw "go" then "stop" (which triggered the stop).
        expect((await File(log).readAsString()).trim().split('\n'),
            ['go', 'stop']);
        // The second command never ran because the batch was aborted.
        expect(marker.existsSync(), isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

/// Writes a JS hook script wrapped in the action() contract enforced by
/// [JsJobRunner.runScript] (Java `JobJavaScriptBridge` parity).
File _actionJs(Directory dir, String name, String body) =>
    File('${dir.path}/$name')
      ..writeAsStringSync('function action(params) { $body }');

Future<Directory> _createTempDir() async {
  return Directory.systemTemp.createTemp('cli_agent_test_');
}
