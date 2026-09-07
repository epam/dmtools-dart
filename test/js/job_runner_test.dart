import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:dmtools/src/mcp/tool_definition.dart';
import 'package:dmtools/src/mcp/tool_param.dart';
import 'package:dmtools/src/mcp/tool_registry.dart';
import 'package:test/test.dart';

/// Tests for [JsJobRunner] — runtime setup, host functions, context
/// injection, tool wrapper generation, and synchronous tool dispatch.
///
/// Every script defines `action(params)` — the JSRunner contract enforced
/// by [JsJobRunner.runScript] (Java `JobJavaScriptBridge` parity).
void main() {
  _testBasicExecution();
  _testContextInjection();
  _testHostFunctions();
  _testErrorDispatch();
  _testWrapperDispatch();
  _testRegistryFiltering();
  _testFileDeleteDispatch();
  _testCliExecuteDispatch();
  _testCliExecuteDispatchErrors();
  _testCliExecuteDispatchWorkingDir();
}

File _writeScript(Directory dir, String name, String content) {
  final file = File('${dir.path}/$name');
  file.writeAsStringSync(content);
  return file;
}

/// Wraps a JS [expression] in the action contract and returns the script.
String _action(String expression) =>
    'function action(params) { return $expression; }';

void _testBasicExecution() {
  group('basic execution', () {
    test('returns JSON result for simple expression', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_basic');
      try {
        final script = _writeScript(dir, 'test.js', _action('1 + 2'));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(result, '3');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testContextInjection() {
  group('context injection', () {
    test('injects jobParams into JS scope', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_ctx');
      try {
        final script =
            _writeScript(dir, 'test.js', _action('params.jobParams.key'));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {'key': 'PROJ-123'},
        );
        expect(jsonDecode(result!), 'PROJ-123');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('injects ticket into JS scope', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_ticket');
      try {
        final script =
            _writeScript(dir, 'test.js', _action('params.ticket.id'));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          ticket: {'id': 42},
        );
        expect(jsonDecode(result!), 42);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('merges contextParams into the params object', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_ctxparams');
      try {
        final script = _writeScript(
          dir,
          'test.js',
          _action('params.response + ":" + params.initiator'),
        );
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          config: const JsRunConfig(
            contextParams: {'response': 'resp', 'initiator': 'me'},
          ),
        );
        expect(jsonDecode(result!), 'resp:me');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testHostFunctions() {
  group('host functions', () {
    test('file_read returns file content as a string', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_fread');
      try {
        File('${dir.path}/data.txt').writeAsStringSync('hello world');
        final script = _writeScript(
            dir, 'test.js', _action("file_read({path: 'data.txt'})"));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          workingDirectory: dir.path,
        );
        expect(jsonDecode(result!), 'hello world');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('set_env_variable is a no-op returning success', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_env');
      try {
        final script = _writeScript(
            dir, 'test.js', _action("set_env_variable('X', 'PATH').success"));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(jsonDecode(result!), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testErrorDispatch() {
  group('error dispatch', () {
    test('executeToolViaJava throws for failed HTTP tool calls', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_http');
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': '',
        'JIRA_EMAIL': '',
        'JIRA_API_TOKEN': '',
        'JIRA_LOGIN_PASS_TOKEN': '',
      });
      try {
        final script = _writeScript(dir, 'test.js', '''
          var msg = 'no-error';
          try {
            executeToolViaJava('jira_get_ticket', {key: 'T-1'});
          } catch (e) {
            msg = e.message;
          }
          function action(params) { return msg; }
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(
          jsonDecode(result!) as String,
          contains('Tool execution failed: Jira not configured'),
        );
      } finally {
        PropertyReader.clearOverrides();
        dir.deleteSync(recursive: true);
      }
    });

    test('executeToolViaJava throws for unknown tool', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_unknown');
      try {
        final script = _writeScript(
            dir,
            'test.js',
            "var msg = 'no-error'; "
                "try { executeToolViaJava('nonexistent', {}); } "
                'catch (e) { msg = e.message; } '
                'function action(params) { return msg; }');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(
          jsonDecode(result!) as String,
          contains('Tool execution failed: Unknown tool'),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testWrapperDispatch() {
  group('tool dispatch', () {
    test('generated wrapper throws for failed tool calls', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_wrap');
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': '',
        'JIRA_EMAIL': '',
        'JIRA_API_TOKEN': '',
        'JIRA_LOGIN_PASS_TOKEN': '',
      });
      try {
        final script = _writeScript(dir, 'test.js', '''
          var msg = 'no-error';
          try {
            jira_get_ticket({key: 'TEST-1'});
          } catch (e) {
            msg = e.message;
          }
          function action(params) { return msg; }
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(
          jsonDecode(result!) as String,
          contains('Tool execution failed: Jira not configured'),
        );
      } finally {
        PropertyReader.clearOverrides();
        dir.deleteSync(recursive: true);
      }
    });

    test('file tool executes synchronously via executeToolViaJava', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_syncfile');
      try {
        File('${dir.path}/notes.txt').writeAsStringSync('secret data');
        final script = _writeScript(
            dir,
            'test.js',
            "var r = executeToolViaJava('file_read', {path: 'notes.txt'}); "
                'function action(params) { return r.content; }');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          workingDirectory: dir.path,
        );
        expect(jsonDecode(result!), 'secret data');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testRegistryFiltering() {
  group('registry filtering', () {
    test('custom registry limits generated wrappers', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_custom');
      try {
        final registry = ToolRegistry()
          ..register(ToolDefinition(
            name: 'custom_tool',
            description: 'Custom',
            integration: 'custom',
            params: [ToolParam(name: 'msg', description: 'Message')],
          ));
        final script = _writeScript(dir, 'test.js', _action('''
          typeof custom_tool === 'function' &&
          typeof jira_get_ticket === 'undefined'
        '''));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          config: JsRunConfig(registry: registry),
        );
        expect(jsonDecode(result!), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('integrationFilter narrows generated wrappers', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_filter');
      try {
        final script = _writeScript(dir, 'test.js', _action('''
          typeof file_read === 'function' &&
          typeof jira_get_ticket === 'undefined'
        '''));
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          config: const JsRunConfig(integrationFilter: {'file'}),
        );
        expect(jsonDecode(result!), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testFileDeleteDispatch() {
  group('file_delete dispatch', () {
    test('removes an existing file via executeToolViaJava', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_delete');
      try {
        final target = File('${dir.path}/to_delete.txt')
          ..writeAsStringSync('bye');
        expect(target.existsSync(), isTrue);
        final script = _writeScript(dir, 'test.js', '''
          var res = executeToolViaJava('file_delete', {path: 'to_delete.txt'});
          function action(params) { return res.deleted; }
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          workingDirectory: dir.path,
        );
        expect(jsonDecode(result!), isTrue);
        expect(target.existsSync(), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('returns deleted=false for missing file', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_noop_del');
      try {
        final script = _writeScript(dir, 'test.js', '''
          var res = executeToolViaJava('file_delete', {path: 'nope.txt'});
          function action(params) { return res.deleted; }
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
          workingDirectory: dir.path,
        );
        expect(jsonDecode(result!), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

Future<Object?> _runCliToolScript(String js,
    {Map<String, String> overrides = const {}, Directory? scriptDir}) async {
  final dir = scriptDir ?? Directory.systemTemp.createTempSync('dmtools_cli');
  final ownsDir = scriptDir == null;
  try {
    final script = _writeScript(dir, 'test.js', js);
    Object? result;
    await PropertyReader.runWithOverrides(overrides, () async {
      result = const JsJobRunner().runScript(
        scriptPath: script.path,
        jobParams: {},
        workingDirectory: dir.path,
      );
    });
    return jsonDecode(result! as String);
  } finally {
    if (ownsDir) dir.deleteSync(recursive: true);
  }
}

void _testCliExecuteDispatch() {
  group('cli_execute_command dispatch', () {
    test('returns trimmed stdout as a plain string', () async {
      final result = await _runCliToolScript('''
        var res = executeToolViaJava('cli_execute_command',
            {command: 'echo hello'});
        function action(params) { return res; }
      ''', overrides: {'CLI_ALLOWED_COMMANDS': 'echo'});
      expect(result, 'hello');
    });

    test('interprets the full command line via shell', () async {
      final result = await _runCliToolScript('''
        var res = executeToolViaJava('cli_execute_command',
            {command: 'echo "a b"'});
        function action(params) { return res; }
      ''', overrides: {'CLI_ALLOWED_COMMANDS': 'echo'});
      expect(result, 'a b');
    });

    test('runs inside workingDirectory when it exists', () async {
      final dir = Directory.systemTemp.createTempSync(
          'dmtools_wd_${DateTime.now().microsecondsSinceEpoch}');
      Process.runSync('git', ['init', '-q', dir.path]);
      try {
        final result = await _runCliToolScript('''
          var res = executeToolViaJava('cli_execute_command',
              {command: 'git rev-parse --show-toplevel',
               workingDirectory: '${dir.path}'});
          function action(params) { return res; }
        ''');
        expect(result as String, contains(dir.path));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testCliExecuteDispatchErrors() {
  group('cli_execute_command dispatch errors', () {
    test('throws when command is missing', () async {
      final result = await _runCliToolScript('''
        var msg = 'no-error';
        try {
          executeToolViaJava('cli_execute_command', {});
        } catch (e) {
          msg = e.message;
        }
        function action(params) { return msg; }
      ''');
      expect(result as String, contains('Command cannot be null or empty'));
    });

    test('throws SecurityException text for non-whitelisted commands',
        () async {
      final result = await _runCliToolScript('''
        var msg = 'no-error';
        try {
          executeToolViaJava('cli_execute_command', {command: 'rm -rf /'});
        } catch (e) {
          msg = e.message;
        }
        function action(params) { return msg; }
      ''');
      expect(result as String,
          contains('Command not allowed. Whitelisted commands:'));
    });

    test('surfaces non-zero exit as an error (exit code propagated)', () async {
      final result = await _runCliToolScript('''
        var msg = 'no-error';
        try {
          executeToolViaJava('cli_execute_command',
              {command: 'git status --bogus-flag-xyz'});
        } catch (e) {
          msg = e.message;
        }
        function action(params) { return msg; }
      ''');
      expect(result as String, contains('Command execution failed (exit code'));
    });
  });
}

/// Java `resolveWorkingDirectory` / `loadEnvironmentVariables` parity tests:
/// git-root fallback, allowed-base validation, and env injection.
void _testCliExecuteDispatchWorkingDir() {
  group('cli_execute_command working directory', () {
    test('falls back to the git root of the job directory', () async {
      final dir = Directory.systemTemp.createTempSync(
          'dmtools_gitroot_${DateTime.now().microsecondsSinceEpoch}');
      Process.runSync('git', ['init', '-q', dir.path]);
      try {
        final result = await _runCliToolScript('''
          var res = executeToolViaJava('cli_execute_command',
              {command: 'git rev-parse --show-toplevel'});
          function action(params) { return res; }
        ''', scriptDir: dir);
        expect(result as String, contains(dir.path));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('rejects a workingDirectory outside the allowed bases', () async {
      final result = await _runCliToolScript('''
        var msg = 'no-error';
        try {
          executeToolViaJava('cli_execute_command',
              {command: 'git rev-parse --show-toplevel', workingDirectory: '/'});
        } catch (e) {
          msg = e.message;
        }
        function action(params) { return msg; }
      ''');
      expect(result as String, contains('outside allowed base paths'));
    });

    test('injects dmtools.env from the working directory', () async {
      final dir = Directory.systemTemp.createTempSync(
          'dmtools_envfile_${DateTime.now().microsecondsSinceEpoch}');
      Process.runSync('git', ['init', '-q', dir.path]);
      File('${dir.path}/dmtools.env').writeAsStringSync(
          'GIT_AUTHOR_NAME=docsbot\nGIT_AUTHOR_EMAIL=docsbot@example.com\n');
      try {
        final result = await _runCliToolScript('''
          var res = executeToolViaJava('cli_execute_command',
              {command: 'git var GIT_AUTHOR_IDENT'});
          function action(params) { return res; }
        ''', scriptDir: dir);
        expect(result as String, contains('docsbot <docsbot@example.com>'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
