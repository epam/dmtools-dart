/// Worklog extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Worklog methods on [JiraClient]: reading a ticket's worklog entries.
extension JiraWorklogClient on JiraClient {
  /// `jira_get_worklogs` — GET `issue/{key}/worklog`.
  ///
  /// Returns the `worklogs` array; an empty list when absent.
  Future<List<Map<String, dynamic>>> getWorklogs(String key) async {
    final body = await _http.get('issue/$key/worklog');
    return _extractArray(body, 'worklogs');
  }
}
