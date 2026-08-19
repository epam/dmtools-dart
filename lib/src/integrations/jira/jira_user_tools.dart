/// User and profile tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// User lookup tools: account by email + profile by account ID.
List<ToolDefinition> _userTools() => [
      _jiraTool(
        name: 'jira_get_account_by_email',
        description: 'Find a Jira user account by email address',
        category: 'user_management',
        params: [
          ToolParam(
            name: 'email',
            description: 'The email address to search for',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_get_user_profile',
        description: 'Get a Jira user profile by account ID',
        category: 'user_management',
        params: [
          ToolParam(
            name: 'userId',
            description: 'The Atlassian account ID of the user',
            required: true,
          ),
        ],
      ),
    ];

/// Current-user profile tool: `jira_get_my_profile`.
List<ToolDefinition> _myProfileTools() => [
      _jiraTool(
        name: 'jira_get_my_profile',
        description: 'Get the current Jira user profile',
        category: 'user_management',
      ),
    ];

/// User dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraUserToolExecutor on JiraToolExecutor {
  /// Routes the user tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)> _userHandlers() =>
      {
        'jira_get_account_by_email': (a) => _client.getAccountByEmail(
              a['email'] as String,
            ),
        'jira_get_user_profile': (a) => _client.getUserProfile(
              a['userId'] as String,
            ),
        'jira_get_my_profile': (_) => _client.getMyProfile(),
      };
}
