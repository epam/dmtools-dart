/// PR state/mutation tools — part of the GitHub MCP tool catalog.
///
/// Ports the pull-request lifecycle `@MCPTool` definitions (merge, close,
/// reopen, diff stats, changed files). Parameter names mirror the Java
/// `GitHub.java` `@MCPParam` annotations.
part of 'github_tools.dart';

/// PR state/mutation tools: merge, close, reopen, diff, files.
List<ToolDefinition> _prStateTools() => [
      _prMergeTool(),
      ..._prLifecycleTools(),
    ];

/// Merge tool: `github_merge_pr`.
ToolDefinition _prMergeTool() => ToolDefinition(
      name: 'github_merge_pr',
      description: 'Merge a GitHub pull request. Supports merge, squash, and '
          'rebase merge methods.',
      integration: 'github',
      category: 'pull_requests',
      aliases: ['source_code_merge_pr'],
      params: [
        _workspaceParam(),
        _repositoryParam(),
        _prIdParam(),
        ToolParam(
          name: 'mergeMethod',
          description:
              "The merge method: 'merge' (default), 'squash', or 'rebase'",
          required: false,
        ),
        ToolParam(
          name: 'commitTitle',
          description:
              'Title for the merge commit (optional, defaults to PR title)',
          required: false,
        ),
        ToolParam(
          name: 'commitMessage',
          description: 'Extra detail to append to the merge commit message '
              '(optional)',
          required: false,
        ),
      ],
    );

/// Lifecycle tools: close, reopen, diff stats, changed files.
List<ToolDefinition> _prLifecycleTools() => [
      ToolDefinition(
        name: 'github_close_pr',
        description: 'Close a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
        ],
      ),
      ToolDefinition(
        name: 'github_reopen_pr',
        description: 'Reopen a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
        ],
      ),
      ToolDefinition(
        name: 'github_get_pr_diff',
        description: 'Get the diff statistics for a GitHub pull request (files '
            'changed, additions, deletions). Requires IS_READ_PULL_REQUEST_'
            'DIFF env/config to be enabled.',
        integration: 'github',
        category: 'pull_requests',
        aliases: ['source_code_get_pr_diff'],
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(name: 'pullRequestID'),
        ],
      ),
      ToolDefinition(
        name: 'github_get_pr_files',
        description: 'List the files changed in a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
        ],
      ),
    ];
