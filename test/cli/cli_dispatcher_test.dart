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
  _testDirectToolNamedArgs();
  _testDirectToolNamedArgsPrecedence();
  _testDirectToolJavaArgs();
  _testDirectToolJavaArgForms();
  _testDirectToolJavaFlags();
  _testDirectToolJavaFlagStripping();
  _testDirectToolJavaDataFlags();
  _testDirectToolHelp();
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
    test('runs a JS file with an action(params) function', () async {
      // Note: the file name must not contain "action" — Java
      // loadJavaScriptCode parity treats such paths as inline code.
      final jsFile = File('${_tmp.path}/fn.js')
        ..writeAsStringSync(
          "function action(params) { return 1 + 2; }",
        );
      expect(await _dispatcher.dispatch(['run', jsFile.path]), 0);
      expect(_lines.last, '3');
    });

    test('runs a JS file returning an object from action(params)', () async {
      final jsFile = File('${_tmp.path}/greet.js')
        ..writeAsStringSync(
          "function action(params) { return { greeting: 'hello' }; }",
        );
      expect(await _dispatcher.dispatch(['run', jsFile.path]), 0);
      final decoded = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(decoded['greeting'], 'hello');
    });

    test('passes --key overrides as jobParams', () async {
      final jsFile = File('${_tmp.path}/params.js')
        ..writeAsStringSync(
          'function action(params) { return params.jobParams.name; }',
        );
      expect(
        await _dispatcher.dispatch(['run', jsFile.path, '--name', 'world']),
        0,
      );
      expect(jsonDecode(_lines.last), 'world');
    });

    test('fails for a script without an action function (Java parity)',
        () async {
      final jsFile = File('${_tmp.path}/plain.js')..writeAsStringSync('1 + 2');
      expect(await _dispatcher.dispatch(['run', jsFile.path]), 1);
      expect(_lines.last, contains("must define an 'action' function"));
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
    test('a positional JSON string is an ordinary positional value', () async {
      // Java parseToolArguments never parses a bare positional as JSON:
      // the blob maps onto the first schema param as a plain string.
      final blob = jsonEncode({'path': '/nonexistent/positional.txt'});
      expect(await _dispatcher.dispatch(['file_read', blob]), 1);
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['error'], contains(blob));
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
    test('a malformed object blob is an ordinary positional, not an error',
        () async {
      // No '{'-prefix special case in Java: '{"broken"' is a value.
      expect(await _dispatcher.dispatch(['file_read', '{"broken"']), 1);
      expect(_lines.join('\n'), isNot(contains('invalid JSON arguments')));
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['error'], contains('{"broken"'));
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

/// Java `parseToolArguments` parity: positional args mapped onto the
/// tool's schema parameters.
void _testDirectToolJavaArgs() {
  group('direct tool invocation (Java-style args)', () {
    test('maps a bare positional onto the first schema param', () async {
      final testFile = File('${_tmp.path}/schema.txt')
        ..writeAsStringSync('schema content');
      expect(await _dispatcher.dispatch(['file_read', testFile.path]), 0);
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'schema content');
    });

    test('collects remaining positionals into a trailing array param',
        () async {
      expect(
        await _dispatcher
            .dispatch(['jira_get_ticket', 'CM-3574', 'summary,description']),
        1,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      // Proves the args parsed: key mapped, fields collected as the array.
      expect(result['error'], contains('not configured'));
    });
  });
}

/// Java `parseToolArguments` parity: mid-list array reservation and the
/// bare argument forms (`key=value`, paramless tools, extras).
void _testDirectToolJavaArgForms() {
  group('direct tool invocation (Java-style arg forms)', () {
    test('reserves one positional per param after a mid-list array', () async {
      // cli_execute_command_with_env: command, args[], env_vars — the
      // array reserves 'world' for env_vars, so echo receives ['hello'].
      expect(
        await _dispatcher.dispatch(
            ['cli_execute_command_with_env', 'echo', 'hello', 'world']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['stdout'], 'hello\n');
    });

    test('a mid-list array with no room is empty, not an error', () async {
      expect(
        await _dispatcher.dispatch(['cli_execute_command_with_env', 'echo']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['stdout'], '\n');
    });

    test('treats a bare key=value token as a named argument', () async {
      final testFile = File('${_tmp.path}/kv.txt')
        ..writeAsStringSync('kv content');
      expect(
        await _dispatcher.dispatch(['file_read', 'path=${testFile.path}']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'kv content');
    });

    test('a tool without params maps positionals to arg0, arg1', () async {
      // mermaid_list_types has no schema params: the bare positional must
      // map to arg0 and reach the executor — not die as invalid JSON.
      expect(
        await _dispatcher.dispatch(['mermaid_list_types', 'ignored-pos']),
        1,
      );
      expect(_lines.first, isNot(contains('invalid JSON arguments')));
      expect(jsonDecode(_lines.last), isA<Map<String, dynamic>>());
    });

    test('extra positionals beyond the schema are ignored', () async {
      final testFile = File('${_tmp.path}/extra.txt')
        ..writeAsStringSync('extra content');
      expect(
        await _dispatcher
            .dispatch(['file_read', testFile.path, 'junk1', 'junk2']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'extra content');
    });
  });
}

/// Java parity: the flag surface — `--format`/`--md`, output-format
/// stripping (`extractFormatFlag`), shell flags, and valueless trailers.
void _testDirectToolJavaFlags() {
  group('direct tool invocation (Java-style flags)', () {
    test('--format sets the format argument', () async {
      expect(
        await _dispatcher
            .dispatch(['file_read', '--format', 'json', '--data', '{}']),
        1,
      );
      // format is accepted; the failure is the missing path, not parsing.
      expect(_lines.join('\n'), isNot(contains('invalid JSON arguments')));
    });

    test('--md sets format to md', () async {
      expect(
        await _dispatcher.dispatch(['file_read', '--md', '--data', '{}']),
        1,
      );
      expect(_lines.join('\n'), isNot(contains('invalid JSON arguments')));
    });

    test('output-format flags are stripped, not named args', () async {
      final testFile = File('${_tmp.path}/stripped.txt')
        ..writeAsStringSync('stripped content');
      final flagForms = [
        ['--toon'],
        ['--mini'],
        ['--output', 'json'],
        ['--output=json'],
      ];
      for (final flags in flagForms) {
        _lines.clear();
        expect(
          await _dispatcher
              .dispatch(['file_read', ...flags, '--path', testFile.path]),
          0,
        );
        final result = jsonDecode(_lines.last) as Map<String, dynamic>;
        expect(result['content'], 'stripped content');
      }
    });
    // Remaining flag-surface cases live in _testDirectToolJavaFlagStripping.
  });
}

/// Java parity: output-format stripping and shell-flag passthrough.
void _testDirectToolJavaFlagStripping() {
  group('direct tool invocation (Java-style flag stripping)', () {
    test('shell flags are ignored without touching named args', () async {
      final testFile = File('${_tmp.path}/verbose.txt')
        ..writeAsStringSync('verbose content');
      expect(
        await _dispatcher
            .dispatch(['file_read', '--verbose', '--path', testFile.path]),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'verbose content');
    });

    test('a trailing --output without a value stays and is ignored', () async {
      final testFile = File('${_tmp.path}/trailing.txt')
        ..writeAsStringSync('trailing content');
      expect(
        await _dispatcher
            .dispatch(['file_read', '--path', testFile.path, '--output']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'trailing content');
    });

    test('--output consumes the next token, so --output --help is no help',
        () async {
      // Java extractFormatFlag runs before the --help scan: --help is
      // eaten as the format value, leaving no arguments for file_read.
      expect(
          await _dispatcher.dispatch(['file_read', '--output', '--help']), 1);
      expect(_lines.join('\n'), isNot(contains('"tools"')));
    });
  });
}

/// Java `parseToolArguments` parity: the data-flag surface — `--data`
/// fallback, `--stdin-data`, and valueless trailers.
void _testDirectToolJavaDataFlags() {
  group('direct tool invocation (Java-style data flags)', () {
    test('--data with a non-JSON value falls back to the data string',
        () async {
      expect(
        await _dispatcher.dispatch(['file_read', '--data', 'notjson']),
        1,
      );
      expect(_lines.join('\n'), isNot(contains('invalid JSON arguments')));
    });

    test('--stdin-data merges like --data', () async {
      final testFile = File('${_tmp.path}/stdin-data.txt')
        ..writeAsStringSync('stdin-data content');
      expect(
        await _dispatcher.dispatch(
            ['file_read', '--stdin-data', '{"path":"${testFile.path}"}']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'stdin-data content');
    });

    test('--file names a plain argument; no file is read', () async {
      // Java parseToolArguments has no --file branch: it falls into the
      // generic named-arg branch, so the JSON blob is never loaded and
      // `path` stays missing.
      final testFile = File('${_tmp.path}/from-file.txt')
        ..writeAsStringSync('from-file content');
      final paramsFile = File('${_tmp.path}/params.json')
        ..writeAsStringSync('{"path":"${testFile.path}"}');
      expect(
        await _dispatcher.dispatch(['file_read', '--file', paramsFile.path]),
        1,
      );
      expect(_lines.join('\n'), isNot(contains('from-file content')));
    });

    test('a trailing flag without a value is ignored', () async {
      expect(
        await _dispatcher.dispatch(['file_read', '--data', '--path']),
        1,
      );
      // '--path' becomes the --data value; no named arg is synthesized.
      expect(_lines.join('\n'), isNot(contains('invalid JSON arguments')));
    });
  });
}

void _testDirectToolNamedArgs() {
  group('direct tool invocation (named args)', () {
    test('executes a file tool with --key value named args', () async {
      final testFile = File('${_tmp.path}/named.txt')
        ..writeAsStringSync('named content');
      expect(
        await _dispatcher.dispatch(['file_read', '--path', testFile.path]),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'named content');
    });

    test('executes a file tool with --key=value named args', () async {
      final testFile = File('${_tmp.path}/eq.txt')
        ..writeAsStringSync('eq content');
      expect(
        await _dispatcher.dispatch(['file_read', '--path=${testFile.path}']),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'eq content');
    });

    test('named arg values are not mistaken for a JSON positional', () async {
      final testFile = File('${_tmp.path}/pos.txt')
        ..writeAsStringSync('positional content');
      expect(
        await _dispatcher.dispatch(['file_read', '--path', testFile.path]),
        0,
      );
      expect(
        _lines.last,
        isNot(contains('invalid JSON arguments')),
      );
    });
    // Precedence cases live in _testDirectToolNamedArgsPrecedence.
  });
}

/// Java parity: positional mapping runs LAST, overriding same-named
/// `--key` flags and `--data` blob keys.
void _testDirectToolNamedArgsPrecedence() {
  group('direct tool invocation (named arg precedence)', () {
    test('positional mapping overrides a same-named --key (Java order)',
        () async {
      // Java mapPositionalArguments runs LAST, after the named flags, so
      // the positional wins over the earlier --path.
      final testFile = File('${_tmp.path}/over.txt')
        ..writeAsStringSync('override content');
      expect(
        await _dispatcher.dispatch([
          'file_read',
          testFile.path,
          '--path',
          '/nonexistent/first.txt',
        ]),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'override content');
    });

    test('positional mapping overrides a --data key (Java order)', () async {
      final testFile = File('${_tmp.path}/over-data.txt')
        ..writeAsStringSync('override-data content');
      expect(
        await _dispatcher.dispatch([
          'file_read',
          '--data',
          jsonEncode({'path': '/nonexistent/data.txt'}),
          testFile.path,
        ]),
        0,
      );
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['content'], 'override-data content');
    });
  });
}

/// No-argument dispatch: help text and the TTY interactive stub.
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

/// Java `processMcpCommand` parity: `--help`/`-h` among tool args shows
/// the tool's schema (the tools list filtered by tool name).
void _testDirectToolHelp() {
  group('direct tool invocation (help)', () {
    test('--help shows the tool schema instead of executing', () async {
      expect(await _dispatcher.dispatch(['file_read', '--help']), 0);
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      final tools = (result['tools'] as List)
          .cast<Map<String, dynamic>>()
          .map((t) => t['name'] as String);
      expect(tools, isNotEmpty);
      expect(tools.every((name) => name.contains('file_read')), isTrue);
    });

    test('-h shows the tool schema instead of executing', () async {
      expect(await _dispatcher.dispatch(['file_read', '-h']), 0);
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect((result['tools'] as List), isNotEmpty);
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
