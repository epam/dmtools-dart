/// Batch-5 GitHub tool definitions and handlers — split from
/// `github_tools.dart` for file-size. Contains workflow catalog, CODEOWNERS,
/// and collaborator functions.
part of 'github_tools.dart';

/// Workflow catalog tools: `github_get_workflows`, `github_enable_workflow`,
/// `github_disable_workflow`.
List<ToolDefinition> _workflowCatalogTools() => [
      ToolDefinition(
        name: 'github_get_workflows',
        description: 'List GitHub Actions workflows in a repository',
        integration: 'github',
        category: 'actions',
        params: [_ownerParam(), _repoParam()],
      ),
      ToolDefinition(
        name: 'github_enable_workflow',
        description: 'Enable a GitHub Actions workflow by id',
        integration: 'github',
        category: 'actions',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'workflow_id',
            description: 'The workflow id to enable',
            type: 'number',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_disable_workflow',
        description: 'Disable a GitHub Actions workflow by id',
        integration: 'github',
        category: 'actions',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'workflow_id',
            description: 'The workflow id to disable',
            type: 'number',
            required: true,
          ),
        ],
      ),
    ];

/// CODEOWNERS tool: `github_get_codeowners`.
List<ToolDefinition> _codeownersTools() => [
      ToolDefinition(
        name: 'github_get_codeowners',
        description: 'Get the CODEOWNERS file from a GitHub repository',
        integration: 'github',
        category: 'files',
        params: [_ownerParam(), _repoParam()],
      ),
    ];

/// Collaborator tools: `github_add_collaborator`,
/// `github_remove_collaborator`.
List<ToolDefinition> _collaboratorTools() => [
      ToolDefinition(
        name: 'github_add_collaborator',
        description: 'Add a collaborator to a GitHub repository',
        integration: 'github',
        category: 'collaborators',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'username',
            description: 'The collaborator login to add',
            required: true,
          ),
          ToolParam(
            name: 'permission',
            description: 'The permission level: push, pull, admin, maintain, '
                'or triage',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_remove_collaborator',
        description: 'Remove a collaborator from a GitHub repository',
        integration: 'github',
        category: 'collaborators',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'username',
            description: 'The collaborator login to remove',
            required: true,
          ),
        ],
      ),
    ];
