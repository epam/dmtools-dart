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
      ..._pageDeleteTools(),
      ..._searchTools(),
      ..._spaceTools(),
      ..._labelTools(),
      ..._attachmentTools(),
      ..._blogTools(),
      ..._contentTools(),
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

/// Page-read tools: `confluence_get_page` / `confluence_get_page_by_id`.
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
      ToolDefinition(
        name: 'confluence_get_page_by_id',
        description: 'Get a Confluence page by id, including body and version',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'id',
            description: 'The Confluence page id',
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

/// Page-delete tool: `confluence_delete_page`.
List<ToolDefinition> _pageDeleteTools() => [
      ToolDefinition(
        name: 'confluence_delete_page',
        description: 'Delete a Confluence page by id',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'id',
            description: 'The Confluence page id',
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

/// Space tool: `confluence_get_spaces`.
List<ToolDefinition> _spaceTools() => [
      ToolDefinition(
        name: 'confluence_get_spaces',
        description: 'List all Confluence spaces visible to the user',
        integration: 'confluence',
        category: 'space',
        params: [],
      ),
    ];

/// Attachment tool: `confluence_get_page_attachments`.
List<ToolDefinition> _attachmentTools() => [
      ToolDefinition(
        name: 'confluence_get_page_attachments',
        description: 'List attachments on a Confluence page',
        integration: 'confluence',
        category: 'attachments',
        params: [
          ToolParam(
            name: 'pageId',
            description: 'The Confluence page id',
            required: true,
          ),
        ],
      ),
    ];

/// Label tools: `confluence_add_label` / `confluence_get_labels`.
List<ToolDefinition> _labelTools() => [
      ToolDefinition(
        name: 'confluence_add_label',
        description: 'Add a label to a Confluence page',
        integration: 'confluence',
        category: 'labels',
        params: [
          ToolParam(
            name: 'pageId',
            description: 'The Confluence page id',
            required: true,
          ),
          ToolParam(
            name: 'label',
            description: 'The label name',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_get_labels',
        description: 'List labels on a Confluence page',
        integration: 'confluence',
        category: 'labels',
        params: [
          ToolParam(
            name: 'pageId',
            description: 'The Confluence page id',
            required: true,
          ),
        ],
      ),
    ];

/// Blog-post tool: `confluence_get_blog_posts`.
List<ToolDefinition> _blogTools() => [
      ToolDefinition(
        name: 'confluence_get_blog_posts',
        description: 'List blog posts in a Confluence space',
        integration: 'confluence',
        category: 'blog_posts',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
        ],
      ),
    ];

/// Content-hierarchy tool: `confluence_get_content_children`.
List<ToolDefinition> _contentTools() => [
      ToolDefinition(
        name: 'confluence_get_content_children',
        description: 'List direct child pages of a Confluence page',
        integration: 'confluence',
        category: 'content_hierarchy',
        params: [
          ToolParam(
            name: 'id',
            description: 'The Confluence page id',
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
    'confluence_get_page_by_id': (a) => _client.getPageById(a['id'] as String),
    'confluence_delete_page': (a) => _client.deletePage(a['id'] as String),
    'confluence_get_spaces': (_) => _client.getSpaces(),
    'confluence_get_page_attachments': (a) =>
        _client.getPageAttachments(a['pageId'] as String),
    'confluence_add_label': (a) => _client.addLabel(
          a['pageId'] as String,
          a['label'] as String,
        ),
    'confluence_get_labels': (a) => _client.getLabels(a['pageId'] as String),
    'confluence_get_blog_posts': (a) =>
        _client.getBlogPosts(a['spaceKey'] as String),
    'confluence_get_content_children': (a) =>
        _client.getContentChildren(a['id'] as String),
  };
}
