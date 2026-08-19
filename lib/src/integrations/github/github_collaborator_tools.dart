/// Collaborator tool definitions — part of the GitHub MCP tool catalog.
part of 'github_tools.dart';

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
