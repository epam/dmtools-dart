/// Fix-version tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Fix-version mutation tools: append and remove.
List<ToolDefinition> _fixVersionTools() => [
      _jiraTool(
        name: 'jira_add_fix_version',
        description: 'Append a fix version to a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
              name: 'version',
              description: 'The fix version name to add',
              required: true),
        ],
      ),
      _jiraTool(
        name: 'jira_remove_fix_version',
        description: 'Remove a fix version from a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
              name: 'version',
              description: 'The fix version name to remove',
              required: true),
        ],
      ),
    ];

/// Fix-version dispatch entries, provided via a library-private extension so
/// the main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraFixVersionToolExecutor on JiraToolExecutor {
  /// Routes the fix-version tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _fixVersionHandlers() => {
            'jira_add_fix_version': (a) => _client.addFixVersion(
                  a['key'] as String,
                  a['version'] as String,
                ),
            'jira_remove_fix_version': (a) => _client.removeFixVersion(
                  a['key'] as String,
                  a['version'] as String,
                ),
          };
}
