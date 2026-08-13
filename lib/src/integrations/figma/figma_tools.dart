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
      ..._systemTools(),
      ..._fileTools(),
      ..._imageTools(),
      ..._commentTools(),
      ..._componentTools(),
      ..._styleTools(),
    ];

/// Connectivity-check tool: `figma_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'figma_test',
        description: 'Test Figma connectivity by fetching the current user',
        integration: 'figma',
        category: 'system',
        params: [],
      ),
    ];

/// File tools: `figma_get_file`, `figma_get_file_nodes`.
List<ToolDefinition> _fileTools() => [
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
    ];

/// Image tools: `figma_get_image`, `figma_export_image`.
List<ToolDefinition> _imageTools() => [
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
      ToolDefinition(
        name: 'figma_export_image',
        description: 'Export nodes from a Figma file as images',
        integration: 'figma',
        category: 'images',
        params: [
          _keyParam(),
          ToolParam(
            name: 'format',
            description: 'Image format: jpg, png, or svg (default png)',
            required: false,
          ),
          ToolParam(
            name: 'scale',
            description: 'Zoom factor for rasterized exports (default 1)',
            required: false,
            type: 'number',
          ),
        ],
      ),
    ];

/// Comment tools: `figma_get_comments`, `figma_post_comment`.
List<ToolDefinition> _commentTools() => [
      ToolDefinition(
        name: 'figma_get_comments',
        description: 'Get comments on a Figma file',
        integration: 'figma',
        category: 'comments',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_post_comment',
        description: 'Post a comment on a Figma file',
        integration: 'figma',
        category: 'comments',
        params: [_keyParam(), _messageParam()],
      ),
    ];

/// Component tools: `figma_get_components`, `figma_get_component_sets`.
List<ToolDefinition> _componentTools() => [
      ToolDefinition(
        name: 'figma_get_components',
        description: 'Get components from a Figma file',
        integration: 'figma',
        category: 'components',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_component_sets',
        description: 'Get component sets from a Figma file',
        integration: 'figma',
        category: 'components',
        params: [_keyParam()],
      ),
    ];

/// Style tool: `figma_get_styles`.
List<ToolDefinition> _styleTools() => [
      ToolDefinition(
        name: 'figma_get_styles',
        description: 'Get styles from a Figma file',
        integration: 'figma',
        category: 'styles',
        params: [_keyParam()],
      ),
    ];

/// Shared `key` parameter (Figma file key).
ToolParam _keyParam() => ToolParam(
      name: 'key',
      description: 'The Figma file key',
      required: true,
    );

/// Shared `message` parameter (comment text).
ToolParam _messageParam() => ToolParam(
      name: 'message',
      description: 'The comment message text',
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
    'figma_get_comments': (a) => _client.getComments(a['key'] as String),
    'figma_post_comment': (a) => _client.postComment(
          a['key'] as String,
          a['message'] as String,
        ),
    'figma_get_components': (a) => _client.getComponents(a['key'] as String),
    'figma_get_component_sets': (a) =>
        _client.getComponentSets(a['key'] as String),
    'figma_get_styles': (a) => _client.getStyles(a['key'] as String),
    'figma_export_image': (a) => _client.exportImage(
          a['key'] as String,
          format: a['format'] as String?,
          scale: (a['scale'] as num?)?.toDouble(),
        ),
  };
}
