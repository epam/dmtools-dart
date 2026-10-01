/// Tests for the CliAgent JS-action surface — setup/preCli/post JS hooks,
/// the timer/error/line context actions, and the action() contract enforced
/// by JsJobRunner (Java `JobJavaScriptBridge` parity).
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  lifecycleJsActionTests();
  ticketContextJsActionTests();
  metadataBindingJsActionTests();
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

void ticketContextJsActionTests() {
  group('CliAgent JS actions — ticket context', () {
    test('JS actions see params.ticket from ticketData', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_ticket.log';
      try {
        final js = _actionJs(
          tmp,
          'post.js',
          'file_write({path: "$log", content: params.ticket.key});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..postJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          ticketData: const {
            'key': 'GH-21',
            'fields': {'summary': 's'},
          },
        )).run();
        expect((await File(log).readAsString()).trim(), 'GH-21');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

// ======================================================================
// CliAgent — top-level metadata binding (epam/dm.ai#623 parity)
// ======================================================================

void metadataBindingJsActionTests() {
  group('CliAgent JS actions — metadata binding', () {
    test('preJSAction and postJSAction see params.metadata', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_metadata.log';
      try {
        final pre = _actionJs(
          tmp,
          'pre_meta.js',
          'file_append({path: "$log", content: "pre=" + '
              'params.metadata.contextId + ":" + params.metadata.agentId '
              '+ "\\n"});',
        );
        final post = _actionJs(
          tmp,
          'post_meta.js',
          'file_append({path: "$log", content: "post=" + '
              'params.metadata.contextId + ":" + params.metadata.agentId '
              '+ "\\n"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..metadata = const {'contextId': 'ctx-123', 'agentId': 'agent-1'}
            ..preJSAction = pre.path
            ..postJSAction = post.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(
          (await File(log).readAsString()).trim().split('\n'),
          ['pre=ctx-123:agent-1', 'post=ctx-123:agent-1'],
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('preCliJSAction sees params.metadata.contextId', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_precli_meta.log';
      try {
        final js = _actionJs(
          tmp,
          'pre_cli_meta.js',
          'file_write({path: "$log", content: params.metadata.contextId});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..metadata = const {'contextId': 'gh-317', 'agentId': 'senior'}
            ..preCliJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect((await File(log).readAsString()).trim(), 'gh-317');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('timerJSAction sees params.metadata.contextId', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_timer_meta.log';
      try {
        final js = _actionJs(
          tmp,
          'timer_meta.js',
          'file_write({path: "$log", content: params.metadata.contextId});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..metadata = const {'contextId': 'ctx-timer'}
            ..timerJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        // The final tick always runs after the batch, so this is
        // deterministic even though no periodic tick fits in the batch.
        expect((await File(log).readAsString()).trim(), 'ctx-timer');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('params.metadata stays undefined when the job has no metadata',
        () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/js_no_meta.log';
      try {
        final js = _actionJs(
          tmp,
          'post_no_meta.js',
          'file_write({path: "$log", content: typeof params.metadata});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..postJSAction = js.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        // Java null-omission parity: no key instead of a null value.
        expect((await File(log).readAsString()).trim(), 'undefined');
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
