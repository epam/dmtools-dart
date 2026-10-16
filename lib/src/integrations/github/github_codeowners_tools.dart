/// CODEOWNERS tool definitions — part of the GitHub MCP tool catalog.
part of 'github_tools.dart';

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
