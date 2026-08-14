/// Workflow tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Project workflow tools: create and sync workflow schemes.
List<ToolDefinition> _workflowTools() => [
      _jiraTool(
        name: 'jira_setup_project_workflow',
        description: 'Create a workflow scoped to a project',
        category: 'workflow',
        params: [
          ToolParam(
              name: 'target',
              description: 'The target project key',
              required: true),
          ToolParam(
              name: 'statusesJson',
              description: 'The workflow statuses and transitions definition',
              type: 'object',
              required: true),
        ],
      ),
      _jiraTool(
        name: 'jira_sync_project_workflow',
        description: 'Sync the workflow scheme from one project to another',
        category: 'workflow',
        params: [
          ToolParam(
              name: 'source',
              description: 'The source project key',
              required: true),
          ToolParam(
              name: 'target',
              description: 'The target project key',
              required: true),
        ],
      ),
    ];

/// Workflow dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraWorkflowToolExecutor on JiraToolExecutor {
  /// Routes the workflow tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _workflowHandlers() => {
            'jira_setup_project_workflow': (a) => _client.setupProjectWorkflow(
                  a['target'] as String,
                  a['statusesJson'] as Map<String, dynamic>,
                ),
            'jira_sync_project_workflow': (a) => _client.syncProjectWorkflow(
                  a['source'] as String,
                  a['target'] as String,
                ),
          };
}
