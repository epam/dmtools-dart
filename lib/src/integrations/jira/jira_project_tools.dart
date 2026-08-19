/// Project tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Project detail tools: project info + statuses.
List<ToolDefinition> _projectDetailTools() => [
      _jiraTool(
        name: 'jira_get_project_details',
        description: 'Get details for a Jira project by key',
        category: 'project_management',
        params: [
          ToolParam(
            name: 'projectKey',
            description: 'The project key (e.g. PROJ)',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_get_project_statuses',
        description: 'Get all statuses for issue types in a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
    ];

/// Project lifecycle tools: clone and delete.
List<ToolDefinition> _projectLifecycleTools() => [
      _jiraTool(
        name: 'jira_clone_project',
        description: 'Clone a Jira project including structure and workflow',
        category: 'project_management',
        params: [
          ToolParam(
              name: 'source',
              description: 'The source project key',
              required: true),
          ToolParam(
              name: 'target',
              description: 'The new project key',
              required: true),
          ToolParam(
              name: 'targetName',
              description: 'The name for the new project',
              required: true),
          ToolParam(
              name: 'lead',
              description: 'The account ID of the project lead',
              required: false),
        ],
      ),
      _jiraTool(
        name: 'jira_delete_project',
        description: 'Delete a Jira project (requires confirmation)',
        category: 'project_management',
        params: [
          ToolParam(
              name: 'key',
              description: 'The project key to delete',
              required: true),
          ToolParam(
              name: 'confirmDelete',
              description: 'Must be true to confirm the deletion',
              type: 'boolean',
              required: true),
        ],
      ),
    ];

/// Project structure copy tool: `jira_copy_project_structure`.
List<ToolDefinition> _projectStructureTools() => [
      _jiraTool(
        name: 'jira_copy_project_structure',
        description: 'Copy components and versions between Jira projects',
        category: 'project_management',
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

/// Project dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraProjectToolExecutor on JiraToolExecutor {
  /// Routes the project tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _projectHandlers() => {
            'jira_get_project_details': (a) =>
                _client.getProjectDetails(a['projectKey'] as String),
            'jira_get_project_statuses': (a) =>
                _client.getProjectStatuses(a['project'] as String),
            'jira_clone_project': (a) => _client.cloneProject(
                  a['source'] as String,
                  a['target'] as String,
                  a['targetName'] as String,
                  a['lead'] as String?,
                ),
            'jira_delete_project': (a) => _client.deleteProject(
                  a['key'] as String,
                  a['confirmDelete'] as bool,
                ),
            'jira_copy_project_structure': (a) => _client.copyProjectStructure(
                  a['source'] as String,
                  a['target'] as String,
                ),
          };
}
