/// Bridge between JS host functions and the Dart MCP tool registry.
///
/// Registers three global JS functions on a [QuickjsRuntime]:
/// - `executeToolViaJava(toolName, args)` — generic tool dispatch, the
///   equivalent of the Java `JobJavaScriptBridge.executeToolViaJava`.
/// - `file_read({path})` — synchronous file reader (used by testRunner.js).
/// - `set_env_variable(name, value)` — no-op (Phase 1 handles overrides).
///
/// File-system and CLI tools execute synchronously via `dart:io`. HTTP tools
/// (jira, github, …) return a placeholder error in sync mode — the agents
/// test suite mocks them in JS, and real blocking HTTP dispatch arrives in a
/// later phase.
library;

import 'dart:convert';
import 'dart:io';

import '../mcp/tool_registry.dart';
import 'quickjs_runtime.dart';

/// Registers JS host functions backed by the Dart MCP tool registry.
class ToolBridge {
  final ToolRegistry _registry;
  final String? _workingDirectory;

  /// Creates a bridge backed by [registry].
  ///
  /// Relative file paths in tool calls resolve against [workingDirectory]
  /// (defaults to [Directory.current]).
  ToolBridge({required ToolRegistry registry, String? workingDirectory})
      : _registry = registry,
        _workingDirectory = workingDirectory;

  /// Registers `executeToolViaJava`, `file_read`, and `set_env_variable`
  /// as global JS functions on [runtime].
  void registerOn(QuickjsRuntime runtime) {
    runtime.registerHostFunction('executeToolViaJava', _dispatchToolCall);
    runtime.registerHostFunction('file_read', _fileReadHost);
    runtime.registerHostFunction('set_env_variable', _setEnvVariable);
  }

  /// Dispatch table for synchronous file tool execution.
  late final Map<String, String Function(Map<String, dynamic>)> _fileFns = {
    'file_read': (a) => _readFile(a['path'] as String),
    'file_write': (a) =>
        _writeFile(a['path'] as String, a['content'] as String),
    'file_list': (a) => _listDir(a['path'] as String),
    'file_exists': (a) => _exists(a['path'] as String),
    'file_delete': (a) => _delete(a['path'] as String),
    'file_copy': (a) => _copy(a['source'] as String, a['dest'] as String),
    'file_move': (a) => _move(a['source'] as String, a['dest'] as String),
    'file_mkdir': (a) => _mkdir(a['path'] as String),
    'file_read_lines': (a) => _readLines(a['path'] as String),
    'file_write_lines': (a) => _writeLines(a['path'] as String, a['lines']),
    'file_append': (a) => _append(a['path'] as String, a['content'] as String),
    'file_info': (a) => _info(a['path'] as String),
  };

  /// Handles `executeToolViaJava(toolName, args)` calls from JS wrappers.
  ///
  /// The C bridge marshals 2+ JS args as a JSON array, so [argsJson] decodes
  /// to `[toolName, argsObj]`.
  String _dispatchToolCall(String argsJson) {
    final parsed = jsonDecode(argsJson);
    if (parsed is! List || parsed.length < 2) {
      return _err('executeToolViaJava expects (toolName, args)');
    }
    final toolName = parsed[0] as String;
    final toolArgs = _castArgs(parsed[1]);
    return _execute(toolName, toolArgs);
  }

  /// Handles direct `file_read({path})` calls from JS test scripts.
  String _fileReadHost(String argsJson) {
    final parsed = jsonDecode(argsJson);
    if (parsed is Map && parsed['path'] is String) {
      return _readFile(parsed['path'] as String);
    }
    return _err('file_read requires a path argument');
  }

  /// No-op: runtime env overrides are handled by the Phase 1 property layer.
  String _setEnvVariable(String argsJson) => '{"success":true}';

  /// Routes [toolName] to the matching executor by integration type.
  String _execute(String toolName, Map<String, dynamic> args) {
    final tool = _registry.getTool(toolName);
    if (tool == null) return _err('Unknown tool: $toolName');
    switch (tool.integration) {
      case 'file':
        return _executeFileTool(toolName, args);
      case 'cli':
        return _executeCliTool(args);
      default:
        return _err('HTTP tool not available in sync mode: $toolName');
    }
  }

  /// Dispatches a file tool synchronously by name.
  String _executeFileTool(String name, Map<String, dynamic> args) {
    final fn = _fileFns[name];
    return fn != null ? fn(args) : _err('Unknown file tool: $name');
  }

  /// Executes `cli_execute_command` via [Process.runSync].
  String _executeCliTool(Map<String, dynamic> args) {
    final command = args['command'] as String?;
    if (command == null) return _err('missing command argument');
    try {
      final cliArgs = _castList(args['args']);
      final result = Process.runSync(command, cliArgs);
      return jsonEncode({
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
        'exitCode': result.exitCode,
      });
    } catch (e) {
      return _err(e.toString());
    }
  }

  // ── Synchronous file operations ────────────────────────────────────────

  String _readFile(String path) {
    try {
      return jsonEncode({'content': File(_resolve(path)).readAsStringSync()});
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _writeFile(String path, String content) {
    try {
      File(_resolve(path)).writeAsStringSync(content);
      return '{"success":true}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _listDir(String path) {
    try {
      final entries =
          Directory(_resolve(path)).listSync().map((e) => e.path).toList();
      return jsonEncode({'entries': entries});
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _exists(String path) {
    final resolved = _resolve(path);
    final exists =
        File(resolved).existsSync() || Directory(resolved).existsSync();
    return jsonEncode({'exists': exists});
  }

  String _delete(String path) {
    try {
      final file = File(_resolve(path));
      if (file.existsSync()) {
        file.deleteSync();
        return '{"deleted":true}';
      }
      return '{"deleted":false}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _copy(String source, String dest) {
    try {
      File(_resolve(source)).copySync(_resolve(dest));
      return '{"success":true}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _move(String source, String dest) {
    try {
      File(_resolve(source)).renameSync(_resolve(dest));
      return '{"success":true}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _mkdir(String path) {
    try {
      Directory(_resolve(path)).createSync(recursive: true);
      return '{"success":true}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _readLines(String path) {
    try {
      final lines = File(_resolve(path)).readAsLinesSync();
      return jsonEncode({'lines': lines});
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _writeLines(String path, dynamic lines) {
    try {
      final list = (lines as List).cast<String>();
      File(_resolve(path)).writeAsStringSync(list.join('\n'));
      return '{"success":true}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _append(String path, String content) {
    try {
      File(_resolve(path)).writeAsStringSync(content, mode: FileMode.append);
      return '{"success":true}';
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _info(String path) {
    final resolved = _resolve(path);
    final type = FileSystemEntity.typeSync(resolved);
    final exists = type != FileSystemEntityType.notFound;
    if (!exists) {
      return jsonEncode({'exists': false, 'isDirectory': false, 'size': 0});
    }
    final stat = FileStat.statSync(resolved);
    return jsonEncode({
      'exists': true,
      'isDirectory': type == FileSystemEntityType.directory,
      'size': stat.size,
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Resolves [path] against the working directory when relative.
  String _resolve(String path) {
    if (path.startsWith('/')) return path;
    final base = _workingDirectory ?? Directory.current.path;
    return '$base/$path';
  }

  static Map<String, dynamic> _castArgs(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

  static List<String> _castList(dynamic value) =>
      value is List ? value.cast<String>() : const [];

  static String _err(String message) => jsonEncode({'error': message});
}
