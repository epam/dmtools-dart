/// Batch-7 Jira client methods — split from [JiraClient] for file-size.
part of 'jira_client.dart';

// ── Batch 7 extension on JiraClient ─────────────────────────────────────

/// Batch-7 extension methods on [JiraClient], adding priorities, security
/// levels, a generic data export, and Agile board/sprint listing — the
/// remaining methods needed for full Java tool-surface parity.
extension JiraClientBatch7 on JiraClient {
  /// `jira_get_priorities` — GET `priority`.
  ///
  /// Returns the full list of issue priority definitions.
  Future<List<Map<String, dynamic>>> getPriorities() async {
    final body = await _http.get('priority');
    return _decodeList(body);
  }

  /// `jira_get_security_levels` — GET `securitylevel`.
  ///
  /// Returns the full list of issue security level definitions.
  Future<List<Map<String, dynamic>>> getSecurityLevels() async {
    final body = await _http.get('securitylevel');
    return _decodeList(body);
  }

  /// `jira_export_data` — bulk-export every issue matching [jql].
  ///
  /// Delegates to [JiraClient.searchByJql] for full auto-pagination (Cloud
  /// cursor + Server/DC offset), returning all matching issues as a flat
  /// list. Pass [fields] to restrict the exported field set.
  Future<List<Map<String, dynamic>>> exportData(
    String jql, [
    List<String>? fields,
  ]) =>
      searchByJql(jql, fields);

  /// `jira_get_board_issues` — GET agile/1.0/board/{boardId}/issue.
  ///
  /// Fetches every issue on the Agile board [boardId], auto-paginating via
  /// the offset-based `startAt`/`total` mechanism. Pass [jql] to filter.
  Future<List<Map<String, dynamic>>> getBoardIssues(
    int boardId, [
    String? jql,
  ]) async {
    final all = <Map<String, dynamic>>[];
    var startAt = 0;
    var total = 0;
    do {
      final params = <String, dynamic>{
        'startAt': startAt.toString(),
        'maxResults': '100',
      };
      if (jql != null) params['jql'] = jql;
      final body = await _http.getAgile(
        'board/$boardId/issue',
        queryParams: params,
      );
      final decoded = _decodeMap(body);
      all.addAll(_castObjectList(decoded['issues'] as List? ?? const []));
      total = (decoded['total'] as num?)?.toInt() ?? all.length;
      startAt += 100;
    } while (startAt < total);
    return all;
  }

  /// `jira_get_sprints` — GET agile/1.0/board/{boardId}/sprint.
  ///
  /// Fetches every sprint on the Agile board [boardId], auto-paginating via
  /// the `startAt`/`isLast`/`total` mechanism.
  Future<List<Map<String, dynamic>>> getSprints(int boardId) async {
    final all = <Map<String, dynamic>>[];
    var startAt = 0;
    while (true) {
      final body = await _http.getAgile(
        'board/$boardId/sprint',
        queryParams: {
          'startAt': startAt.toString(),
          'maxResults': '100',
        },
      );
      final decoded = _decodeMap(body);
      all.addAll(_castObjectList(decoded['values'] as List? ?? const []));
      final isLast = decoded['isLast'] as bool? ?? true;
      final total = (decoded['total'] as num?)?.toInt() ?? all.length;
      if (isLast || startAt >= total) break;
      startAt += 100;
    }
    return all;
  }
}
