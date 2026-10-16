/// Worklog tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Worklog read tool: `jira_get_worklogs`.
List<ToolDefinition> _worklogTools() => [
      _jiraTool(
        name: 'jira_get_worklogs',
        description: 'Get all worklogs for a Jira ticket',
        params: [_keyParam],
      ),
    ];

/// Worklog dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraWorklogToolExecutor on JiraToolExecutor {
  /// Routes the worklog tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _worklogHandlers() => {
            'jira_get_worklogs': (a) => _client.getWorklogs(a['key'] as String),
          };
}
