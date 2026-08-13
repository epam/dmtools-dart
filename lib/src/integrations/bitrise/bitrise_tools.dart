/// MCP tool definitions and dispatcher for the Bitrise integration.
///
/// The tool list ports the Bitrise subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [BitriseClient]
/// call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'bitrise_client.dart';

/// Returns all Bitrise MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> bitriseTools() => [
      ..._systemTools(),
      ..._buildTools(),
    ];

/// Connectivity-check tool: `bitrise_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'bitrise_test',
        description: 'Test Bitrise connectivity by listing apps',
        integration: 'bitrise',
        category: 'system',
        params: [],
      ),
    ];

/// Build tools: `bitrise_get_builds`, `bitrise_trigger_build`.
List<ToolDefinition> _buildTools() => [
      _getBuildsTool(),
      _triggerBuildTool(),
    ];

/// Build-list tool: `bitrise_get_builds`.
ToolDefinition _getBuildsTool() => ToolDefinition(
      name: 'bitrise_get_builds',
      description: 'List builds for a Bitrise app by app slug',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
      ],
    );

/// Build-trigger tool: `bitrise_trigger_build`.
ToolDefinition _triggerBuildTool() => ToolDefinition(
      name: 'bitrise_trigger_build',
      description: 'Trigger a new build for a Bitrise app by app slug',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
      ],
    );

/// Executes Bitrise MCP tools by dispatching to [BitriseClient].
class BitriseToolExecutor {
  final BitriseClient _client;

  /// Creates an executor bound to [_client].
  BitriseToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Bitrise tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Bitrise tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'bitrise_test': (_) => _client.testConnection(),
    'bitrise_get_builds': (a) => _client.getBuilds(a['app_slug'] as String),
    'bitrise_trigger_build': (a) =>
        _client.triggerBuild(a['app_slug'] as String),
  };
}
