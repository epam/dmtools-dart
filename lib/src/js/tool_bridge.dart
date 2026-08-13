/// Bridge between JS host functions and the Dart MCP tool registry.
///
/// Registers global JS functions on a [QuickjsRuntime]:
/// - `executeToolViaJava(toolName, args)` — generic tool dispatch, the
///   equivalent of the Java `JobJavaScriptBridge.executeToolViaJava`.
/// - `file_read({path})` — synchronous file reader returning the raw file
///   content as a plain JS string (mirrors the Java bridge contract that
///   testRunner.js and configLoader.js rely on: `content.trim()`).
/// - `set_env_variable(name, value)` — no-op (Phase 1 handles overrides).
/// - `console.log/error/warn/info/debug` — prints to Dart's stdout/stderr.
///
/// File-system and CLI tools execute synchronously via `dart:io` — the
/// [SyncToolDispatcher] delegates them back through the non-HTTP handler.
/// HTTP tools (jira, github, …) dispatch synchronously via curl subprocess —
/// see [SyncToolDispatcher].
library;

import 'dart:convert';
import 'dart:io';

import '../config/property_reader.dart';
import '../mcp/tool_registry.dart';
import 'quickjs_runtime.dart';
import 'sync_tool_dispatcher.dart';

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

  /// Registers `executeToolViaJava`, `file_read`, `set_env_variable`, and
  /// the `console` object as globals on [runtime].
  ///
  /// Must be called **after** tool wrappers are generated so that the direct
  /// `file_read` host function (returning the raw content string) takes
  /// precedence over any generated wrapper that dispatches via
  /// `executeToolViaJava`.
  void registerOn(QuickjsRuntime runtime) {
    runtime.registerHostFunction('executeToolViaJava', _dispatchToolCall);
    runtime.registerHostFunction('file_read', _fileReadHost);
    runtime.registerHostFunction('set_env_variable', _setEnvVariable);
    _registerConsole(runtime);
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
  ///
  /// Returns the file content as a plain JSON string (the C bridge
  /// unmarshals it back to a JS string), or JS `null` when the file cannot
  /// be read — the Java bridge contract testRunner.js and configLoader.js
  /// depend on (`content && content.trim()`).
  String _fileReadHost(String argsJson) {
    final parsed = jsonDecode(argsJson);
    String? path;
    if (parsed is Map) path = parsed['path'] as String?;
    if (path == null) return 'null';
    try {
      return jsonEncode(File(_resolve(path)).readAsStringSync());
    } catch (_) {
      return 'null';
    }
  }

  /// No-op: runtime env overrides are handled by the Phase 1 property layer.
  String _setEnvVariable(String argsJson) => '{"success":true}';

  /// Executes [toolName] with [args], returning the JSON result string.
  ///
  /// This is the same dispatch path used by `executeToolViaJava` from JS,
  /// exposed for direct CLI invocation (`dmtools <tool> '<json>'`). Returns
  /// an `{"error": ...}` JSON object when the tool is unknown or dispatch
  /// fails.
  String execute(String toolName, Map<String, dynamic> args) =>
      _execute(toolName, args);

  /// Routes [toolName] through [SyncToolDispatcher], the single entry point.
  ///
  /// HTTP tools (jira, github, …) dispatch via curl; file-system and CLI
  /// tools delegate back to [_dispatchNonHttp] for direct `dart:io` execution.
  String _execute(String toolName, Map<String, dynamic> args) {
    if (_registry.getTool(toolName) == null) {
      return _err('Unknown tool: $toolName');
    }
    final dispatcher = SyncToolDispatcher(
      PropertyReader(),
      nonHttpHandler: _dispatchNonHttp,
    );
    return dispatcher.execute(toolName, args) ??
        _err('Tool not available: $toolName');
  }

  /// Delegates non-HTTP tools (file-system, CLI) to their sync executors.
  String _dispatchNonHttp(String toolName, Map<String, dynamic> args) {
    final tool = _registry.getTool(toolName);
    if (tool == null) return _err('Unknown tool: $toolName');
    switch (tool.integration) {
      case 'file':
        return _executeFileTool(toolName, args);
      case 'cli':
        return _executeCliTool(args);
      default:
        return _err('Unsupported non-HTTP integration: ${tool.integration}');
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

  /// JS bootstrap that builds the `console` object over the private host
  /// functions registered by [_registerConsole].
  ///
  /// Arguments are formatted in JS (strings as-is, other values via
  /// `JSON.stringify`) and joined with spaces, matching the console
  /// convention used by testRunner.js and agent scripts.
  static const String _consoleBootstrap = '''
(function() {
    function __joinArgs(args) {
        var parts = [];
        for (var i = 0; i < args.length; i++) {
            var a = args[i];
            if (typeof a === 'string') {
                parts.push(a);
            } else {
                var s;
                try { s = JSON.stringify(a); } catch (e) { s = null; }
                parts.push(s === undefined || s === null ? String(a) : s);
            }
        }
        return parts.join(' ');
    }
    globalThis.console = {
        log:   function() { return __consoleLog(__joinArgs(arguments)); },
        info:  function() { return __consoleLog(__joinArgs(arguments)); },
        debug: function() { return __consoleLog(__joinArgs(arguments)); },
        warn:  function() { return __consoleWarn(__joinArgs(arguments)); },
        error: function() { return __consoleError(__joinArgs(arguments)); }
    };
})();
''';

  /// Registers the `console` object on [runtime].
  ///
  /// Host functions print synchronously to Dart's stdout/stderr and return
  /// JS `undefined`, so `console.log(...)` calls chain as no-ops.
  void _registerConsole(QuickjsRuntime runtime) {
    runtime.registerHostFunction(
        '__consoleLog', (argsJson) => _printTo(stdout, argsJson));
    runtime.registerHostFunction(
        '__consoleWarn', (argsJson) => _printTo(stderr, argsJson));
    runtime.registerHostFunction(
        '__consoleError', (argsJson) => _printTo(stderr, argsJson));
    runtime.eval(_consoleBootstrap, filename: '<console>');
  }

  /// Prints one console line and signals JS `undefined` (Dart `null`).
  String? _printTo(IOSink sink, String argsJson) {
    sink.writeln(_consoleArg(argsJson));
    return null;
  }

  /// Decodes the JSON-marshaled console argument back to a display string.
  String _consoleArg(String argsJson) {
    try {
      final decoded = jsonDecode(argsJson);
      return decoded is String ? decoded : argsJson;
    } catch (_) {
      return argsJson;
    }
  }

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
