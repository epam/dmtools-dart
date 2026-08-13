/// MCP tool definitions and dispatcher for the SharePoint integration.
///
/// The tool list ports the SharePoint subset of the Java `@MCPTool` catalog;
/// the executor routes a tool name + arguments to the matching
/// [SharepointClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'sharepoint_client.dart';

/// Returns all SharePoint MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> sharepointTools() => [
      _testTool(),
      _getDriveTool(),
      _listFilesTool(),
    ];

/// Connectivity-check tool: `sharepoint_test`.
ToolDefinition _testTool() => ToolDefinition(
      name: 'sharepoint_test',
      description: 'Test SharePoint connectivity by fetching the default drive',
      integration: 'sharepoint',
      category: 'system',
      params: [],
    );

/// Get-drive tool: `sharepoint_get_drive`.
ToolDefinition _getDriveTool() => ToolDefinition(
      name: 'sharepoint_get_drive',
      description: 'Get the current user default SharePoint drive',
      integration: 'sharepoint',
      category: 'files',
      params: [],
    );

/// List-files tool: `sharepoint_list_files`.
ToolDefinition _listFilesTool() => ToolDefinition(
      name: 'sharepoint_list_files',
      description: 'List files in the root of a SharePoint drive by drive id',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
      ],
    );

/// Executes SharePoint MCP tools by dispatching to [SharepointClient].
class SharepointToolExecutor {
  final SharepointClient _client;

  /// Creates an executor bound to [_client].
  SharepointToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown SharePoint tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown SharePoint tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'sharepoint_test': (_) => _client.testConnection(),
    'sharepoint_get_drive': (_) => _client.getDrive(),
    'sharepoint_list_files': (a) => _client.listFiles(a['drive_id'] as String),
  };
}
