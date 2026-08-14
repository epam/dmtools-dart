/// Workflow-catalog tool definitions — part of the GitHub MCP tool catalog.
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
