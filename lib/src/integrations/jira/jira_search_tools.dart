/// Page-level search tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Page-level search tools: cursor page + offset page (deprecated).
List<ToolDefinition> _searchPageTools() => [
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

/// Search dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraSearchToolExecutor on JiraToolExecutor {
  /// Routes the page-level search tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _searchPageHandlers() => {
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
          };
}
