/// Unit tests for [CliDispatcher].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;
late List<String> _lines;
late CliDispatcher _dispatcher;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_cli_');
    PropertyReader.setOverrides({});
    _lines = [];
    _dispatcher = CliDispatcher(
      writer: _lines.add,
      propertyReader: PropertyReader(basePath: _tmp.path),
      isTty: () => false,
    );
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testVersion();
  _testHelp();
  _testListJobs();
  _testDoctor();
  _testRun();
  _testRunJsFile();
  _testRunCliAgent();
  _testList();
  _testInteractive();
  _testDirectTool();
  _testNoArgs();
  _testDefaults();
}

void _testVersion() {
  group('--version', () {
    test('prints the version banner', () async {
      expect(await _dispatcher.dispatch(['--version']), 0);
      expect(
        _lines,
        [
          'DMTools $dmtoolsVersion',
          'A comprehensive development management toolkit'
        ],
      );
    });

    test('-v alias matches', () async {
      expect(await _dispatcher.dispatch(['-v']), 0);
      expect(_lines.first, 'DMTools $dmtoolsVersion');
    });
  });
}

void _testHelp() {
  group('--help', () {
    test('prints the Java help text', () async {
      expect(await _dispatcher.dispatch(['--help']), 0);
      expect(_lines.join('\n'), CliDispatcher.helpText);
      expect(_lines.join('\n'), startsWith('DMTools CLI Wrapper'));
    });

    test('-h and help aliases match --help', () async {
      expect(await _dispatcher.dispatch(['-h']), 0);
      final viaH = _lines.join('\n');
      _lines.clear();
      expect(await _dispatcher.dispatch(['help']), 0);
      expect(_lines.join('\n'), viaH);
      expect(
        _lines.join('\n'),
        contains('dmtools jira_get_ticket DMC-479 summary,description'),
      );
    });
  });
}

void _testListJobs() {
  group('--list-jobs', () {
    test('prints every display job and the total', () async {
      expect(await _dispatcher.dispatch(['--list-jobs']), 0);
      expect(_lines.first, 'Available Jobs:');
      expect(_lines[1], '===============');
      expect(_lines[2], '- presalesupport');
      expect(_lines.last, 'Total: 23 jobs available');
      expect(
        _lines.last,
        'Total: ${JobRegistry.displayJobs.length} jobs available',
      );
    });
  });
}

void _testDoctor() {
  group('doctor', () {
    test('prints the configuration check report', () async {
      expect(await _dispatcher.dispatch(['doctor']), 0);
      final out = _lines.join('\n');
      expect(out, startsWith('DMTools Configuration Check'));
      expect(out, contains('Integrations ready: '));
    });

    test('reflects dmtools.env from the working directory', () async {
      File('${_tmp.path}/dmtools.env')
          .writeAsStringSync('SOURCE_GITHUB_TOKEN=ghp_test\n');
      expect(await _dispatcher.dispatch(['doctor']), 0);
      expect(
        _lines.join('\n'),
        contains('✓ github - GitHub authentication configured'),
      );
    });
  });
}

void _testRun() {
  group('run', () {
    test('rejects a non-existent config file', () async {
      expect(await _dispatcher.dispatch(['run', 'job-config.json']), 1);
      expect(_lines, ['Error: Config file not found: job-config.json']);
    });

    test('attempts execution of a known-but-unsupported job name', () async {
      // codegenerator resolves as a known job, but AgentFactory has no
      // registered agent for it — the dispatcher attempts execution and
      // surfaces the ArgumentError.
      expect(
        await _dispatcher
            .dispatch(['run', 'codegenerator', '--param1', 'test']),
        1,
      );
      expect(_lines.last, contains('Unknown job: codegenerator'));
    });

    test('rejects a non-existent config file with encoded overrides', () async {
      expect(
          await _dispatcher.dispatch(['run', 'job.json', 'encoded-blob']), 1);
      expect(_lines, ['Error: Config file not found: job.json']);
    });

    test('rejects run without a target', () async {
      expect(await _dispatcher.dispatch(['run']), 1);
      expect(_lines.first, contains('Error:'));
    });
  });
}

void _testRunJsFile() {
  group('run <file>.js', () {
    test('runs a simple JS expression file', () async {
      final jsFile = File('${_tmp.path}/hello.js')..writeAsStringSync('1 + 2');
      expect(await _dispatcher.dispatch(['run', jsFile.path]), 0);
      expect(_lines.last, '3');
    });

    test('runs a JS file with an action(params) function', () async {
      final jsFile = File('${_tmp.path}/action.js')
        ..writeAsStringSync(
          "function action(params) { return { greeting: 'hello' }; }",
        );
      expect(await _dispatcher.dispatch(['run', jsFile.path]), 0);
      final decoded = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(decoded['greeting'], 'hello');
    });

    test('passes --key overrides as jobParams', () async {
      final jsFile = File('${_tmp.path}/params.js')
        ..writeAsStringSync('params.jobParams.name');
      expect(
        await _dispatcher.dispatch(['run', jsFile.path, '--name', 'world']),
        0,
      );
      expect(jsonDecode(_lines.last), 'world');
    });
  });
}

void _testRunCliAgent() {
  group('run <cliagent-config>.json', () {
    test('executes a cliagent job and returns 0 on success', () async {
      final configFile = File('${_tmp.path}/agent.json')
        ..writeAsStringSync(jsonEncode({
          'name': 'cliagent',
          'params': {
            'cliCommands': ['echo done'],
            'workingDirectory': _tmp.path,
            'cleanupInputFolder': false,
          },
        }));
      final code = await _dispatcher.dispatch(['run', configFile.path]);
      expect(code, 0);
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['success'], isTrue);
    });
  });
}

void _testList() {
  group('list', () {
    test('prints the full MCP tool catalog as JSON', () async {
      expect(await _dispatcher.dispatch(['list']), 0);
      final decoded = jsonDecode(_lines.join('\n')) as Map<String, dynamic>;
      final tools = decoded['tools'] as List;
      expect(tools.length, greaterThan(250));
      final names = tools
          .map((t) => (t as Map<String, dynamic>)['name'] as String)
          .toSet();
      expect(names, contains('jira_get_ticket'));
      expect(names, contains('github_create_pr'));
    });

    test('filters the catalog by a case-insensitive substring', () async {
      expect(await _dispatcher.dispatch(['list', 'COMMENT']), 0);
      final decoded = jsonDecode(_lines.join('\n')) as Map<String, dynamic>;
      final tools = decoded['tools'] as List;
      expect(tools, isNotEmpty);
      for (final t in tools) {
        final map = t as Map<String, dynamic>;
        final matches = (map['name'] as String)
                .toLowerCase()
                .contains('comment') ||
            (map['description'] as String).toLowerCase().contains('comment');
        expect(matches, isTrue);
      }
    });

    test('honors the DMTOOLS_INTEGRATIONS filter', () async {
      PropertyReader.setOverrides({'DMTOOLS_INTEGRATIONS': 'jira'});
      expect(await _dispatcher.dispatch(['list']), 0);
      final decoded = jsonDecode(_lines.join('\n')) as Map<String, dynamic>;
      final tools = decoded['tools'] as List;
      expect(tools, isNotEmpty);
      for (final t in tools) {
        expect((t as Map<String, dynamic>)['integration'], 'jira');
      }
    });
  });
}

void _testInteractive() {
  group('interactive', () {
    test('stubs interactive mode', () async {
      expect(await _dispatcher.dispatch(['interactive']), 1);
      expect(_lines, ['Interactive mode requires Phase 4 (terminal picker)']);
    });

    test('i alias matches', () async {
      expect(await _dispatcher.dispatch(['i']), 1);
      expect(_lines, ['Interactive mode requires Phase 4 (terminal picker)']);
    });
  });
}

void _testDirectTool() {
  group('direct tool invocation', () {
    test('executes a file tool with JSON args', () async {
      final testFile = File('${_tmp.path}/hello.txt')
        ..writeAsStringSync('hello world');
      expect(
        await _dispatcher.dispatch([
          'file_read',
          jsonEncode({'path': testFile.path}),
        ]),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'hello world');
    });

    test('executes a file tool with --data flag', () async {
      final testFile = File('${_tmp.path}/data.txt')
        ..writeAsStringSync('data content');
      expect(
        await _dispatcher.dispatch([
          'file_read',
          '--data',
          jsonEncode({'path': testFile.path}),
        ]),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'data content');
    });

    test('rejects an unknown tool name', () async {
      expect(await _dispatcher.dispatch(['frobnicate']), 1);
      expect(_lines.first, contains('unknown tool'));
      expect(_lines.last, contains('dmtools list'));
    });

    test('reports invalid JSON arguments', () async {
      expect(await _dispatcher.dispatch(['file_read', 'not-json']), 1);
      expect(_lines.first, contains('invalid JSON arguments'));
    });

    test('returns an error for an unconfigured integration tool', () async {
      expect(
        await _dispatcher.dispatch(
          ['jira_get_ticket', '{"key": "DMC-479"}'],
        ),
        1,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['error'], contains('not configured'));
    });
  });
}

void _testNoArgs() {
  group('no arguments', () {
    test('prints help when stdout is not a terminal', () async {
      expect(await _dispatcher.dispatch([]), 0);
      expect(_lines.join('\n'), CliDispatcher.helpText);
    });

    test('routes to the interactive stub on a TTY', () async {
      final tty = CliDispatcher(
        writer: _lines.add,
        propertyReader: PropertyReader(basePath: _tmp.path),
        isTty: () => true,
      );
      expect(await tty.dispatch([]), 1);
      expect(_lines, ['Interactive mode requires Phase 4 (terminal picker)']);
    });
  });
}

void _testDefaults() {
  group('defaults', () {
    test('writes through print and treats a non-terminal run as help',
        () async {
      final captured = <String>[];
      final code = await runZoned(
        () => CliDispatcher().dispatch([]),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => captured.add(line),
        ),
      );
      expect(code, 0);
      expect(captured.join('\n'), CliDispatcher.helpText);
    });

    test('--version uses the default writer', () async {
      final captured = <String>[];
      final code = await runZoned(
        () => CliDispatcher().dispatch(['--version']),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => captured.add(line),
        ),
      );
      expect(code, 0);
      expect(
        captured,
        [
          'DMTools $dmtoolsVersion',
          'A comprehensive development management toolkit'
        ],
      );
    });
  });
}
