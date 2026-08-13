/// Batch-4 GitHub tool definitions — split from `github_tools.dart` for
/// file-size. Contains repository, PR-update, and Actions catalog functions.
part of 'github_tools.dart';

/// Repository tools: `github_get_repo`, `github_get_tree`.
List<ToolDefinition> _repositoryTools() => [
      ToolDefinition(
        name: 'github_get_repo',
        description: 'Get a GitHub repository by owner and name',
        integration: 'github',
        category: 'repositories',
        params: [_ownerParam(), _repoParam()],
      ),
      ToolDefinition(
        name: 'github_get_tree',
        description: 'Get a GitHub git tree recursively by ref',
        integration: 'github',
        category: 'files',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'ref',
            description: 'Branch, tag, or commit SHA to read the tree from',
            required: true,
          ),
        ],
      ),
    ];

/// PR mutation tools: `github_update_pr`, `github_request_reviewers`.
List<ToolDefinition> _prUpdateTools() => [
      ToolDefinition(
        name: 'github_update_pr',
        description: 'Update the title or body of a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
          ToolParam(
            name: 'title',
            description: 'The new title (omitted to leave unchanged)',
            required: false,
          ),
          ToolParam(
            name: 'body',
            description: 'The new body (omitted to leave unchanged)',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_request_reviewers',
        description: 'Request reviewers on a GitHub pull request',
        integration: 'github',
        category: 'reviews',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
          ToolParam(
            name: 'reviewers',
            description: 'The reviewer logins to request',
            type: 'array',
            required: true,
          ),
        ],
      ),
    ];

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
