part of 'confluence_tools.dart';

/// The gh-191 Java-named tools (frozen gap snapshot, `Confluence.java`
/// `@MCPTool` annotations), grouped per the file's list-function pattern.

/// All 15 Java-named tool definitions in Java catalog order.
List<ToolDefinition> javaNameConfluenceTools() => [
      ..._javaNameContentByTitleTools(),
      ..._javaNameUrlFetchTools(),
      ..._javaNameFindTools(),
      ..._javaNameFindOrCreateTools(),
      ..._javaNameAttachmentListTools(),
      ..._javaNameProfileAndSearchTools(),
      ..._javaNameHistoryUpdateTools(),
      ..._javaNameUploadTools(),
    ];

/// Default-space title content: `confluence_content_by_title` / `confluence_content_by_title_and_space`.
List<ToolDefinition> _javaNameContentByTitleTools() => [
      ToolDefinition(
        name: 'confluence_content_by_title',
        description: 'Get Confluence content by title in the default space. '
            'Returns content result with metadata and body information. Use '
            'format=md to convert body.storage.value to Markdown.',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'title',
            description: 'Title of the Confluence page to get',
            required: true,
          ),
          _formatParam(),
        ],
      ),
      ToolDefinition(
        name: 'confluence_content_by_title_and_space',
        description: 'Get Confluence content by title and space key. Returns '
            'content result with metadata and body information. Use format=md '
            'to convert body.storage.value to Markdown.',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'title',
            description: 'The title of the Confluence page',
            required: true,
          ),
          ToolParam(
            name: 'space',
            description: 'The space key where the content is located',
            required: true,
          ),
          _formatParam(),
        ],
      ),
    ];

/// URL fetch + recursive page download: `confluence_contents_by_urls` / `confluence_download_pages`.
List<ToolDefinition> _javaNameUrlFetchTools() => [
      ToolDefinition(
        name: 'confluence_contents_by_urls',
        description: 'Get Confluence content by multiple URLs. Returns a list '
            'of content objects for each valid URL. Use format=md to convert '
            'body.storage.value to Markdown.',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'urlStrings',
            description: 'Array of Confluence URLs to retrieve content from',
            required: true,
          ),
          _formatParam(),
        ],
      ),
      ToolDefinition(
        name: 'confluence_download_pages',
        description: 'Download Confluence pages and their attachments to a '
            'local folder. Follows child pages down to the given depth.',
        integration: 'confluence',
        category: 'content_management',
        params: [
          ToolParam(
            name: 'urlStrings',
            description: 'Array of Confluence page URLs to download',
            required: true,
          ),
          ToolParam(
            name: 'outputPath',
            description:
                'Local folder path where pages and attachments will be saved',
            required: true,
          ),
          ToolParam(
            name: 'depth',
            description:
                'How many levels of child pages to follow. Default is 1.',
            required: false,
          ),
          ToolParam(
            name: 'downloadAttachments',
            description:
                'Whether to download page attachments. Default is true.',
            required: false,
          ),
        ],
      ),
    ];

/// Find-by-title family: `confluence_find_content` / `confluence_find_content_by_title_and_space`.
List<ToolDefinition> _javaNameFindTools() => [
      ToolDefinition(
        name: 'confluence_find_content',
        description: 'Find a Confluence page by title in the default space. '
            "Returns the page content if found. Use format=md to convert "
            'body.storage.value to Markdown.',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'title',
            description: 'Title of the Confluence page to find',
            required: true,
          ),
          _formatParam(),
        ],
      ),
      ToolDefinition(
        name: 'confluence_find_content_by_title_and_space',
        description: 'Find Confluence content by title and space key. '
            'Returns the first matching content or null if not found. Use '
            'format=md to convert body.storage.value to Markdown.',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'title',
            description: 'The title of the content to find',
            required: true,
          ),
          ToolParam(
            name: 'space',
            description: 'The space key where to search for the content',
            required: true,
          ),
          _formatParam(),
        ],
      ),
    ];

/// Find-or-create + children-by-name: `confluence_find_or_create` / `confluence_get_children_by_name`.
List<ToolDefinition> _javaNameFindOrCreateTools() => [
      ToolDefinition(
        name: 'confluence_find_or_create',
        description: 'Find a Confluence page by title in the default space, '
            "or create it if it doesn't exist. Returns the found or created "
            'content.',
        integration: 'confluence',
        category: 'content_management',
        params: [
          ToolParam(
            name: 'title',
            description: 'Title of the page to find or create',
            required: true,
          ),
          ToolParam(
            name: 'parentId',
            description: 'ID of the parent page for creation',
            required: true,
          ),
          ToolParam(
            name: 'body',
            description: 'Body content for the new page (if creation is '
                'needed)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_get_children_by_name',
        description: 'Get child pages of a Confluence page by space key and '
            'content name. Returns a list of child content objects. Use '
            'format=md to convert body.storage.value to Markdown.',
        integration: 'confluence',
        category: 'content_retrieval',
        params: [
          ToolParam(
            name: 'spaceKey',
            description: 'The space key where the parent page is located',
            required: true,
          ),
          ToolParam(
            name: 'contentName',
            description: 'The name/title of the parent page',
            required: true,
          ),
          _formatParam(),
        ],
      ),
    ];

/// Attachment listing: `confluence_get_content_attachments`.
List<ToolDefinition> _javaNameAttachmentListTools() => [
      ToolDefinition(
        name: 'confluence_get_content_attachments',
        description: 'Get all attachments for a specific Confluence content. '
            'Returns a list of attachment objects with metadata.',
        integration: 'confluence',
        category: 'content_management',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The content ID to get attachments for',
            required: true,
          ),
        ],
      ),
    ];

/// User profiles + text search: `confluence_get_current_user_profile`, `confluence_get_user_profile_by_id`, `confluence_search_content_by_text`.
List<ToolDefinition> _javaNameProfileAndSearchTools() => [
      ToolDefinition(
        name: 'confluence_get_current_user_profile',
        description: "Get the current user's profile information from "
            'Confluence. Returns user details for the authenticated user.',
        integration: 'confluence',
        category: 'user_management',
        params: [],
      ),
      ToolDefinition(
        name: 'confluence_get_user_profile_by_id',
        description: "Get a specific user's profile information from "
            'Confluence by user ID. Returns user details for the specified '
            'user.',
        integration: 'confluence',
        category: 'user_management',
        params: [
          ToolParam(
            name: 'userId',
            description: 'The account ID of the user to get profile for',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_search_content_by_text',
        description: 'Search Confluence content by text query using CQL '
            '(Confluence Query Language). Returns search results with content '
            'excerpts. Default limit is 20 if not specified.',
        integration: 'confluence',
        category: 'search',
        params: [
          ToolParam(
            name: 'query',
            description: 'Search query text to find in Confluence content',
            required: true,
          ),
          ToolParam(
            name: 'limit',
            description:
                'Maximum number of search results to return. Default is 20 '
                'if not provided.',
            required: false,
          ),
        ],
      ),
    ];

/// History-aware page update: `confluence_update_page_with_history`.
List<ToolDefinition> _javaNameHistoryUpdateTools() => [
      ToolDefinition(
        name: 'confluence_update_page_with_history',
        description: 'Update an existing Confluence page with new content and '
            'add a history comment. Returns the updated content object.',
        integration: 'confluence',
        category: 'content_management',
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
            description:
                'The new body content of the page in Confluence storage format',
            required: true,
          ),
          ToolParam(
            name: 'space',
            description: 'The space key where the page is located',
            required: true,
          ),
          ToolParam(
            name: 'historyComment',
            description: 'Comment to add to the page history',
            required: true,
          ),
        ],
      ),
    ];

/// Attachment uploads: `confluence_upload_attachment` / `confluence_upload_attachments`.
List<ToolDefinition> _javaNameUploadTools() => [
      ToolDefinition(
        name: 'confluence_upload_attachment',
        description:
            'Upload a single file as an attachment to a Confluence page. '
            'Skips existing attachments by default. Returns the attachment '
            'object.',
        integration: 'confluence',
        category: 'content_management',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The content ID of the page to attach the file to',
            required: true,
          ),
          ToolParam(
            name: 'file',
            description: 'The local file to upload',
            required: true,
          ),
          ToolParam(
            name: 'updateIfExists',
            description:
                'Whether to overwrite an existing attachment with the same '
                'name',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'confluence_upload_attachments',
        description:
            'Upload all files in a directory as attachments to a Confluence '
            'page. Existing attachments are skipped by default. Returns a '
            'JSON summary.',
        integration: 'confluence',
        category: 'content_management',
        params: [
          ToolParam(
            name: 'contentId',
            description: 'The content ID of the page to attach files to',
            required: true,
          ),
          ToolParam(
            name: 'directory',
            description: 'The local directory containing files to upload',
            required: true,
          ),
          ToolParam(
            name: 'updateIfExists',
            description:
                'Whether to overwrite existing attachments with the same names',
            required: false,
          ),
        ],
      ),
    ];

/// Handler entries for the Java-named tools, spread into
/// `ConfluenceToolExecutor._handlers`.
Map<String, Future<dynamic> Function(Map<String, dynamic>)> javaNameHandlers(
  ConfluenceClient client,
) =>
    {
      'confluence_content_by_title': (a) =>
          client.contentByTitle(a['title'] as String, a['format'] as String?),
      'confluence_content_by_title_and_space': (a) =>
          client.contentByTitleAndSpace(
            a['title'] as String,
            a['space'] as String,
            a['format'] as String?,
          ),
      'confluence_contents_by_urls': (a) => client.contentsByUrls(
            (a['urlStrings'] as List).map((e) => e as String).toList(),
            a['format'] as String?,
          ),
      'confluence_download_pages': (a) => client.downloadPages(
            (a['urlStrings'] as List).map((e) => e as String).toList(),
            a['outputPath'] as String,
            _intArg(a, 'depth', 1) ?? 1,
            _boolArg(a, 'downloadAttachments', fallback: true),
          ),
      'confluence_find_content': (a) => client.findContent(
            a['title'] as String,
            format: a['format'] as String?,
          ),
      'confluence_find_content_by_title_and_space': (a) => client.findContent(
            a['title'] as String,
            space: a['space'] as String,
            format: a['format'] as String?,
          ),
      'confluence_find_or_create': (a) => client.findOrCreate(
            a['title'] as String,
            a['parentId'] as String,
            a['body'] as String,
          ),
      'confluence_get_children_by_name': (a) => client.getChildrenByName(
            a['spaceKey'] as String,
            a['contentName'] as String,
            a['format'] as String?,
          ),
      'confluence_get_content_attachments': (a) =>
          client.getContentAttachments(a['contentId'] as String),
      'confluence_get_current_user_profile': (_) =>
          client.getCurrentUserProfile(),
      'confluence_get_user_profile_by_id': (a) =>
          client.getUserProfileById(a['userId'] as String),
      'confluence_search_content_by_text': (a) => client.searchContentByText(
            a['query'] as String,
            _intArg(a, 'limit'),
          ),
      'confluence_update_page_with_history': (a) =>
          client.updatePageWithHistory(
            contentId: a['contentId'] as String,
            title: a['title'] as String,
            parentId: a['parentId'] as String,
            body: a['body'] as String,
            space: a['space'] as String,
            historyComment: a['historyComment'] as String,
          ),
      'confluence_upload_attachment': (a) => client.uploadAttachment(
            a['contentId'] as String,
            a['file'] as String,
            _boolArg(a, 'updateIfExists'),
          ),
      'confluence_upload_attachments': (a) => client.uploadAttachments(
            a['contentId'] as String,
            a['directory'] as String,
            _boolArg(a, 'updateIfExists'),
          ),
    };
