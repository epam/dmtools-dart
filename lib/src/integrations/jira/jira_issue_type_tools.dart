/// Issue-type tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Issue-type creation tool: `jira_create_project_issue_type`.
List<ToolDefinition> _issueTypeTools() => [
      _jiraTool(
        name: 'jira_create_project_issue_type',
        description: 'Create a new Jira issue type',
        category: 'project_management',
        params: [
          _projectParam,
          ToolParam(
              name: 'name', description: 'The issue type name', required: true),
          ToolParam(
              name: 'type',
              description: 'The issue type (e.g. standard, sub-task)',
              required: true),
          ToolParam(
              name: 'description',
              description: 'The issue type description',
              required: false),
        ],
      ),
    ];

/// Issue-type dispatch entries, provided via a library-private extension so
/// the main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraIssueTypeToolExecutor on JiraToolExecutor {
  /// Routes the issue-type tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _issueTypeHandlers() => {
            'jira_create_project_issue_type': (a) =>
                _client.createProjectIssueType(
                  a['project'] as String,
                  a['name'] as String,
                  a['type'] as String,
                  a['description'] as String?,
                ),
          };
}
