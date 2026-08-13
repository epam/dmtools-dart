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
      ..._commentTools(),
      ..._issueTools(),
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

/// Issue tool: `github_get_issue`.
List<ToolDefinition> _issueTools() => [
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
  };
}
