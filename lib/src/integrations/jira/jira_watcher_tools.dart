/// Watcher tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Watcher tools: list, add, and remove.
List<ToolDefinition> _watcherTools() => [
      _jiraTool(
        name: 'jira_get_watchers',
        description: 'Get all watchers for a Jira ticket',
        category: 'user_management',
        params: [_keyParam],
      ),
      _jiraTool(
        name: 'jira_add_watcher',
        description: 'Add a watcher to a Jira ticket',
        category: 'user_management',
        params: [
          _keyParam,
          ToolParam(
            name: 'accountId',
            description: 'The Atlassian account ID of the watcher to add',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_remove_watcher',
        description: 'Remove a watcher from a Jira ticket',
        category: 'user_management',
        params: [
          _keyParam,
          ToolParam(
            name: 'accountId',
            description: 'The Atlassian account ID of the watcher to remove',
            required: true,
          ),
        ],
      ),
    ];

/// Watcher dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraWatcherToolExecutor on JiraToolExecutor {
  /// Routes the watcher tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _watcherHandlers() => {
            'jira_get_watchers': (a) => _client.getWatchers(a['key'] as String),
            'jira_add_watcher': (a) => _client.addWatcher(
                  a['key'] as String,
                  a['accountId'] as String,
                ),
            'jira_remove_watcher': (a) => _client.removeWatcher(
                  a['key'] as String,
                  a['accountId'] as String,
                ),
          };
}
