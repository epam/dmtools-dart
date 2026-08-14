/// Repository tool definitions — part of the GitHub MCP tool catalog.
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
