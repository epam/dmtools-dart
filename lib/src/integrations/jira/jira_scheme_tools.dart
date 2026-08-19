/// Scheme tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Issue-type and workflow scheme get/assign tools.
List<ToolDefinition> _schemeTools() => [
      _jiraTool(
        name: 'jira_get_project_issue_type_scheme',
        description: 'Get the issue-type scheme for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
      _jiraTool(
        name: 'jira_assign_issue_type_scheme',
        description: 'Assign an issue-type scheme to a Jira project',
        category: 'project_management',
        params: [
          ToolParam(
              name: 'projectId',
              description: 'The project ID or key',
              required: true),
          ToolParam(
              name: 'schemeId',
              description: 'The issue-type scheme ID',
              required: true),
        ],
      ),
      _jiraTool(
        name: 'jira_get_project_workflow_scheme',
        description: 'Get the workflow scheme for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
      _jiraTool(
        name: 'jira_assign_workflow_scheme',
        description: 'Assign a workflow scheme to a Jira project',
        category: 'project_management',
        params: [
          ToolParam(
              name: 'projectId',
              description: 'The project ID or key',
              required: true),
          ToolParam(
              name: 'schemeId',
              description: 'The workflow scheme ID',
              required: true),
        ],
      ),
    ];

/// Scheme dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraSchemeToolExecutor on JiraToolExecutor {
  /// Routes the scheme tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _schemeHandlers() => {
            'jira_get_project_issue_type_scheme': (a) =>
                _client.getProjectIssueTypeScheme(a['project'] as String),
            'jira_assign_issue_type_scheme': (a) =>
                _client.assignIssueTypeScheme(
                  a['projectId'] as String,
                  a['schemeId'] as String,
                ),
            'jira_get_project_workflow_scheme': (a) =>
                _client.getProjectWorkflowScheme(a['project'] as String),
            'jira_assign_workflow_scheme': (a) => _client.assignWorkflowScheme(
                  a['projectId'] as String,
                  a['schemeId'] as String,
                ),
          };
}
