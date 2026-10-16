/// PR-update tool definitions — part of the GitHub MCP tool catalog.
part of 'github_tools.dart';

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
