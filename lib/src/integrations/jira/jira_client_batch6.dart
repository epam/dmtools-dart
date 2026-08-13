/// Batch-6 Jira client methods — split from [JiraClient] for file-size.
part of 'jira_client.dart';

// ── Batch 6 extension on JiraClient ─────────────────────────────────────

/// Batch-6 extension methods on [JiraClient], adding page-level search
/// (Cloud cursor + Server/DC offset), attachments, worklogs, watchers, and
/// resolutions — the remaining methods needed for full Java parity.
extension JiraClientBatch6 on JiraClient {
  /// `jira_search_by_page` — GET `search/jql` returning a single cursor page.
  ///
  /// Fetches one Cloud cursor-paginated page; pass [nextPageToken] from a
  /// prior call to advance. The returned map mirrors the Jira response and
  /// includes `issues` plus, when more results exist, `nextPageToken`.
  Future<Map<String, dynamic>> searchByPage(
    String jql, [
    String? nextPageToken,
    List<String>? fields,
  ]) async {
    final params = <String, dynamic>{
      'jql': jql,
      'fields': _joinFields(fields),
    };
    if (nextPageToken != null) params['nextPageToken'] = nextPageToken;
    final body = await _http.get('search/jql', queryParams: params);
    return _decodeMap(body);
  }

  /// `jira_search_with_pagination` — GET `search` returning one offset page.
  ///
  /// Deprecated by Atlassian but kept for parity with the Java client.
  /// Returns the raw page map (`issues`, `total`, `startAt`, `maxResults`)
  /// for a single page starting at [startAt]; auto-pagination is intentionally
  /// not performed — callers wanting all issues should use [JiraClient.searchByJql].
  Future<Map<String, dynamic>> searchWithPagination(
    String jql, [
    int startAt = 0,
    List<String>? fields,
  ]) async {
    final body = await _http.get('search', queryParams: {
      'jql': jql,
      'fields': _joinFields(fields),
      'startAt': startAt.toString(),
      'maxResults': '100',
    });
    return _decodeMap(body);
  }

  /// `jira_get_attachments` — reads `fields.attachment` from the ticket.
  ///
  /// Returns the attachment metadata array; an empty list when the ticket is
  /// absent or has no attachments.
  Future<List<Map<String, dynamic>>> getAttachments(String key) async {
    final ticket = await getTicket(key, ['attachment']);
    if (ticket == null) return const [];
    final fields = ticket['fields'] as Map<String, dynamic>? ?? {};
    return _castObjectList(fields['attachment'] as List? ?? const []);
  }

  /// `jira_get_worklogs` — GET `issue/{key}/worklog`.
  ///
  /// Returns the `worklogs` array; an empty list when absent.
  Future<List<Map<String, dynamic>>> getWorklogs(String key) async {
    final body = await _http.get('issue/$key/worklog');
    return _extractArray(body, 'worklogs');
  }

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

  /// `jira_get_resolutions` — GET `resolution`.
  ///
  /// Returns the full list of issue resolution definitions.
  Future<List<Map<String, dynamic>>> getResolutions() async {
    final body = await _http.get('resolution');
    return _decodeList(body);
  }
}
