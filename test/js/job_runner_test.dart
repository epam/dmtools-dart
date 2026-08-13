import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/job_runner.dart';
import 'package:dmtools/src/mcp/tool_definition.dart';
import 'package:dmtools/src/mcp/tool_param.dart';
import 'package:dmtools/src/mcp/tool_registry.dart';
import 'package:test/test.dart';

/// Tests for [JsJobRunner] — runtime setup, host functions, context
/// injection, tool wrapper generation, and synchronous tool dispatch.
void main() {
  _testBasicExecution();
  _testContextInjection();
  _testHostFunctions();
  _testErrorDispatch();
  _testWrapperDispatch();
  _testRegistryFiltering();
  _testFileDeleteDispatch();
  _testCliExecuteDispatch();
}

File _writeScript(Directory dir, String name, String content) {
  final file = File('${dir.path}/$name');
  file.writeAsStringSync(content);
  return file;
}

void _testBasicExecution() {
  group('basic execution', () {
    test('returns JSON result for simple expression', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_basic');
      try {
        final script = _writeScript(dir, 'test.js', '1 + 2');
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
        final script = _writeScript(dir, 'test.js', 'params.jobParams.key');
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
        final script = _writeScript(dir, 'test.js', 'params.ticket.id');
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
  });
}

void _testHostFunctions() {
  group('host functions', () {
    test('file_read returns file content as a string', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_fread');
      try {
        File('${dir.path}/data.txt').writeAsStringSync('hello world');
        final script =
            _writeScript(dir, 'test.js', "file_read({path: 'data.txt'})");
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
        final script = _writeScript(dir, 'test.js',
            "set_env_variable({name: 'X', value: 'Y'}).success");
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
    test('executeToolViaJava returns error for HTTP tools', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_http');
      try {
        final script = _writeScript(dir, 'test.js',
            "executeToolViaJava('jira_get_ticket', {key: 'T-1'}).error");
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(jsonDecode(result!) as String,
            contains('not available in sync mode'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('executeToolViaJava returns error for unknown tool', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_unknown');
      try {
        final script = _writeScript(
            dir, 'test.js', "executeToolViaJava('nonexistent', {}).error");
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(jsonDecode(result!) as String, contains('Unknown tool'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _testWrapperDispatch() {
  group('tool dispatch', () {
    test('generated wrapper dispatches to executeToolViaJava', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_wrap');
      try {
        final script = _writeScript(dir, 'test.js', '''
          var result = jira_get_ticket({key: 'TEST-1'});
          result.error
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(jsonDecode(result!) as String,
            contains('not available in sync mode'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('file tool executes synchronously via executeToolViaJava', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_syncfile');
      try {
        File('${dir.path}/notes.txt').writeAsStringSync('secret data');
        final script = _writeScript(dir, 'test.js',
            "executeToolViaJava('file_read', {path: 'notes.txt'}).content");
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
        final script = _writeScript(dir, 'test.js', '''
          typeof custom_tool === 'function' &&
          typeof jira_get_ticket === 'undefined'
        ''');
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
        final script = _writeScript(dir, 'test.js', '''
          typeof file_read === 'function' &&
          typeof jira_get_ticket === 'undefined'
        ''');
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
          res.deleted
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
          res.deleted
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

void _testCliExecuteDispatch() {
  group('cli_execute_command dispatch', () {
    test('runs echo via executeToolViaJava', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_cli');
      try {
        final script = _writeScript(dir, 'test.js', '''
          var res = executeToolViaJava(
            'cli_execute_command',
            {command: 'echo', args: ['hello']}
          );
          res.exitCode + ':' + res.stdout.trim()
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(jsonDecode(result!), '0:hello');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('returns error when command is missing', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_nocmd');
      try {
        final script = _writeScript(dir, 'test.js', '''
          var res = executeToolViaJava('cli_execute_command', {});
          res.error
        ''');
        final result = const JsJobRunner().runScript(
          scriptPath: script.path,
          jobParams: {},
        );
        expect(jsonDecode(result!) as String, contains('missing command'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
