/// Page-level search extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Page-level search methods on [JiraClient]: a single Cloud cursor page
/// (`search/jql`) and the deprecated Server/DC offset page (`search`).
extension JiraSearchClient on JiraClient {
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
}
