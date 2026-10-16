/// MCP tool definitions and executor for CLI command execution.
///
/// Ports the `cli_execute_command` tool from the Java DMTools catalog with
/// the same command whitelist mechanics: built-in defaults extended by the
/// `CLI_ALLOWED_COMMANDS` environment variable.
library;

import 'dart:io';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'allowed_base.dart';
import 'process_output_tee.dart';

/// Built-in whitelist of allowed CLI commands.
const Set<String> defaultAllowedCommands = {
  'git',
  'gh',
  'dmtools',
  'npm',
  'yarn',
  'docker',
  'kubectl',
  'terraform',
  'ansible',
  'aws',
  'gcloud',
  'az',
};

/// Returns the CLI MCP tool definitions.
List<ToolDefinition> cliTools() => [
      ToolDefinition(
        name: 'cli_execute_command',
        description: 'Execute a whitelisted CLI command and capture output',
        integration: 'cli',
        category: 'system',
        params: [
          ToolParam(
            name: 'command',
            description: 'CLI command to execute. Must start with a '
                'whitelisted command. Extend the whitelist via '
                'CLI_ALLOWED_COMMANDS in dmtools.env.',
            required: true,
          ),
          ToolParam(
            name: 'workingDirectory',
            description: 'Working directory for command execution. Defaults '
                'to repository root if not specified. Use absolute path or '
                'path relative to current directory.',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'cli_execute_command_with_env',
        description: 'Execute a whitelisted CLI command with extra env vars',
        integration: 'cli',
        category: 'system',
        params: [
          ToolParam(name: 'command', description: 'The CLI command to run'),
          ToolParam(
            name: 'args',
            description: 'Arguments to pass to the command',
            type: 'array',
            required: false,
          ),
          ToolParam(
            name: 'env_vars',
            description: 'Extra environment variables for the process',
            type: 'object',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'cli_list_allowed_commands',
        description: 'List all whitelisted CLI commands as a sorted array',
        integration: 'cli',
        category: 'system',
      ),
    ];

/// Executes CLI MCP tools via a streaming capture process run, enforcing
/// the command whitelist. Output lines are mirrored live to dmtools' stderr
/// (see [runCaptured]) while the `{stdout, stderr, exitCode}` result
/// stays byte-identical to a full-buffer capture.
class CliToolExecutor {
  /// Creates a CLI tool executor.
  ///
  /// When [propertyReader] is supplied, extra commands from the
  /// `CLI_ALLOWED_COMMANDS` env var are merged into the whitelist.
  CliToolExecutor([this.propertyReader]);

  /// Optional property reader for the `CLI_ALLOWED_COMMANDS` extension.
  final PropertyReader? propertyReader;

  /// Returns the full set of allowed commands (defaults + env extension).
  Set<String> get allowedCommands {
    final extra = _extraCommands();
    if (extra.isEmpty) return defaultAllowedCommands;
    return {...defaultAllowedCommands, ...extra};
  }

  Set<String> _extraCommands() {
    final pr = propertyReader;
    if (pr == null) return const {};
    return pr.getCliAllowedCommands();
  }

  /// Returns `true` if [command] is in the whitelist.
  bool isAllowed(String command) => allowedCommands.contains(command);

  /// Returns the full whitelist as a sorted array.
  List<String> getAllowedCommands() => (allowedCommands.toList()..sort());

  /// Executes [command] with optional [args], mirroring every output line
  /// live to dmtools' stderr ([mirror] overrides the target for tests).
  ///
  /// [workingDirectory] runs the child inside that directory (absolute, or
  /// relative to the process CWD). It is validated within the allowed base
  /// directories — the process CWD, its git root, the system temp dir —
  /// per Java `validateWithinAllowedBase` parity, the same sandbox the
  /// JS-bridge path for this tool enforces; a directory outside them
  /// throws. When null the child inherits the process CWD, as before.
  ///
  /// Returns a map with `stdout`, `stderr`, and `exitCode`.
  /// Throws [ArgumentError] if the command is not whitelisted.
  Future<Map<String, dynamic>> executeCommand(
    String command, {
    List<String>? args,
    String? workingDirectory,
    OutputLineSink? mirror,
  }) async {
    if (!isAllowed(command)) {
      throw ArgumentError('Command not allowed: $command');
    }
    final result = await runCaptured(
      command,
      args ?? const [],
      workingDirectory: _validatedWorkingDir(workingDirectory),
      mirror: mirror,
    );
    return _resultMap(result);
  }

  /// Resolves [workingDirectory] against the process CWD and validates it
  /// within the allowed bases (Java `validateWithinAllowedBase` parity) —
  /// the same check the JS-bridge path applies, so both surfaces of the
  /// tool enforce the same sandbox. Null inherits the process CWD.
  ///
  /// A specified directory that does not exist falls back to the git root
  /// of the base (then the base), the same resolution the JS-bridge path
  /// applies (Java `resolveWorkingDirectory` parity) — `Process.start`
  /// would otherwise throw a [ProcessException] for the exact input the
  /// bridge resolves, so a typo'd `workingDirectory` would fail on this
  /// surface while succeeding in the git root on the bridge.
  String? _validatedWorkingDir(String? workingDirectory) {
    if (workingDirectory == null || workingDirectory.trim().isEmpty) {
      return null;
    }
    final base = Directory.current.path;
    final specified = Directory(workingDirectory.trim());
    final resolved =
        specified.isAbsolute ? specified : Directory('$base/${specified.path}');
    if (!resolved.existsSync()) {
      return gitRepositoryRoot(base) ?? base;
    }
    validateWithinAllowedBase(resolved.absolute.path, base);
    return resolved.path;
  }

  /// Executes [command] with [args] and extra [envVars], mirroring every
  /// output line live to dmtools' stderr ([mirror] overrides the target for
  /// tests).
  ///
  /// Returns a map with `stdout`, `stderr`, and `exitCode`.
  /// Throws [ArgumentError] if the command is not whitelisted.
  Future<Map<String, dynamic>> executeCommandWithEnv(
    String command, {
    List<String>? args,
    Map<String, String>? envVars,
    OutputLineSink? mirror,
  }) async {
    if (!isAllowed(command)) {
      throw ArgumentError('Command not allowed: $command');
    }
    final result = await runCaptured(
      command,
      args ?? const [],
      environment: envVars,
      mirror: mirror,
    );
    return _resultMap(result);
  }

  Map<String, dynamic> _resultMap(CapturedProcessResult result) => {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      };

  /// Dispatches [toolName] with [args] to the matching CLI executor method.
  ///
  /// Throws [ArgumentError] for an unknown CLI tool name.
  Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown CLI tool: $toolName');
    }
    return handler(args);
  }

  List<String> _parseArgs(dynamic value) {
    if (value is List) return value.cast<String>();
    return const [];
  }

  Map<String, String> _parseEnv(dynamic value) {
    if (value is Map) return value.cast<String, String>();
    return const {};
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String,
      Future<Map<String, dynamic>> Function(Map<String, dynamic>)> _handlers = {
    'cli_execute_command': (a) => executeCommand(
          a['command'] as String,
          args: _parseArgs(a['args']),
          workingDirectory: a['workingDirectory'] as String?,
        ),
    'cli_execute_command_with_env': (a) => executeCommandWithEnv(
          a['command'] as String,
          args: _parseArgs(a['args']),
          envVars: _parseEnv(a['env_vars']),
        ),
    'cli_list_allowed_commands': (a) async =>
        {'commands': getAllowedCommands()},
  };
}
