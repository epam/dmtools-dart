/// Batch-7 Jira tool definitions and dispatch — split for file-size.
part of 'jira_tools.dart';

/// Returns all batch-7 Jira tool definitions.
List<ToolDefinition> _batch7Tools() => [
      ..._batch7MetadataTools(),
      ..._batch7ExportTools(),
      ..._batch7AgileTools(),
    ];

/// Metadata listing tools: priorities and security levels.
List<ToolDefinition> _batch7MetadataTools() => [
      _jiraTool(
        name: 'jira_get_priorities',
        description: 'Get all available Jira issue priorities',
        category: 'project_management',
      ),
      _jiraTool(
        name: 'jira_get_security_levels',
        description: 'Get all available Jira issue security levels',
        category: 'project_management',
      ),
    ];

/// Generic data-export tool: `jira_export_data`.
List<ToolDefinition> _batch7ExportTools() => [
      _jiraTool(
        name: 'jira_export_data',
        description: 'Export all Jira issue data matching a JQL query',
        category: 'search',
        params: _jqlSearchParams,
      ),
    ];

/// Agile board tools: board issues and sprints.
List<ToolDefinition> _batch7AgileTools() => [
      _jiraTool(
        name: 'jira_get_board_issues',
        description: 'Get all issues on a Jira Agile board by board ID',
        category: 'project_management',
        params: [
          ToolParam(
            name: 'boardId',
            description: 'The Agile board ID',
            type: 'integer',
            required: true,
          ),
          ToolParam(
            name: 'jql',
            description: 'Optional JQL to filter board issues',
            required: false,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_get_sprints',
        description: 'Get all sprints for a Jira Agile board by board ID',
        category: 'project_management',
        params: [
          ToolParam(
            name: 'boardId',
            description: 'The Agile board ID',
            type: 'integer',
            required: true,
          ),
        ],
      ),
    ];

/// Batch-7 dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraToolExecutorBatch7 on JiraToolExecutor {
  /// Routes the batch-7 Jira tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      batch7Handlers() => {
            'jira_get_priorities': (_) => _client.getPriorities(),
            'jira_get_security_levels': (_) => _client.getSecurityLevels(),
            'jira_export_data': (a) => _client.exportData(
                  a['jql'] as String,
                  _optionalStringList(a, 'fields'),
                ),
            'jira_get_board_issues': (a) => _client.getBoardIssues(
                  (a['boardId'] as num).toInt(),
                  a['jql'] as String?,
                ),
            'jira_get_sprints': (a) => _client.getSprints(
                  (a['boardId'] as num).toInt(),
                ),
          };
}
