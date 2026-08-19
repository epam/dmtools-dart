/// Workflow-transition tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Transition-with-resolution tool: `jira_move_to_status_with_resolution`.
List<ToolDefinition> _transitionTools() => [
      _jiraTool(
        name: 'jira_move_to_status_with_resolution',
        description: 'Transition a Jira ticket to a status with a resolution',
        category: 'workflow',
        params: [
          _keyParam,
          ToolParam(
            name: 'status',
            description: 'The target status or transition name',
            required: true,
          ),
          ToolParam(
            name: 'resolution',
            description: 'The resolution name to set during the transition',
            required: true,
          ),
        ],
      ),
    ];

/// Transition dispatch entries, provided via a library-private extension so
/// the main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraTransitionToolExecutor on JiraToolExecutor {
  /// Routes the transition tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _transitionHandlers() => {
            'jira_move_to_status_with_resolution': (a) =>
                _client.moveToStatusWithResolution(
                  a['key'] as String,
                  a['status'] as String,
                  a['resolution'] as String,
                ),
          };
}
