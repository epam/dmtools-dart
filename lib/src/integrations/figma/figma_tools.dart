/// MCP tool definitions and dispatcher for the Figma integration.
///
/// The tool list ports the Figma subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [FigmaClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'figma_client.dart';

/// Returns all Figma MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> figmaTools() => [
      ToolDefinition(
        name: 'figma_test',
        description: 'Test Figma connectivity by fetching the current user',
        integration: 'figma',
        category: 'system',
        params: [],
      ),
      ToolDefinition(
        name: 'figma_get_file',
        description: 'Get a Figma file by key',
        integration: 'figma',
        category: 'files',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_file_nodes',
        description: 'Get specific nodes from a Figma file',
        integration: 'figma',
        category: 'files',
        params: [
          _keyParam(),
          ToolParam(
            name: 'node_ids',
            description: 'Comma-separated node IDs to fetch',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_image',
        description: 'Export a Figma node as an image',
        integration: 'figma',
        category: 'images',
        params: [
          _keyParam(),
          ToolParam(
            name: 'node_id',
            description: 'The node ID to export as an image',
            required: true,
          ),
        ],
      ),
    ];

/// Shared `key` parameter (Figma file key).
ToolParam _keyParam() => ToolParam(
      name: 'key',
      description: 'The Figma file key',
      required: true,
    );

/// Executes Figma MCP tools by dispatching to [FigmaClient].
class FigmaToolExecutor {
  final FigmaClient _client;

  /// Creates an executor bound to [_client].
  FigmaToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Figma tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Figma tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'figma_test': (_) => _client.testConnection(),
    'figma_get_file': (a) => _client.getFile(a['key'] as String),
    'figma_get_file_nodes': (a) => _client.getFileNodes(
          a['key'] as String,
          a['node_ids'] as String,
        ),
    'figma_get_image': (a) => _client.getImage(
          a['key'] as String,
          a['node_id'] as String,
        ),
  };
}
