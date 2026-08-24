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
      ..._spaceContentTools(),
      ..._labelTools(),
      ..._attachmentTools(),
      ..._blogTools(),
      ..._contentTools(),
      ..._pageLifecycleTools(),
      ..._permissionTools(),
      ..._propertyTools(),
      ..._groupTools(),
      ..._userTools(),
      ..._watcherTools(),
      ..._contentRetrievalTools(),
      ..._markdownSyncTools(),
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
        description: 'Update an existing Confluence page with new title, '
            'parent, body content, and space. Returns the updated content '
            'object',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The ID of the page to update',
            required: true,
          ),
          ToolParam(
            name: 'title',
            description: 'The new title for the page',
            required: true,
          ),
          ToolParam(
            name: 'parentId',
            description: 'The ID of the new parent page',
            required: true,
          ),
          ToolParam(
            name: 'body',
            description: 'The page body in Confluence storage format (XHTML)',
            required: true,
          ),
          ToolParam(
            name: 'space',
            description: 'The space key where the page is located',
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

/// Space tools: `confluence_get_spaces` / `confluence_get_space_by_key` /
/// `confluence_update_space`.
List<ToolDefinition> _spaceTools() => [
      ToolDefinition(
        name: 'confluence_get_spaces',
        description: 'List all Confluence spaces visible to the user',
        integration: 'confluence',
        category: 'space',
        params: [],
      ),
      ToolDefinition(
        name: 'confluence_get_space_by_key',
        description: 'Get a Confluence space by its key',
        integration: 'confluence',
        category: 'space',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_update_space',
        description: 'Update the name and description of a Confluence space',
        integration: 'confluence',
        category: 'space',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
          ToolParam(
            name: 'name',
            description: 'The new space name',
            required: true,
          ),
          ToolParam(
            name: 'description',
            description: 'The new space description (plain text)',
            required: true,
          ),
        ],
      ),
    ];

/// Space-content tools: `confluence_get_space_content` /
/// `confluence_create_space`.
List<ToolDefinition> _spaceContentTools() => [
      ToolDefinition(
        name: 'confluence_get_space_content',
        description: 'List all content of a given type in a Confluence space',
        integration: 'confluence',
        category: 'space',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
          ToolParam(
            name: 'type',
            description: 'The content type to list (e.g. page, blogpost)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_create_space',
        description: 'Create a new Confluence space with a key and name',
        integration: 'confluence',
        category: 'space',
        params: [
          ToolParam(
            name: 'key',
            description: 'The space key (e.g. ENG)',
            required: true,
          ),
          ToolParam(
            name: 'name',
            description: 'The human-readable space name',
            required: true,
          ),
        ],
      ),
    ];

/// Attachment tools: `confluence_get_page_attachments`,
/// `confluence_download_attachment`.
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
      ToolDefinition(
        name: 'confluence_download_attachment',
        description: 'Download the raw content of a Confluence attachment',
        integration: 'confluence',
        category: 'attachments',
        params: [
          ToolParam(
            name: 'pageId',
            description: 'The Confluence page id',
            required: true,
          ),
          ToolParam(
            name: 'attachmentId',
            description: 'The attachment id',
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

/// Page-lifecycle tools: `confluence_move_page` /
/// `confluence_get_page_history`.
List<ToolDefinition> _pageLifecycleTools() => [
      ToolDefinition(
        name: 'confluence_move_page',
        description: 'Move a Confluence page under a new parent page',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'pageId',
            description: 'The id of the page to move',
            required: true,
          ),
          ToolParam(
            name: 'targetId',
            description: 'The id of the new parent page',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_get_page_history',
        description: 'List the version history of a Confluence page',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'pageId',
            description: 'The Confluence page id',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_archive_page',
        description: 'Archive a Confluence page by id',
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
      ToolDefinition(
        name: 'confluence_restore_page',
        description: 'Restore an archived Confluence page to current',
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

/// Permission tools: `confluence_get_permissions` /
/// `confluence_add_permission`.
List<ToolDefinition> _permissionTools() => [
      ToolDefinition(
        name: 'confluence_get_permissions',
        description: 'List content permissions for a Confluence space',
        integration: 'confluence',
        category: 'permissions',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_add_permission',
        description: 'Add a content permission to a Confluence space',
        integration: 'confluence',
        category: 'permissions',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The Confluence space key (e.g. ENG)',
            required: true,
          ),
          ToolParam(
            name: 'permission',
            description: 'The permission entry as a JSON object',
            required: true,
          ),
        ],
      ),
    ];

/// Property tools: `confluence_get_page_properties` /
/// `confluence_set_page_property`.
List<ToolDefinition> _propertyTools() => [
      ToolDefinition(
        name: 'confluence_get_page_properties',
        description: 'List content properties on a Confluence page',
        integration: 'confluence',
        category: 'properties',
        params: [
          ToolParam(
            name: 'id',
            description: 'The Confluence page id',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_set_page_property',
        description: 'Set a content property on a Confluence page',
        integration: 'confluence',
        category: 'properties',
        params: [
          ToolParam(
            name: 'id',
            description: 'The Confluence page id',
            required: true,
          ),
          ToolParam(
            name: 'key',
            description: 'The property key',
            required: true,
          ),
          ToolParam(
            name: 'value',
            description: 'The property value as a JSON object',
            required: true,
          ),
        ],
      ),
    ];

/// Group tools: `confluence_get_group_members`.
List<ToolDefinition> _groupTools() => [
      ToolDefinition(
        name: 'confluence_get_group_members',
        description: 'List the members of a Confluence group by name',
        integration: 'confluence',
        category: 'groups',
        params: [
          ToolParam(
            name: 'groupname',
            description: 'The Confluence group name',
            required: true,
          ),
        ],
      ),
    ];

/// User tools: `confluence_get_user_by_key`.
List<ToolDefinition> _userTools() => [
      ToolDefinition(
        name: 'confluence_get_user_by_key',
        description: 'Get a Confluence user by key',
        integration: 'confluence',
        category: 'users',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Confluence user key',
            required: true,
          ),
        ],
      ),
    ];

/// Watcher tools: `confluence_get_watchers`.
List<ToolDefinition> _watcherTools() => [
      ToolDefinition(
        name: 'confluence_get_watchers',
        description: 'List the watchers of a Confluence content item',
        integration: 'confluence',
        category: 'watchers',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The Confluence content id',
            required: true,
          ),
        ],
      ),
    ];

/// Content-retrieval tools (Java `Confluence.java`): `confluence_content_by_id`
/// / `confluence_get_children_by_id`.
List<ToolDefinition> _contentRetrievalTools() => [
      ToolDefinition(
        name: 'confluence_content_by_id',
        description: 'Get Confluence content by its unique content ID. Returns '
            'detailed content information including body, version, and '
            'metadata. Use format=md to convert body.storage.value to Markdown',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The unique content ID of the Confluence page',
            required: true,
          ),
          ToolParam(
            name: 'format',
            description: "Output format for the page body. Use 'md' or "
                "'markdown' to convert Confluence storage format to Markdown",
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_get_children_by_id',
        description: 'Get child pages of a Confluence page by content ID. '
            'Returns a list of child content objects. Use format=md to '
            'convert body.storage.value to Markdown',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The content ID of the parent page',
            required: true,
          ),
          ToolParam(
            name: 'format',
            description: "Output format for the page body. Use 'md' or "
                "'markdown' to convert Confluence storage format to Markdown",
            required: false,
          ),
        ],
      ),
    ];

/// Markdown-sync tool (Java `Confluence.java`):
/// `confluence_sync_markdown_directory`.
List<ToolDefinition> _markdownSyncTools() => [
      ToolDefinition(
        name: 'confluence_sync_markdown_directory',
        description: 'Synchronize a local Markdown directory tree to a '
            'Confluence page subtree. Markdown files become child pages, '
            'images and other files become attachments. Links between '
            'Markdown files are rewritten to Confluence page links. Returns a '
            'JSON summary',
        integration: 'confluence',
        category: 'page_management',
        params: [
          ToolParam(
            name: 'directory',
            description: 'The local directory containing Markdown files and '
                'attachments',
            required: true,
          ),
          ToolParam(
            name: 'parentId',
            description: 'The content ID of the parent Confluence page',
            required: true,
          ),
          ToolParam(
            name: 'space',
            description: 'The space key where the pages should be created',
            required: true,
          ),
          ToolParam(
            name: 'deleteOrphans',
            description: 'Whether to delete child pages not present in the '
                'directory tree',
            type: 'boolean',
            required: false,
          ),
          ToolParam(
            name: 'attachmentsDir',
            description: 'Optional directory containing referenced '
                "attachments. Defaults to the Markdown file's directory",
            required: false,
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
          a['contentId'] as String,
          a['title'] as String,
          a['parentId'] as String,
          a['body'] as String,
          a['space'] as String,
        ),
    'confluence_content_by_id': (a) =>
        _client.getPageById(a['contentId'] as String),
    'confluence_get_children_by_id': (a) =>
        _client.getContentChildren(a['contentId'] as String),
    'confluence_search': (a) => _client.search(a['cql'] as String),
    'confluence_get_page_by_id': (a) => _client.getPageById(a['id'] as String),
    'confluence_delete_page': (a) => _client.deletePage(a['id'] as String),
    'confluence_get_spaces': (_) => _client.getSpaces(),
    'confluence_get_page_attachments': (a) =>
        _client.getPageAttachments(a['pageId'] as String),
    'confluence_download_attachment': (a) => _client.downloadAttachment(
          a['pageId'] as String,
          a['attachmentId'] as String,
        ),
    'confluence_add_label': (a) => _client.addLabel(
          a['pageId'] as String,
          a['label'] as String,
        ),
    'confluence_get_labels': (a) => _client.getLabels(a['pageId'] as String),
    'confluence_get_blog_posts': (a) =>
        _client.getBlogPosts(a['spaceKey'] as String),
    'confluence_get_content_children': (a) =>
        _client.getContentChildren(a['id'] as String),
    'confluence_get_space_by_key': (a) =>
        _client.getSpaceByKey(a['spaceKey'] as String),
    'confluence_update_space': (a) => _client.updateSpace(
          a['spaceKey'] as String,
          a['name'] as String,
          a['description'] as String,
        ),
    'confluence_move_page': (a) => _client.movePage(
          a['pageId'] as String,
          a['targetId'] as String,
        ),
    'confluence_get_page_history': (a) =>
        _client.getPageHistory(a['pageId'] as String),
    'confluence_get_permissions': (a) =>
        _client.getPermissions(a['spaceKey'] as String),
    'confluence_add_permission': (a) => _client.addPermission(
          a['spaceKey'] as String,
          a['permission'] as Map<String, dynamic>,
        ),
    'confluence_get_space_content': (a) => _client.getSpaceContent(
          a['spaceKey'] as String,
          a['type'] as String,
        ),
    'confluence_create_space': (a) => _client.createSpace(
          a['key'] as String,
          a['name'] as String,
        ),
    'confluence_archive_page': (a) => _client.archivePage(a['id'] as String),
    'confluence_restore_page': (a) => _client.restorePage(a['id'] as String),
    'confluence_get_page_properties': (a) =>
        _client.getPageProperties(a['id'] as String),
    'confluence_set_page_property': (a) => _client.setPageProperty(
          a['id'] as String,
          a['key'] as String,
          a['value'] as Map<String, dynamic>,
        ),
    'confluence_get_group_members': (a) =>
        _client.getGroupMembers(a['groupname'] as String),
    'confluence_get_user_by_key': (a) =>
        _client.getUserByKey(a['key'] as String),
    'confluence_get_watchers': (a) =>
        _client.getWatchers(a['contentId'] as String),
  };
}
