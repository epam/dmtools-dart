/// Bridge between JS host functions and the Dart MCP tool registry.
///
/// Registers global JS functions on a [QuickjsRuntime]:
/// - `executeToolViaJava(toolName, args)` — generic tool dispatch, the
///   equivalent of the Java `JobJavaScriptBridge.executeToolViaJava`.
/// - `file_read({path})` — synchronous file reader returning the raw file
///   content as a plain JS string (mirrors the Java bridge contract that
///   testRunner.js and configLoader.js rely on: `content.trim()`).
/// - `set_env_variable(propertyName, envVarName)` — no-op (Phase 1 handles
///   overrides); validates its argument count for Java parity.
/// - `console.log/error/warn/info/debug` — prints to Dart's stdout/stderr.
///
/// File-system and CLI tools execute synchronously via `dart:io` — the
/// [SyncToolDispatcher] delegates them back through the non-HTTP handler.
/// HTTP tools (jira, github, …) dispatch synchronously via curl subprocess —
/// see [SyncToolDispatcher].
library;

import 'dart:convert';
import 'dart:io';

import '../config/env_file_parser.dart';
import '../config/property_reader.dart';
import '../integrations/cli/cli_tools.dart';
import '../mcp/tool_registry.dart';
import 'package:quickjs_runtime/quickjs_runtime.dart';
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

  /// The single tool dispatcher shared by every call through this bridge.
  ///
  /// Holds the per-integration sync tool sets and their config
  /// [PropertyReader]; one instance per bridge so repeated tool calls reuse
  /// the loaded configuration (and its cached `dmtools.env` reads) instead
  /// of rebuilding both on every call.
  late final SyncToolDispatcher dispatcher = SyncToolDispatcher(
    PropertyReader(),
    nonHttpHandler: _dispatchNonHttp,
  );

  /// CLI executor for the JS-bridge `cli_execute_command` path: supplies the
  /// base whitelist plus the `CLI_ALLOWED_COMMANDS` extension.
  late final CliToolExecutor _cliExecutor = CliToolExecutor(PropertyReader());

  /// Registers `executeToolViaJava`, `file_read`, `set_env_variable`, and
  /// the `console` object as globals on [runtime].
  ///
  /// The host functions are registered under private `__…Host` names and
  /// wrapped by [_hostFunctionBootstrap] under the public global names:
  /// FFI host functions cannot throw into JS (stray Dart exceptions surface
  /// as JS `undefined`), so argument-validation failures return a
  /// `{'__jsError': …}` sentinel that the JS wrapper rethrows as a real
  /// JS `Error` — mirroring Java `IllegalArgumentException` propagation.
  ///
  /// Must be called **after** tool wrappers are generated so that the direct
  /// `file_read` host function (returning the raw content string) takes
  /// precedence over any generated wrapper that dispatches via
  /// `executeToolViaJava`.
  void registerOn(QuickjsRuntime runtime) {
    runtime.registerHostFunction('__executeToolViaJavaHost', _dispatchToolCall);
    runtime.registerHostFunction('__fileReadHost', _fileReadHost);
    runtime.registerHostFunction('__setEnvVariableHost', _setEnvVariable);
    _registerConsole(runtime);
    runtime.eval(_hostFunctionBootstrap, filename: '<host_functions>');
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
  /// The C bridge marshals the call arguments as JSON: 2+ JS args as an
  /// array (`[toolName, argsObj]`), a single arg as-is, and none as an
  /// unparseable object literal (see [_decodeArgs]). Java
  /// `ExecuteToolProxy` parity: at least the tool name is required (a bare
  /// tool name executes with empty args); fewer surfaces the `__jsError`
  /// sentinel.
  ///
  /// Tool-execution failures also surface as the `__jsError` sentinel (rethrown
  /// as a JS `Error` by the bootstrap) — Java `JobJavaScriptBridge` parity: a
  /// failed call throws into the script, which agent scripts catch and react
  /// to; it never resolves to a value a script could mistake for tool data.
  String _dispatchToolCall(String argsJson) {
    final parsed = _decodeArgs(argsJson);
    if (parsed is String) {
      return _toolCallResult(() => _execute(parsed, const {}));
    }
    if (parsed is List && parsed.length >= 2 && parsed[0] is String) {
      return _toolCallResult(
        () => _execute(parsed[0] as String, _castArgs(parsed[1])),
      );
    }
    return _jsError(
      'executeToolViaJava requires at least 1 argument: toolName',
    );
  }

  /// Runs one tool call for the `executeToolViaJava` host function and
  /// converts failures into the `__jsError` sentinel.
  ///
  /// Failures arrive two ways: a Dart exception thrown by an executor, or a
  /// single-key `{"error": …}` envelope (the [SyncToolDispatcher] failure
  /// convention — unconfigured integration, unknown tool, transport error).
  /// Both become `Tool execution failed: <message>`, the wording the Java
  /// bridge uses. Successful results pass through untouched; a multi-key
  /// object that happens to carry an `error` field is a remote API body and
  /// passes through too.
  String _toolCallResult(String Function() run) {
    final String result;
    try {
      result = run();
    } catch (e) {
      return _jsError('Tool execution failed: $e');
    }
    final decoded = _decodeArgs(result);
    final isErrorEnvelope =
        decoded is Map && decoded.length == 1 && decoded['error'] != null;
    if (isErrorEnvelope) {
      return _jsError('Tool execution failed: ${decoded['error']}');
    }
    return result;
  }

  /// Handles direct `file_read({path})` calls from JS test scripts.
  ///
  /// Returns the file content as a plain JSON string (the C bridge
  /// unmarshals it back to a JS string), or JS `null` when the file cannot
  /// be read — the Java bridge contract testRunner.js and configLoader.js
  /// depend on (`content && content.trim()`).
  ///
  /// Logs the call args first, like every other tool: in Java `file_read`
  /// is a generated wrapper that logs its call, but here the direct host
  /// replaces that wrapper.
  String _fileReadHost(String argsJson) {
    final parsed = _decodeArgs(argsJson);
    String? path;
    if (parsed is Map) path = parsed['path'] as String?;
    stdout.writeln('Calling tool file_read with args: '
        '${jsonEncode(parsed is Map ? parsed : const {})}');
    if (path == null) return 'null';
    try {
      return jsonEncode(File(_resolve(path)).readAsStringSync());
    } catch (_) {
      return 'null';
    }
  }

  /// No-op returning success: runtime env overrides are handled by the
  /// Phase 1 property layer. Argument count is validated for Java
  /// `SetEnvVariableProxy` parity — `set_env_variable(propertyName,
  /// envVarName)` requires exactly two positional arguments.
  ///
  /// The C bridge marshals a single JS argument as-is and none as an
  /// unparseable object literal, so anything but a 2+ element array fails
  /// validation via the `__jsError` sentinel.
  String _setEnvVariable(String argsJson) {
    final parsed = _decodeArgs(argsJson);
    if (parsed is List && parsed.length >= 2) {
      return _successJson;
    }
    return _jsError(
      'set_env_variable requires 2 arguments: propertyName, envVarName',
    );
  }

  /// Executes [toolName] with [args], returning the JSON result string.
  ///
  /// This is the same dispatch path used by `executeToolViaJava` from JS,
  /// exposed for direct CLI invocation (`dmtools <tool> '<json>'`). Returns
  /// an `{"error": ...}` JSON object when the tool is unknown or dispatch
  /// fails.
  String execute(String toolName, Map<String, dynamic> args) =>
      _execute(toolName, args);

  /// Routes [toolName] through [dispatcher], the single entry point.
  ///
  /// HTTP tools (jira, github, …) dispatch via curl; file-system and CLI
  /// tools delegate back to [_dispatchNonHttp] for direct `dart:io` execution.
  String _execute(String toolName, Map<String, dynamic> args) {
    // Canonical names only: the Java JS surface exposes and resolves
    // canonical schemas (MCPSchemaGenerator); tracker_*/source_code_*
    // alias resolution is a CLI concern (McpCliHandler.resolveToolAlias).
    final tool = _registry.getTool(toolName);
    if (tool == null || tool.name != toolName) {
      return _err('Unknown tool: $toolName');
    }
    return dispatcher.execute(tool.name, tool.applyParamAliases(args)) ??
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
        return _executeCliTool(toolName, args);
      default:
        return _err('Unsupported non-HTTP integration: ${tool.integration}');
    }
  }

  /// Dispatches a file tool synchronously by name.
  String _executeFileTool(String name, Map<String, dynamic> args) {
    final fn = _fileFns[name];
    return fn != null ? fn(args) : _err('Unknown file tool: $name');
  }

  /// Executes JS-bridge CLI tools. `cli_execute_command` follows Java
  /// `CliCommandExecutor` parity exactly: the command is a full command LINE
  /// whose first token is whitelisted (base set + `CLI_ALLOWED_COMMANDS`);
  /// the line runs through a shell temp script (`/bin/sh`; `cmd.exe /c` on
  /// Windows) and trimmed stdout is returned as a plain string. Non-zero
  /// exit, spawn failure, or a whitelist violation surfaces as the
  /// `__jsError` sentinel (Java SecurityException / CliCommandFailedException
  /// parity) and is rethrown as a JS `Error`. The Dart-only extras
  /// (`cli_execute_command_with_env`) keep their legacy `command` + `args`
  /// array semantics.
  String _executeCliTool(String toolName, Map<String, dynamic> args) {
    if (toolName != 'cli_execute_command') {
      return _executeLegacyCliTool(args);
    }
    final command = (args['command'] as String?)?.trim();
    if (command == null || command.isEmpty) {
      return _err('Command cannot be null or empty');
    }
    final firstWord = command.split(RegExp(r'\s+')).first.toLowerCase();
    final allowed = _cliExecutor.allowedCommands.toList()..sort();
    if (!allowed.contains(firstWord)) {
      return _err(
          'Command not allowed. Whitelisted commands: ${allowed.join(', ')}');
    }
    try {
      final workDir =
          _resolveCliWorkingDir(args['workingDirectory'] as String?);
      return _runCommandLine(command, workDir);
    } catch (e) {
      // SecurityException parity for the allowed-base validation failure.
      return _err(e.toString());
    }
  }

  /// Legacy executor for the Dart-only `cli_execute_command_with_env`:
  /// [args] carry a `command` executable plus a separate `args` array.
  /// Returns a `{stdout, stderr, exitCode}` JSON object (pre-parity shape,
  /// kept so the Dart-only tool surface does not regress).
  String _executeLegacyCliTool(Map<String, dynamic> args) {
    final command = args['command'] as String?;
    if (command == null) return _err('missing command argument');
    try {
      final cliArgs = args['args'] is List
          ? (args['args'] as List).cast<String>().toList()
          : const <String>[];
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

  /// Runs the whitelisted [command] line through a shell and returns its
  /// trimmed stdout.
  ///
  /// Java `CommandLineUtils.runCommand` parity: the line is written to a temp
  /// script (avoids shell-escaping issues) and executed with `/bin/sh`, the
  /// real exit code is propagated, and a non-zero exit fails the call.
  ///
  /// This path captures synchronously and cannot mirror output live: the JS
  /// `executeToolViaJava` contract is a synchronous FFI host call, and
  /// `dart:io` has no synchronous streaming API (`Process.runSync` is the
  /// only blocking run). The live stderr mirroring lives on the async
  /// process paths — the CliAgent command phases and the direct CLI tool
  /// executor — see `process_output_tee.dart`.
  String _runCommandLine(String command, String? workDir) {
    final env = _cliProcessEnv(workDir);
    try {
      final result = Platform.isWindows
          ? Process.runSync('cmd.exe', ['/c', '$command 2>&1'],
              workingDirectory: workDir, environment: env)
          : _runShellScript(command, workDir, env);
      // Java merges stdout and stderr (`redirectErrorStream(true)`), so the
      // script redirects the whole command group into stdout.
      final output = result.stdout.toString().trim();
      if (result.exitCode != 0) {
        return _err('Command execution failed (exit code '
            '${result.exitCode}): $output');
      }
      // The FFI host callback marshals through JSON, so a plain-string
      // result (Java `executeCommand` parity) is returned JSON-encoded and
      // surfaces to JS as an unquoted string.
      return jsonEncode(output);
    } catch (e) {
      return _err('Command execution failed: $e');
    }
  }

  /// Writes [command] to a temp shell script and runs it with `/bin/sh`.
  ProcessResult _runShellScript(
      String command, String? workDir, Map<String, String> env) {
    final script = File('${Directory.systemTemp.path}/dmtools_cli_'
        '${DateTime.now().microsecondsSinceEpoch}.sh');
    script.writeAsStringSync('{\n$command\n} 2>&1\n');
    try {
      return Process.runSync('/bin/sh', [script.path],
          workingDirectory: workDir, environment: env);
    } finally {
      try {
        script.deleteSync();
      } catch (_) {}
    }
  }

  /// Resolves the working directory per Java `resolveWorkingDirectory`:
  /// an explicit [workingDirectory] that exists wins (validated within the
  /// allowed bases); otherwise the git root of the job base directory, then
  /// the base itself — the Dart stand-in for the process cwd a Java CLI
  /// launched from that directory would inherit. Relative paths resolve
  /// against the base.
  String _resolveCliWorkingDir(String? workingDirectory) {
    final base = _workingDirectory ?? Directory.current.path;
    if (workingDirectory != null && workingDirectory.trim().isNotEmpty) {
      final specified = Directory(workingDirectory.trim());
      final resolved = specified.isAbsolute
          ? specified
          : Directory('$base/${specified.path}');
      if (resolved.existsSync()) {
        _validateWithinAllowedBase(resolved.absolute.path, base);
        return resolved.path;
      }
    }
    return _cliGitRoot(base) ?? base;
  }

  /// Java `validateWithinAllowedBase` parity: the canonical [dirPath] must
  /// sit inside the job base directory (Java's `user.dir`), its git root,
  /// or the system temp dir — otherwise the call fails (SecurityException
  /// parity, rethrown as a JS `Error`).
  void _validateWithinAllowedBase(String dirPath, String base) {
    String canonical(String p) {
      try {
        return Directory(p).resolveSymbolicLinksSync();
      } catch (_) {
        return p;
      }
    }

    final dir = canonical(dirPath);
    bool within(String? candidate) {
      if (candidate == null) return false;
      final c = canonical(candidate);
      return dir == c || dir.startsWith('$c/');
    }

    if (within(base) || within(_cliGitRoot(base))) return;
    if (within(Directory.systemTemp.path)) return;
    throw Exception('Working directory is outside allowed base paths '
        '(user.dir, git root, tmpdir): $dirPath');
  }

  /// Detects the git repository root containing [base], or `null` when
  /// [base] is not inside a repository (Java `resolveWorkingDirectory`
  /// git-root detection parity).
  String? _cliGitRoot(String base) {
    try {
      final result = Process.runSync(
          'git', const ['rev-parse', '--show-toplevel'],
          workingDirectory: base);
      final root = result.stdout.toString().trim();
      if (result.exitCode == 0 &&
          root.isNotEmpty &&
          Directory(root).existsSync()) {
        return root;
      }
    } catch (_) {}
    return null;
  }

  /// Java `loadEnvironmentVariables` parity: non-interactive git defaults,
  /// a PATH extended with common tool installation directories,
  /// `dmtools.env` from the resolved working directory, and job-level
  /// overrides on top.
  Map<String, String> _cliProcessEnv(String? workDir) {
    final env = <String, String>{
      'GIT_PAGER': 'cat',
      'GIT_TERMINAL_PROMPT': '0',
    };
    var path = Platform.environment['PATH'] ?? '';
    for (final dir in const [
      '/usr/local/bin',
      '/opt/homebrew/bin',
      '/usr/bin',
      '/bin'
    ]) {
      if (!path.contains(dir)) path = '$path:$dir';
    }
    env['PATH'] = path;
    if (workDir != null) {
      env.addAll(parseEnvFile('$workDir/dmtools.env'));
    }
    env.addAll(PropertyReader.getOverrides());
    return env;
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
      return _successJson;
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
      return _successJson;
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _move(String source, String dest) {
    try {
      File(_resolve(source)).renameSync(_resolve(dest));
      return _successJson;
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _mkdir(String path) {
    try {
      Directory(_resolve(path)).createSync(recursive: true);
      return _successJson;
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
      return _successJson;
    } catch (e) {
      return _err(e.toString());
    }
  }

  String _append(String path, String content) {
    try {
      File(_resolve(path)).writeAsStringSync(content, mode: FileMode.append);
      return _successJson;
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

  /// Resolves [path] against the working directory when relative.
  String _resolve(String path) {
    if (path.startsWith('/')) return path;
    final base = _workingDirectory ?? Directory.current.path;
    return '$base/$path';
  }
}

// ── Console bridge ──────────────────────────────────────────────────────

/// JS bootstrap that builds the public host-function globals over the
/// private `__…Host` functions registered by [ToolBridge.registerOn].
///
/// FFI host functions cannot throw into JS, so validation failures return
/// a `{'__jsError': <message>}` sentinel object; the wrapper turns that
/// into a real JS `Error` (Java `IllegalArgumentException` parity). All
/// other results pass through untouched.
const String _hostFunctionBootstrap = '''
(function() {
    function __unwrapHostError(result) {
        if (result !== null && result !== undefined &&
                typeof result === 'object' &&
                result.__jsError !== undefined) {
            throw new Error(result.__jsError);
        }
        return result;
    }
    globalThis.executeToolViaJava = function() {
        return __unwrapHostError(
            __executeToolViaJavaHost.apply(null, arguments));
    };
    globalThis.file_read = function() {
        return __unwrapHostError(__fileReadHost.apply(null, arguments));
    };
    globalThis.set_env_variable = function() {
        return __unwrapHostError(
            __setEnvVariableHost.apply(null, arguments));
    };
})();
''';

/// JS bootstrap that builds the `console` object over the private host
/// functions registered by [_registerConsole].
///
/// Arguments are formatted in JS (strings as-is, other values via
/// `JSON.stringify`) and joined with spaces, matching the console
/// convention used by testRunner.js and agent scripts.
const String _consoleBootstrap = '''
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

/// JSON body returned by host functions that only signal success.
const _successJson = '{"success":true}';

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

// ── Helpers ─────────────────────────────────────────────────────────────

Map<String, dynamic> _castArgs(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

/// Decodes a host-call argument payload.
///
/// The C bridge marshals a JS call with **no** arguments as a bare object
/// whose string form (`[object Object]`) is not JSON — decoded here as
/// `null` so callers treat it as "no arguments" instead of crashing (a
/// crashed host callback surfaces as JS `undefined`, losing the error).
dynamic _decodeArgs(String argsJson) {
  try {
    return jsonDecode(argsJson);
  } on FormatException {
    return null;
  }
}

String _err(String message) => jsonEncode({'error': message});

/// Sentinel body for host-function argument validation: a JS bootstrap
/// wrapper turns this into a real JS `Error` (see [_hostFunctionBootstrap]).
String _jsError(String message) => jsonEncode({'__jsError': message});
