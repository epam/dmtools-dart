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

/// Returns the CLI MCP tool definition.
List<ToolDefinition> cliTools() => [
      ToolDefinition(
        name: 'cli_execute_command',
        description: 'Execute a whitelisted CLI command and capture output',
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
        ],
      ),
    ];

/// Executes CLI MCP tools via [Process.run], enforcing the command whitelist.
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

  /// Executes [command] with optional [args] via [Process.run].
  ///
  /// Returns a map with `stdout`, `stderr`, and `exitCode`.
  /// Throws [ArgumentError] if the command is not whitelisted.
  Future<Map<String, dynamic>> executeCommand(
    String command, [
    List<String>? args,
  ]) async {
    if (!isAllowed(command)) {
      throw ArgumentError('Command not allowed: $command');
    }
    final result = await Process.run(command, args ?? const []);
    return {
      'stdout': result.stdout.toString(),
      'stderr': result.stderr.toString(),
      'exitCode': result.exitCode,
    };
  }

  /// Dispatches [toolName] with [args] to [executeCommand].
  ///
  /// Throws [ArgumentError] for an unknown CLI tool name.
  Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> args,
  ) {
    if (toolName != 'cli_execute_command') {
      throw ArgumentError('Unknown CLI tool: $toolName');
    }
    final command = args['command'] as String;
    final cmdArgs = _parseArgs(args['args']);
    return executeCommand(command, cmdArgs);
  }

  List<String> _parseArgs(dynamic value) {
    if (value is List) return value.cast<String>();
    return const [];
  }
}
