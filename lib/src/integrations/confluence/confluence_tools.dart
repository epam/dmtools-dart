/// MCP tool definitions and dispatcher for the Confluence integration.
///
/// The tool list ports the Confluence subset of the Java `@MCPTool` catalog;
/// the executor routes a tool name + arguments to the matching
/// [ConfluenceClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'confluence_client.dart';

/// Returns all Confluence MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> confluenceTools() => [
      ..._systemTools(),
      ..._pageReadTools(),
      ..._pageWriteTools(),
      ..._searchTools(),
    ];

/// Connectivity-check tool: `confluence_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'confluence_test',
        description: 'Test Confluence connectivity by fetching the current '
            'user profile',
        integration: 'confluence',
        category: 'system',
        params: [],
      ),
    ];

/// Page-read tool: `confluence_get_page`.
List<ToolDefinition> _pageReadTools() => [
      ToolDefinition(
        name: 'confluence_get_page',
        description: 'Get a Confluence page by space key and title',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
          ToolParam(
            name: 'title',
            description: 'The exact page title',
            required: true,
          ),
        ],
      ),
    ];

/// Page-write tools: `confluence_create_page` / `confluence_update_page`.
List<ToolDefinition> _pageWriteTools() => [
      ToolDefinition(
        name: 'confluence_create_page',
        description: 'Create a new Confluence page in the given space',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
          ToolParam(
            name: 'title',
            description: 'The page title',
            required: true,
          ),
          ToolParam(
            name: 'body',
            description: 'The page body in Confluence storage format (XHTML)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_update_page',
        description: 'Update an existing Confluence page by id',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'id',
            description: 'The Confluence page id',
            required: true,
          ),
          ToolParam(
            name: 'title',
            description: 'The page title',
            required: true,
          ),
          ToolParam(
            name: 'body',
            description: 'The page body in Confluence storage format (XHTML)',
            required: true,
          ),
          ToolParam(
            name: 'version',
            description: 'The new version number (current + 1)',
            type: 'number',
            required: true,
          ),
        ],
      ),
    ];

/// CQL search tool: `confluence_search`.
List<ToolDefinition> _searchTools() => [
      ToolDefinition(
        name: 'confluence_search',
        description: 'Search Confluence content using a CQL query',
        integration: 'confluence',
        category: 'search',
        params: [
          ToolParam(
            name: 'cql',
            description: 'The CQL query string',
            required: true,
          ),
        ],
      ),
    ];

/// Executes Confluence MCP tools by dispatching to [ConfluenceClient].
class ConfluenceToolExecutor {
  final ConfluenceClient _client;

  /// Creates an executor bound to [_client].
  ConfluenceToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Confluence tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Confluence tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'confluence_test': (_) => _client.testConnection(),
    'confluence_get_page': (a) => _client.getPage(
          a['spaceKey'] as String,
          a['title'] as String,
        ),
    'confluence_create_page': (a) => _client.createPage(
          a['spaceKey'] as String,
          a['title'] as String,
          a['body'] as String,
        ),
    'confluence_update_page': (a) => _client.updatePage(
          a['id'] as String,
          a['title'] as String,
          a['body'] as String,
          (a['version'] as num).toInt(),
        ),
    'confluence_search': (a) => _client.search(a['cql'] as String),
  };
}
