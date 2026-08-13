/// Batch-5 Jira tool definitions — split from [jira_tools] for file-size.
part of 'jira_tools.dart';

/// Project detail tools: project info + statuses (moved for file-size).
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

/// Returns all batch-5 Jira tool definitions.
List<ToolDefinition> _batch5Tools() => [
      ..._batch5TransitionTools(),
      ..._batch5UserTools(),
      ..._batch5AttachmentTools(),
      ..._batch5CloneDeleteTools(),
      ..._batch5WorkflowTools(),
      ..._batch5SchemeTools(),
      ..._batch5IssueTypeTools(),
      ..._batch5FixVersionTools(),
      ..._batch5ProfileTools(),
    ];

/// Transition-with-resolution tool: `jira_move_to_status_with_resolution`.
List<ToolDefinition> _batch5TransitionTools() => [
      _jiraTool(
        name: 'jira_move_to_status_with_resolution',
        description: 'Transition a Jira ticket to a status with a resolution',
        category: 'workflow',
        params: [
          _keyParam,
          ToolParam(
            name: 'status',
            description: 'The target status or transition name',
            required: true,
          ),
          ToolParam(
            name: 'resolution',
            description: 'The resolution name to set during the transition',
            required: true,
          ),
        ],
      ),
    ];

/// User/profile tools: account lookup, profile fetch.
List<ToolDefinition> _batch5UserTools() => [
      _jiraTool(
        name: 'jira_get_account_by_email',
        description: 'Find a Jira user account by email address',
        category: 'user_management',
        params: [
          ToolParam(
            name: 'email',
            description: 'The email address to search for',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_get_user_profile',
        description: 'Get a Jira user profile by account ID',
        category: 'user_management',
        params: [
          ToolParam(
            name: 'userId',
            description: 'The Atlassian account ID of the user',
            required: true,
          ),
        ],
      ),
    ];

/// Attachment tools: file upload and binary download.
List<ToolDefinition> _batch5AttachmentTools() => [
      _jiraTool(
        name: 'jira_attach_file_to_ticket',
        description: 'Attach a file to a Jira ticket via multipart upload',
        params: [
          _keyParam,
          ToolParam(
            name: 'fileName',
            description: 'The name to give the attached file',
            required: true,
          ),
          ToolParam(
            name: 'filePath',
            description: 'The local file path to upload',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_download_attachment',
        description: 'Download a Jira attachment to a local file',
        category: 'system',
        params: [
          ToolParam(
            name: 'url',
            description: 'The full attachment download URL',
            required: true,
          ),
          ToolParam(
            name: 'filePath',
            description: 'The local file path to save to',
            required: true,
          ),
        ],
      ),
    ];

/// Project clone and delete tools.
List<ToolDefinition> _batch5CloneDeleteTools() => [
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

/// Workflow, structure copy, and board config tools.
List<ToolDefinition> _batch5WorkflowTools() => [
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
      _jiraTool(
        name: 'jira_get_project_board_config',
        description: 'Get the Agile board configuration for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
    ];

/// Issue-type and workflow scheme get/assign tools.
List<ToolDefinition> _batch5SchemeTools() => [
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

/// Issue-type creation tool: `jira_create_project_issue_type`.
List<ToolDefinition> _batch5IssueTypeTools() => [
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

/// Fix-version mutation tools: append and remove.
List<ToolDefinition> _batch5FixVersionTools() => [
      _jiraTool(
        name: 'jira_add_fix_version',
        description: 'Append a fix version to a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
              name: 'version',
              description: 'The fix version name to add',
              required: true),
        ],
      ),
      _jiraTool(
        name: 'jira_remove_fix_version',
        description: 'Remove a fix version from a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
              name: 'version',
              description: 'The fix version name to remove',
              required: true),
        ],
      ),
    ];

/// Current-user profile tool: `jira_get_my_profile`.
List<ToolDefinition> _batch5ProfileTools() => [
      _jiraTool(
        name: 'jira_get_my_profile',
        description: 'Get the current Jira user profile',
        category: 'user_management',
      ),
    ];
