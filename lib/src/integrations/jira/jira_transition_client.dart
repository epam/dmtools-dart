/// Workflow-transition extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Transition methods on [JiraClient], extending basic status moves with
/// resolution-setting transitions.
extension JiraTransitionClient on JiraClient {
  /// `jira_move_to_status_with_resolution` — POST `issue/{key}/transitions`.
  ///
  /// Like [JiraClient.moveToStatus] but includes a resolution in the
  /// transition body. Returns the POST response body, or an explanatory
  /// string when no matching transition exists.
  Future<String> moveToStatusWithResolution(
    String key,
    String statusName,
    String resolution,
  ) =>
      _transitionIssue(key, statusName, {
        'resolution': {'name': resolution}
      });
}
