/// Watcher extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Watcher methods on [JiraClient]: listing, adding, and removing ticket
/// watchers.
extension JiraWatcherClient on JiraClient {
  /// `jira_get_watchers` — GET `issue/{key}/watchers`.
  ///
  /// Returns the `watchers` array; an empty list when absent.
  Future<List<Map<String, dynamic>>> getWatchers(String key) async {
    final body = await _http.get('issue/$key/watchers');
    return _extractArray(body, 'watchers');
  }

  /// `jira_add_watcher` — POST `issue/{key}/watchers`.
  ///
  /// Adds [accountId] as a watcher. The Jira API expects the body to be the
  /// account id encoded as a bare JSON string.
  Future<void> addWatcher(String key, String accountId) async {
    await _http.post('issue/$key/watchers', body: jsonEncode(accountId));
  }

  /// `jira_remove_watcher` — DELETE `issue/{key}/watchers?accountId=`.
  Future<void> removeWatcher(String key, String accountId) async {
    await _http.deleteWithQuery(
      'issue/$key/watchers',
      queryParams: {'accountId': accountId},
    );
  }
}
