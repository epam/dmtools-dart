/// MCP tool definitions and dispatcher for the GitHub integration.
///
/// The tool list ports the GitHub subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [GithubClient] call.
library;

import '../../mcp/tool_args.dart';
import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'github_client.dart';

/// Returns all GitHub MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> githubTools() => [
      ..._systemTools(),
      ..._pullRequestTools(),
      ..._prStateTools(),
      ..._reviewTools(),
      ..._commentTools(),
      ..._issueTools(),
      ..._branchTools(),
      ..._fileTools(),
      ..._releaseTools(),
      ..._commitTools(),
    ];

/// Connectivity-check tool: `github_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'github_test',
        description: 'Test GitHub connectivity by fetching the current user',
        integration: 'github',
        category: 'system',
        params: [],
      ),
    ];

/// Pull-request tools: `github_get_pr`, `github_list_prs`, `github_create_pr`.
List<ToolDefinition> _pullRequestTools() => [
      ToolDefinition(
        name: 'github_get_pr',
        description: 'Get a GitHub pull request by number',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
        ],
      ),
      ToolDefinition(
        name: 'github_list_prs',
        description: 'List GitHub pull requests on a repository',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'state',
            description: 'PR state filter: open, closed, or all',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_create_pr',
        description: 'Create a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'title',
            description: 'The title of the new pull request',
            required: true,
          ),
          ToolParam(
            name: 'head',
            description: 'The branch containing changes (source)',
            required: true,
          ),
          ToolParam(
            name: 'base',
            description: 'The branch to merge changes into (target)',
            required: true,
          ),
        ],
      ),
    ];

/// Comment tool: `github_create_comment`.
List<ToolDefinition> _commentTools() => [
      ToolDefinition(
        name: 'github_create_comment',
        description: 'Create a comment on a GitHub pull request',
        integration: 'github',
        category: 'comments',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
          ToolParam(
            name: 'body',
            description: 'The comment body text',
            required: true,
          ),
        ],
      ),
    ];

/// Issue tools: get, create, close, add labels, remove label.
List<ToolDefinition> _issueTools() => [
      ..._issueReadTools(),
      ..._issueMutationTools(),
    ];

/// Issue read/create tools: `github_get_issue`, `github_create_issue`.
List<ToolDefinition> _issueReadTools() => [
      ToolDefinition(
        name: 'github_get_issue',
        description: 'Get a GitHub issue by number',
        integration: 'github',
        category: 'issues',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The issue number'),
        ],
      ),
      ToolDefinition(
        name: 'github_create_issue',
        description: 'Create a GitHub issue',
        integration: 'github',
        category: 'issues',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'title',
            description: 'The title of the new issue',
            required: true,
          ),
          ToolParam(
            name: 'body',
            description: 'The issue description (markdown)',
            required: false,
          ),
        ],
      ),
    ];

/// Issue mutation tools: close, add labels, remove label.
List<ToolDefinition> _issueMutationTools() => [
      ToolDefinition(
        name: 'github_close_issue',
        description: 'Close a GitHub issue',
        integration: 'github',
        category: 'issues',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The issue number'),
        ],
      ),
      ToolDefinition(
        name: 'github_add_labels',
        description: 'Add labels to a GitHub issue',
        integration: 'github',
        category: 'issues',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The issue number'),
          ToolParam(
            name: 'labels',
            description: 'The label names to add',
            type: 'array',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_remove_label',
        description: 'Remove a label from a GitHub issue',
        integration: 'github',
        category: 'issues',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The issue number'),
          ToolParam(
            name: 'label',
            description: 'The name of the label to remove',
            required: true,
          ),
        ],
      ),
    ];

/// PR state/mutation tools: merge, close, reopen, diff, files.
List<ToolDefinition> _prStateTools() => [
      ToolDefinition(
        name: 'github_merge_pr',
        description: 'Merge a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
        ],
      ),
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
        description: 'Get the raw diff of a GitHub pull request',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
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

/// Review tool: `github_create_review`.
List<ToolDefinition> _reviewTools() => [
      ToolDefinition(
        name: 'github_create_review',
        description: 'Create a review on a GitHub pull request',
        integration: 'github',
        category: 'reviews',
        params: [
          _ownerParam(),
          _repoParam(),
          _numberParam('The pull request number'),
          ToolParam(
            name: 'body',
            description: 'The review body text',
            required: true,
          ),
          ToolParam(
            name: 'event',
            description: 'Review event: APPROVE, REQUEST_CHANGES, or COMMENT',
            required: true,
          ),
        ],
      ),
    ];

/// Branch tools: `github_list_branches`, `github_create_branch`,
/// `github_delete_branch`.
List<ToolDefinition> _branchTools() => [
      ToolDefinition(
        name: 'github_list_branches',
        description: 'List branches in a GitHub repository',
        integration: 'github',
        category: 'branches',
        params: [
          _ownerParam(),
          _repoParam(),
        ],
      ),
      ToolDefinition(
        name: 'github_create_branch',
        description: 'Create a new branch from an existing commit SHA',
        integration: 'github',
        category: 'branches',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'branch',
            description: 'The name of the new branch',
            required: true,
          ),
          ToolParam(
            name: 'from_sha',
            description: 'The commit SHA to branch from',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_delete_branch',
        description: 'Delete a branch in a GitHub repository',
        integration: 'github',
        category: 'branches',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'branch',
            description: 'The name of the branch to delete',
            required: true,
          ),
        ],
      ),
    ];

/// File-content tools: `github_get_file_content`, `github_update_file`.
List<ToolDefinition> _fileTools() => [
      ToolDefinition(
        name: 'github_get_file_content',
        description: 'Get the contents of a file in a GitHub repository',
        integration: 'github',
        category: 'files',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'path',
            description: 'The file path within the repository',
            required: true,
          ),
          ToolParam(
            name: 'ref',
            description:
                'Branch, tag, or commit SHA (defaults to default branch)',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_update_file',
        description: 'Create or update a file in a GitHub repository',
        integration: 'github',
        category: 'files',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'path',
            description: 'The file path within the repository',
            required: true,
          ),
          ToolParam(
            name: 'content',
            description: 'The new file content (plain text)',
            required: true,
          ),
          ToolParam(
            name: 'message',
            description: 'The commit message',
            required: true,
          ),
          ToolParam(
            name: 'sha',
            description:
                'The blob SHA of the existing file (required to update)',
            required: true,
          ),
        ],
      ),
    ];

/// Release tools: `github_list_releases`, `github_get_release`,
/// `github_create_release`.
List<ToolDefinition> _releaseTools() => [
      ToolDefinition(
        name: 'github_list_releases',
        description: 'List GitHub releases for a repository',
        integration: 'github',
        category: 'releases',
        params: [
          _ownerParam(),
          _repoParam(),
        ],
      ),
      ToolDefinition(
        name: 'github_get_release',
        description: 'Get a GitHub release by tag name',
        integration: 'github',
        category: 'releases',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'tag',
            description: 'The tag name of the release',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_create_release',
        description: 'Create a GitHub release for a tag',
        integration: 'github',
        category: 'releases',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'tag_name',
            description: 'The name of the tag the release targets',
            required: true,
          ),
          ToolParam(
            name: 'body',
            description: 'The release description (markdown)',
            required: false,
          ),
        ],
      ),
    ];

/// Commit tools: `github_get_commit`, `github_list_commits`.
List<ToolDefinition> _commitTools() => [
      ToolDefinition(
        name: 'github_get_commit',
        description: 'Get a GitHub commit by SHA',
        integration: 'github',
        category: 'commits',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'sha',
            description: 'The commit SHA (or ref) to fetch',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_list_commits',
        description: 'List commits in a GitHub repository',
        integration: 'github',
        category: 'commits',
        params: [
          _ownerParam(),
          _repoParam(),
          ToolParam(
            name: 'sha',
            description:
                'Branch or commit SHA to list from (defaults to default branch)',
            required: false,
          ),
        ],
      ),
    ];

/// Shared `owner` parameter (repository owner / org).
ToolParam _ownerParam() => ToolParam(
      name: 'owner',
      description: 'The repository owner (user or organization)',
      required: true,
    );

/// Shared `repo` parameter (repository name).
ToolParam _repoParam() => ToolParam(
      name: 'repo',
      description: 'The repository name',
      required: true,
    );

/// Shared numeric `number` parameter with a tool-specific [description].
ToolParam _numberParam(String description) => ToolParam(
      name: 'number',
      description: description,
      type: 'number',
      required: true,
    );

/// Executes GitHub MCP tools by dispatching to [GithubClient].
class GithubToolExecutor {
  final GithubClient _client;

  /// Creates an executor bound to [_client].
  GithubToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown GitHub tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown GitHub tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'github_test': (_) => _client.testConnection(),
    'github_get_pr': (a) => _client.getPr(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_list_prs': (a) => _client.listPrs(
          a['owner'] as String,
          a['repo'] as String,
          a['state'] as String?,
        ),
    'github_create_comment': (a) => _client.createComment(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
          a['body'] as String,
        ),
    'github_get_issue': (a) => _client.getIssue(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_create_pr': (a) => _client.createPr(
          a['owner'] as String,
          a['repo'] as String,
          a['title'] as String,
          a['head'] as String,
          a['base'] as String,
        ),
    'github_merge_pr': (a) => _client.mergePr(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_close_pr': (a) => _client.closePr(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_reopen_pr': (a) => _client.reopenPr(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_get_pr_diff': (a) => _client.getPrDiff(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_get_pr_files': (a) => _client.getPrFiles(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_create_review': (a) => _client.createReview(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
          a['body'] as String,
          a['event'] as String,
        ),
    'github_list_branches': (a) => _client.listBranches(
          a['owner'] as String,
          a['repo'] as String,
        ),
    'github_create_branch': (a) => _client.createBranch(
          a['owner'] as String,
          a['repo'] as String,
          a['branch'] as String,
          a['from_sha'] as String,
        ),
    'github_get_file_content': (a) => _client.getFileContent(
          a['owner'] as String,
          a['repo'] as String,
          a['path'] as String,
          a['ref'] as String?,
        ),
    'github_update_file': (a) => _client.updateFile(
          a['owner'] as String,
          a['repo'] as String,
          a['path'] as String,
          a['content'] as String,
          a['message'] as String,
          a['sha'] as String,
        ),
    'github_create_issue': (a) => _client.createIssue(
          a['owner'] as String,
          a['repo'] as String,
          a['title'] as String,
          a['body'] as String?,
        ),
    'github_close_issue': (a) => _client.closeIssue(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
        ),
    'github_add_labels': (a) => _client.addLabels(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
          (a['labels'] as List).cast<String>(),
        ),
    'github_remove_label': (a) => _client.removeLabel(
          a['owner'] as String,
          a['repo'] as String,
          requiredInt(a, 'number'),
          a['label'] as String,
        ),
    'github_delete_branch': (a) => _client.deleteBranch(
          a['owner'] as String,
          a['repo'] as String,
          a['branch'] as String,
        ),
    'github_list_releases': (a) => _client.listReleases(
          a['owner'] as String,
          a['repo'] as String,
        ),
    'github_get_release': (a) => _client.getRelease(
          a['owner'] as String,
          a['repo'] as String,
          a['tag'] as String,
        ),
    'github_create_release': (a) => _client.createRelease(
          a['owner'] as String,
          a['repo'] as String,
          a['tag_name'] as String,
          a['body'] as String?,
        ),
    'github_get_commit': (a) => _client.getCommit(
          a['owner'] as String,
          a['repo'] as String,
          a['sha'] as String,
        ),
    'github_list_commits': (a) => _client.listCommits(
          a['owner'] as String,
          a['repo'] as String,
          a['sha'] as String?,
        ),
  };
}
