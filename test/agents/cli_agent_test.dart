/// Tests for the Phase 5 CliAgent port — parameter parsing, command builder,
/// execution helper, lifecycle order, cleanup, and factory dispatch.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  paramsParsingTests();
  paramsContextIdTests();
  paramsCliPromptsTests();
  resolveCliPromptsTests();
  buildCommandsTests();
  filterEnvTests();
  executeCommandsTests();
  readOutputResponseTests();
  lifecycleOrderTests();
  lifecycleInputCleanupTests();
  lifecycleFolderCleanupTests();
  lifecycleContextTests();
  lifecycleEnvTests();
  lifecycleJsActionTests();
  timerJsActionTests();
  cliErrorJsActionTests();
  cliOutputLineJsActionTests();
  factoryTests();
}

// ======================================================================
// CliAgentParams — parsing
// ======================================================================

void paramsParsingTests() {
  group('CliAgentParams.fromJson', () {
    test('parses all fields from JSON', () {
      final params = CliAgentParams.fromJson({
        'cliCommands': ['echo hello', 'echo world'],
        'cliPrompt': 'Do the thing',
        'setup': 'make setup',
        'cache': 'make cache',
        'reset': 'make reset',
        'preCliJSAction': 'pre.js',
        'cleanupInputFolder': false,
        'requireCliOutputFile': true,
        'workingDirectory': '/tmp/work',
        'timerIntervalSeconds': 30,
        'cleanupOutputsFolder': true,
        'envVariables': {'KEY': 'value'},
        'metadata': {'contextId': 'my-job'},
      });
      expect(params.cliCommands, ['echo hello', 'echo world']);
      expect(params.cliPrompt, 'Do the thing');
      expect(params.cleanupInputFolder, isFalse);
      expect(params.timerIntervalSeconds, 30);
      expect(params.envVariables, {'KEY': 'value'});
    });

    test('applies correct defaults', () {
      final params = CliAgentParams.fromJson({
        'cliCommands': ['echo']
      });
      expect(params.cleanupInputFolder, isTrue);
      expect(params.requireCliOutputFile, isFalse);
      expect(params.cleanupOutputsFolder, isFalse);
      expect(params.timerIntervalSeconds, 60);
    });

    test('parses excludedEnvVariables and regex', () {
      final params = CliAgentParams.fromJson({
        'excludedEnvVariables': ['SECRET', 'TOKEN'],
        'excludeEnvVariablesByRegex': ['^_.*'],
      });
      expect(params.excludedEnvVariables, ['SECRET', 'TOKEN']);
      expect(params.excludeEnvVariablesByRegex, ['^_.*']);
    });

    test('parses cliPromptsByTracker', () {
      final params = CliAgentParams.fromJson({
        'cliPromptsByTracker': {
          'jira': ['j1', 'j2'],
          'ado': ['a1'],
        },
      });
      expect(params.cliPromptsByTracker?['jira'], ['j1', 'j2']);
      expect(params.cliPromptsByTracker?['ado'], ['a1']);
    });
  });
}

void paramsContextIdTests() {
  group('CliAgentParams.contextId', () {
    test('reads contextId from metadata', () {
      expect(
        CliAgentParams.fromJson({
          'metadata': {'contextId': 'job-1'}
        }).contextId,
        'job-1',
      );
    });

    test('falls back to cli-agent', () {
      expect(CliAgentParams.fromJson({}).contextId, 'cli-agent');
      expect(CliAgentParams.fromJson({'metadata': {}}).contextId, 'cli-agent');
    });
  });
}

void paramsCliPromptsTests() {
  group('CliAgentParams.cliPromptsAsArray', () {
    test('flattens structured config', () {
      final params = CliAgentParams.fromJson({
        'cliPrompts': [
          'plain',
          {
            'id': 's1',
            'prompts': ['a', 'b']
          },
        ],
      });
      expect(params.cliPromptsAsArray, ['plain', 'a', 'b']);
    });

    test('handles flat string array', () {
      final params = CliAgentParams.fromJson({
        'cliPrompts': ['x', 'y']
      });
      expect(params.cliPromptsAsArray, ['x', 'y']);
    });

    test('returns null when absent', () {
      expect(CliAgentParams.fromJson({}).cliPromptsAsArray, isNull);
    });
  });
}

// ======================================================================
// CliCommandBuilder
// ======================================================================

void resolveCliPromptsTests() {
  group('CliCommandBuilder.resolveCliPrompts', () {
    test('merges base with matching tracker prompts', () {
      expect(
        CliCommandBuilder.resolveCliPrompts(
          ['base1'],
          {
            'jira': ['j1', 'j2']
          },
          'jira',
        ),
        ['base1', 'j1', 'j2'],
      );
    });

    test('returns base when tracker not found', () {
      expect(
        CliCommandBuilder.resolveCliPrompts([
          'b'
        ], {
          'jira': ['j']
        }, 'ado'),
        ['b'],
      );
    });

    test('defaults to ado when tracker is null', () {
      expect(
        CliCommandBuilder.resolveCliPrompts([
          'b'
        ], {
          'ado': ['a']
        }, null),
        ['b', 'a'],
      );
    });
  });
}

void buildCommandsTests() {
  group('CliCommandBuilder.buildCommands', () {
    test('returns original commands when no prompt', () {
      final result = const CliCommandBuilder().buildCommands(
        ['echo hello'],
        null,
        null,
        null,
      );
      expect(result, ['echo hello']);
    });

    test('appends prompt file path when prompt provided', () {
      final result = const CliCommandBuilder().buildCommands(
        ['echo a', 'echo b'],
        'Do X',
        null,
        null,
      );
      expect(result, hasLength(2));
      expect(result[0], startsWith('echo a "'));
      expect(result[0], endsWith('.txt"'));
    });

    test('returns original when cliCommands empty', () {
      expect(const CliCommandBuilder().buildCommands([], 'p', null, null), []);
    });
  });
}

// ======================================================================
// CliExecutionHelper
// ======================================================================

void filterEnvTests() {
  group('CliExecutionHelper.filterEnvVariables', () {
    test('removes exact-name exclusions', () {
      final f = CliExecutionHelper.filterEnvVariables(
        {'A': '1', 'B': '2', 'S': 'x'},
        ['S'],
        null,
      );
      expect(f.containsKey('S'), isFalse);
      expect(f['A'], '1');
    });

    test('removes regex-matched keys', () {
      final f = CliExecutionHelper.filterEnvVariables(
        {'_X': '1', 'P': '2'},
        null,
        ['^_.*'],
      );
      expect(f.containsKey('_X'), isFalse);
      expect(f['P'], '2');
    });

    test('returns original when no filters', () {
      final orig = {'A': '1'};
      expect(
        CliExecutionHelper.filterEnvVariables(orig, null, null),
        same(orig),
      );
    });
  });
}

void executeCommandsTests() {
  group('CliExecutionHelper.executeCommands', () {
    test('captures successful output', () async {
      final r = await const CliExecutionHelper().executeCommands(
        ['echo hello_world'],
      );
      expect(r.commandResponses, contains('hello_world'));
      expect(r.hasFatalError, isFalse);
    });

    test('tracks fatal error on failure', () async {
      final r = await const CliExecutionHelper().executeCommands(['exit 42']);
      expect(r.hasFatalError, isTrue);
      expect(r.lastExitCode, 42);
    });
  });
}

void readOutputResponseTests() {
  group('CliExecutionHelper.readOutputResponse', () {
    test('prefers outputs/ when outputsFirst', () async {
      final tmp = await _createTempDir();
      try {
        await _writeResponse(tmp.path, 'outputs', 'from-outputs');
        await _writeResponse(tmp.path, 'output', 'from-legacy');
        final r = const CliExecutionHelper().readOutputResponse(
          tmp.path,
          OutputFolderPreference.outputsFirst,
        );
        expect(r, 'from-outputs');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('falls back to legacy folder', () async {
      final tmp = await _createTempDir();
      try {
        await _writeResponse(tmp.path, 'output', 'from-legacy');
        final r = const CliExecutionHelper().readOutputResponse(
          tmp.path,
          OutputFolderPreference.outputsFirst,
        );
        expect(r, 'from-legacy');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('returns null when neither exists', () {
      expect(
        const CliExecutionHelper().readOutputResponse(
          '/nonexistent',
          OutputFolderPreference.outputsFirst,
        ),
        isNull,
      );
    });
  });
}

// ======================================================================
// CliAgent lifecycle
// ======================================================================

void lifecycleOrderTests() {
  group('CliAgent lifecycle order', () {
    test('executes setup → cliCommands → cache → reset', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/order.log';
      try {
        final agent = CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo cli >> "$log"']
            ..setup = 'echo setup >> "$log"'
            ..cache = 'echo cache >> "$log"'
            ..reset = 'echo reset >> "$log"'
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        );
        final result = await agent.run();
        expect(result['success'], isTrue);
        final lines = (await File(log).readAsString()).trim().split('\n');
        expect(lines, ['setup', 'cli', 'cache', 'reset']);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('reset runs even on failure', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/fail.log';
      try {
        await File('${tmp.path}/input/cli-agent').create(recursive: true);
        final agent = CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo cli >> "$log"']
            ..reset = 'echo reset >> "$log"'
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        );
        expect((await agent.run())['success'], isFalse);
        expect((await File(log).readAsString()).trim(), 'reset');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void lifecycleInputCleanupTests() {
  group('CliAgent input cleanup', () {
    test('cleanupInputFolder deletes input folder', () async {
      final tmp = await _createTempDir();
      try {
        await (CliAgent(
          params: CliAgentParams()..cliCommands = ['echo done'],
          workingDirectory: tmp.path,
        )).run();
        expect(
          Directory('${tmp.path}/input/cli-agent').existsSync(),
          isFalse,
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('cleanupInputFolder=false keeps input folder', () async {
      final tmp = await _createTempDir();
      try {
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(
          Directory('${tmp.path}/input/cli-agent').existsSync(),
          isTrue,
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void lifecycleFolderCleanupTests() {
  group('CliAgent folder cleanup', () {
    test('cleanupOutputsFolder deletes outputs folder', () async {
      final tmp = await _createTempDir();
      try {
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..cleanupOutputsFolder = true,
          workingDirectory: tmp.path,
        )).run();
        expect(Directory('${tmp.path}/outputs').existsSync(), isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('clears stale outputs/response.md on start', () async {
      final tmp = await _createTempDir();
      try {
        await _writeResponse(tmp.path, 'outputs', 'stale');
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(
          File('${tmp.path}/outputs/$responseFileName').existsSync(),
          isFalse,
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void lifecycleContextTests() {
  group('CliAgent context', () {
    test('uses contextId from metadata', () async {
      final tmp = await _createTempDir();
      try {
        final agent = CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..metadata = {'contextId': 'custom-ctx'}
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        );
        expect((await agent.run())['contextId'], 'custom-ctx');
        expect(
          Directory('${tmp.path}/input/custom-ctx').existsSync(),
          isTrue,
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('defaults to cli-agent contextId', () async {
      final tmp = await _createTempDir();
      try {
        final agent = CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        );
        expect((await agent.run())['contextId'], 'cli-agent');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('returns early when cliCommands empty', () async {
      final result = await CliAgent(
        params: CliAgentParams()..cliCommands = const [],
      ).run();
      expect(result['success'], isTrue);
      expect(result['message'], contains('No cliCommands'));
    });
  });
}

void lifecycleEnvTests() {
  group('CliAgent env', () {
    test('sets envVariables overrides for subprocesses', () async {
      final tmp = await _createTempDir();
      final log = '${tmp.path}/env.log';
      try {
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo \$MY_VAR >> "$log"']
            ..envVariables = {'MY_VAR': 'injected-value'}
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect((await File(log).readAsString()).trim(), 'injected-value');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
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
        final js = File('${tmp.path}/setup_hook.js');
        await js.writeAsString('file_write({path: "$log", content: "ran"});');
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
        final js = File('${tmp.path}/pre_cli.js');
        await js.writeAsString('file_write({path: "$log", content: "ok"});');
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
        final js = File('${tmp.path}/timer.js');
        await js.writeAsString(
          'file_append({path: "$log", '
          'content: "len=" + currentCliOutput.length + "\\n"});',
        );
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['sleep 2; echo done']
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
        final js = File('${tmp.path}/error.js');
        await js.writeAsString(
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
        final js = File('${tmp.path}/error_ok.js');
        await js.writeAsString(
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
        final js = File('${tmp.path}/lines.js');
        await js.writeAsString(
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

// ======================================================================
// AgentFactory
// ======================================================================

void factoryTests() {
  group('AgentFactory.create', () {
    test('creates CliAgent for cliagent', () {
      expect(
        AgentFactory.create('cliagent', {
          'cliCommands': ['echo']
        }),
        isA<CliAgent>(),
      );
    });

    test('creates JsRunnerJob for jsrunner', () {
      expect(
        AgentFactory.create('jsrunner', {'jsPath': 't.js'}),
        isA<JsRunnerJob>(),
      );
    });

    test('matches case-insensitively', () {
      expect(
        AgentFactory.create('CLIAGENT', {
          'cliCommands': ['echo']
        }),
        isA<CliAgent>(),
      );
    });

    test('throws ArgumentError for unknown', () {
      expect(() => AgentFactory.create('nope', {}), throwsArgumentError);
    });
  });
}

// ======================================================================
// Helpers
// ======================================================================

/// Creates a unique temporary directory.
Future<Directory> _createTempDir() async {
  return Directory.systemTemp.createTemp('cli_agent_test_');
}

/// Writes a response file into a subfolder of [baseDir].
Future<void> _writeResponse(String baseDir, String folder, String content) {
  final file = File('$baseDir/$folder/$responseFileName');
  return file.create(recursive: true).then((_) => file.writeAsString(content));
}
