/// Agile board extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Agile-board methods on [JiraClient]: per-project board configuration and
/// board-scoped issue/sprint listing via the Agile API.
extension JiraAgileClient on JiraClient {
  /// `jira_get_project_board_config` — GET `board/{boardId}/configuration`.
  ///
  /// Looks up the first board for [key] via the Agile API, then fetches its
  /// full configuration. Returns an empty map when no board exists.
  Future<Map<String, dynamic>> getProjectBoardConfig(String key) async {
    final boardId = await _findBoardId(key);
    if (boardId == null) return {};
    final body = await _http.getAgile('board/$boardId/configuration');
    return _decodeMap(body);
  }

  /// Finds the first Agile board id for [key], or `null`.
  Future<int?> _findBoardId(String key) async {
    final body = await _http.getAgile(
      'board',
      queryParams: {'projectKeyOrId': key},
    );
    final decoded = _decodeMap(body);
    final values = decoded['values'] as List? ?? const [];
    if (values.isEmpty) return null;
    return (values.first as Map<String, dynamic>)['id'] as int?;
  }

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
