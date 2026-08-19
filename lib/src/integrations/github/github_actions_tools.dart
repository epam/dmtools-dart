/// Actions tool definitions — part of the GitHub MCP tool catalog.
part of 'github_tools.dart';

/// Actions tools: `github_get_workflow_runs`, `github_rerun_workflow`,
/// `github_get_check_runs`.
List<ToolDefinition> _actionsTools() => [
      ToolDefinition(
        name: 'github_get_workflow_runs',
        description: 'List GitHub Actions workflow runs for a repository',
        integration: 'github',
        category: 'actions',
        params: [_ownerParam(), _repoParam()],
      ),
      ToolDefinition(
        name: 'github_rerun_workflow',
        description: 'Re-run a GitHub Actions workflow run by id',
        integration: 'github',
        category: 'actions',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'run_id',
            description: 'The workflow run id to re-run',
            type: 'number',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_check_runs',
        description: 'List check runs for a GitHub commit ref',
        integration: 'github',
        category: 'actions',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'ref',
            description:
                'The branch, tag, or commit SHA to list check runs for',
            required: true,
          ),
        ],
      ),
    ];
