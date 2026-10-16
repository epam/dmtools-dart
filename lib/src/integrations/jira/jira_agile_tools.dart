/// Agile board tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Agile board-config tool: `jira_get_project_board_config`.
List<ToolDefinition> _boardConfigTools() => [
      _jiraTool(
        name: 'jira_get_project_board_config',
        description: 'Get the Agile board configuration for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
    ];

/// Agile board tools: board issues and sprints.
List<ToolDefinition> _agileTools() => [
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

/// Agile dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraAgileToolExecutor on JiraToolExecutor {
  /// Routes the Agile tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _agileHandlers() => {
            'jira_get_project_board_config': (a) =>
                _client.getProjectBoardConfig(a['project'] as String),
            'jira_get_board_issues': (a) => _client.getBoardIssues(
                  (a['boardId'] as num).toInt(),
                  a['jql'] as String?,
                ),
            'jira_get_sprints': (a) => _client.getSprints(
                  (a['boardId'] as num).toInt(),
                ),
          };
}
