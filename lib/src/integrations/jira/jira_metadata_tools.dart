/// Issue-metadata tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Metadata listing tools: resolutions, priorities, and security levels.
List<ToolDefinition> _metadataTools() => [
      _jiraTool(
        name: 'jira_get_resolutions',
        description: 'Get all available Jira issue resolutions',
        category: 'project_management',
      ),
      _jiraTool(
        name: 'jira_get_priorities',
        description: 'Get all available Jira issue priorities',
        category: 'project_management',
      ),
      _jiraTool(
        name: 'jira_get_security_levels',
        description: 'Get all available Jira issue security levels',
        category: 'project_management',
      ),
    ];

/// Metadata dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraMetadataToolExecutor on JiraToolExecutor {
  /// Routes the metadata tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _metadataHandlers() => {
            'jira_get_resolutions': (_) => _client.getResolutions(),
            'jira_get_priorities': (_) => _client.getPriorities(),
            'jira_get_security_levels': (_) => _client.getSecurityLevels(),
          };
}
