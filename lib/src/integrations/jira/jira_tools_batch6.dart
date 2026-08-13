/// Batch-6 Jira tool definitions and dispatch — split for file-size.
part of 'jira_tools.dart';

/// Returns all batch-6 Jira tool definitions.
List<ToolDefinition> _batch6Tools() => [
      ..._batch6SearchTools(),
      ..._batch6AttachmentTools(),
      ..._batch6WorklogTools(),
      ..._batch6WatcherTools(),
      ..._batch6ResolutionTools(),
    ];

/// Page-level search tools: cursor page + offset page (deprecated).
List<ToolDefinition> _batch6SearchTools() => [
      _jiraTool(
        name: 'jira_search_by_page',
        description: 'Search Jira issues by JQL returning a single cursor page',
        category: 'search',
        params: [
          ToolParam(
            name: 'jql',
            description: 'The JQL query string',
            required: true,
          ),
          ToolParam(
            name: 'nextPageToken',
            description: 'Cursor from a prior page; omit for the first page',
            required: false,
          ),
          ToolParam(
            name: 'fields',
            description: 'Comma-separated field names to return',
            type: 'array',
            required: false,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_search_with_pagination',
        description: 'Search Jira issues by JQL with offset-based pagination '
            '(deprecated)',
        category: 'search',
        params: [
          ToolParam(
            name: 'jql',
            description: 'The JQL query string',
            required: true,
          ),
          ToolParam(
            name: 'startAt',
            description: 'The zero-based index of the first issue to return',
            type: 'integer',
            required: false,
          ),
          ToolParam(
            name: 'fields',
            description: 'Comma-separated field names to return',
            type: 'array',
            required: false,
          ),
        ],
      ),
    ];

/// Attachment read tool: `jira_get_attachments`.
List<ToolDefinition> _batch6AttachmentTools() => [
      _jiraTool(
        name: 'jira_get_attachments',
        description: 'Get all attachments for a Jira ticket',
        params: [_keyParam],
      ),
    ];

/// Worklog read tool: `jira_get_worklogs`.
List<ToolDefinition> _batch6WorklogTools() => [
      _jiraTool(
        name: 'jira_get_worklogs',
        description: 'Get all worklogs for a Jira ticket',
        params: [_keyParam],
      ),
    ];

/// Watcher tools: list, add, and remove.
List<ToolDefinition> _batch6WatcherTools() => [
      _jiraTool(
        name: 'jira_get_watchers',
        description: 'Get all watchers for a Jira ticket',
        category: 'user_management',
        params: [_keyParam],
      ),
      _jiraTool(
        name: 'jira_add_watcher',
        description: 'Add a watcher to a Jira ticket',
        category: 'user_management',
        params: [
          _keyParam,
          ToolParam(
            name: 'accountId',
            description: 'The Atlassian account ID of the watcher to add',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_remove_watcher',
        description: 'Remove a watcher from a Jira ticket',
        category: 'user_management',
        params: [
          _keyParam,
          ToolParam(
            name: 'accountId',
            description: 'The Atlassian account ID of the watcher to remove',
            required: true,
          ),
        ],
      ),
    ];

/// Resolution listing tool: `jira_get_resolutions`.
List<ToolDefinition> _batch6ResolutionTools() => [
      _jiraTool(
        name: 'jira_get_resolutions',
        description: 'Get all available Jira issue resolutions',
        category: 'project_management',
      ),
    ];

/// Batch-6 dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraToolExecutorBatch6 on JiraToolExecutor {
  /// Routes the batch-6 Jira tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      batch6Handlers() => {
            'jira_search_by_page': (a) => _client.searchByPage(
                  a['jql'] as String,
                  a['nextPageToken'] as String?,
                  _optionalStringList(a, 'fields'),
                ),
            'jira_search_with_pagination': (a) => _client.searchWithPagination(
                  a['jql'] as String,
                  (a['startAt'] as num?)?.toInt() ?? 0,
                  _optionalStringList(a, 'fields'),
                ),
            'jira_get_attachments': (a) =>
                _client.getAttachments(a['key'] as String),
            'jira_get_worklogs': (a) => _client.getWorklogs(a['key'] as String),
            'jira_get_watchers': (a) => _client.getWatchers(a['key'] as String),
            'jira_add_watcher': (a) => _client.addWatcher(
                  a['key'] as String,
                  a['accountId'] as String,
                ),
            'jira_remove_watcher': (a) => _client.removeWatcher(
                  a['key'] as String,
                  a['accountId'] as String,
                ),
            'jira_get_resolutions': (_) => _client.getResolutions(),
          };
}
