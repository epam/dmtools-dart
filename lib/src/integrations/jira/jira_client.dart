/// High-level Jira API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// `JiraClient`. Transport is delegated to [JiraHttpClient]; this layer only
/// shapes requests and parses JSON into typed results.
library;

import 'dart:convert';

import 'jira_http_client.dart';

/// Jira API methods exposed to the MCP tool runtime.
class JiraClient {
  final JiraHttpClient _http;

  /// Creates a client backed by [_http].
  JiraClient(this._http);

  /// Joins field names into the `fields` query value, defaulting to
  /// `*navigable` (Java default) when none are requested.
  String _joinFields(List<String>? fields) =>
      fields != null && fields.isNotEmpty ? fields.join(',') : '*navigable';

  /// `jira_test` — connectivity check via GET `/rest/api/latest/myself`.
  ///
  /// Returns `success: true` with the user profile on success, or
  /// `success: false` with the error message on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('myself');
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Jira connection successful',
        'user': user['displayName'] ?? '',
        'email': user['emailAddress'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Jira connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `jira_get_ticket` — GET `/rest/api/latest/issue/{key}`.
  ///
  /// [fields] defaults to `*navigable`. Returns `null` for non-object bodies.
  Future<Map<String, dynamic>?> getTicket(
    String key, [
    List<String>? fields,
  ]) async {
    final body = await _http.get(
      'issue/$key',
      queryParams: {'fields': _joinFields(fields)},
    );
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  /// `jira_search_by_jql` — searches by JQL with auto-pagination.
  ///
  /// Tries the Cloud cursor endpoint first (`/rest/api/latest/search/jql`),
  /// paginating via `nextPageToken`. If that returns nothing and signals no
  /// cursor, falls back to the Server/DC offset-based `/search` endpoint.
  Future<List<Map<String, dynamic>>> searchByJql(
    String jql, [
    List<String>? fields,
  ]) async {
    final fieldsParam = _joinFields(fields);
    final result = await _searchCursor(jql, fieldsParam);
    if (result.issues.isEmpty && !result.tokenSeen) {
      return _searchServerOffset(jql, fieldsParam);
    }
    return result.issues;
  }

  /// Runs the Cloud cursor-paginated `search/jql` endpoint.
  Future<({List<Map<String, dynamic>> issues, bool tokenSeen})> _searchCursor(
    String jql,
    String fields,
  ) async {
    final body = await _http.get(
      'search/jql',
      queryParams: {'jql': jql, 'fields': fields},
    );
    final tokenSeen = body.contains('nextPageToken');
    final all = _extractIssues(body);
    var nextToken = _nextToken(body);
    while (nextToken != null) {
      final pageBody = await _http.get('search/jql', queryParams: {
        'jql': jql,
        'fields': fields,
        'nextPageToken': nextToken,
      });
      all.addAll(_extractIssues(pageBody));
      nextToken = _nextToken(pageBody);
    }
    return (issues: all, tokenSeen: tokenSeen);
  }

  /// Parses the `issues` array out of a search response body.
  List<Map<String, dynamic>> _extractIssues(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final issues = decoded['issues'] as List? ?? [];
    return List<Map<String, dynamic>>.from(
      issues.map((i) => i as Map<String, dynamic>),
    );
  }

  /// Extracts `nextPageToken` from a search body, or `null`.
  String? _nextToken(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded['nextPageToken'] as String?;
  }

  /// Server/DC offset-based pagination fallback for `/search`.
  Future<List<Map<String, dynamic>>> _searchServerOffset(
    String jql,
    String fields,
  ) async {
    const maxResults = 100;
    final all = <Map<String, dynamic>>[];
    var startAt = 0;
    var total = 0;
    do {
      final body = await _http.get('search', queryParams: {
        'jql': jql,
        'fields': fields,
        'startAt': startAt.toString(),
        'maxResults': maxResults.toString(),
      });
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final issues = decoded['issues'] as List? ?? [];
      all.addAll(issues.map((i) => i as Map<String, dynamic>));
      total = (decoded['total'] as num?)?.toInt() ?? 0;
      startAt += maxResults;
    } while (startAt < total);
    return all;
  }

  /// `jira_post_comment` — POST `/rest/api/latest/issue/{key}/comment`.
  Future<void> postComment(String key, String comment) async {
    await _http.post(
      'issue/$key/comment',
      body: jsonEncode({'body': comment}),
    );
  }

  /// `jira_add_label` — adds [label] to [key] if not already present.
  Future<void> addLabel(String key, String label) async {
    final labels = await _fetchLabels(key);
    if (labels.contains(label)) return;
    labels.add(label);
    await _setLabels(key, labels);
  }

  /// `jira_remove_label` — removes [label] from [key] if present.
  Future<void> removeLabel(String key, String label) async {
    final labels = await _fetchLabels(key);
    labels.remove(label);
    await _setLabels(key, labels);
  }

  /// Fetches the current labels list for [key].
  Future<List<String>> _fetchLabels(String key) async {
    final body = await _http.get(
      'issue/$key',
      queryParams: {'fields': 'labels'},
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final fields = decoded['fields'] as Map<String, dynamic>? ?? {};
    return List<String>.from(fields['labels'] as List? ?? []);
  }

  /// PUTs the full labels set for [key] using `update.labels[].set`.
  Future<void> _setLabels(String key, List<String> labels) async {
    await _http.put('issue/$key',
        body: jsonEncode({
          'update': {
            'labels': [
              {'set': labels}
            ]
          },
        }));
  }

  /// `jira_move_to_status` — transitions [key] to [statusName].
  ///
  /// Matches by transition name or destination status name (case-insensitive).
  /// Returns the POST response body, or an explanatory string when no
  /// matching transition exists.
  Future<String> moveToStatus(String key, String statusName) async {
    final transitionId = await _findTransition(key, statusName);
    if (transitionId == null) {
      return 'No transition found for status: $statusName';
    }
    return _http.post(
      'issue/$key/transitions',
      body: jsonEncode({
        'transition': {'id': transitionId}
      }),
    );
  }

  /// Finds a transition id matching [statusName] for [key].
  Future<String?> _findTransition(String key, String statusName) async {
    final transitions = await getTransitions(key);
    final target = statusName.toLowerCase();
    for (final t in transitions) {
      final name = (t['name'] as String?)?.toLowerCase() ?? '';
      final toStatus = t['to'] as Map<String, dynamic>?;
      final toName = (toStatus?['name'] as String?)?.toLowerCase() ?? '';
      if (name == target || toName == target) {
        return t['id'] as String?;
      }
    }
    return null;
  }

  /// `jira_get_comments` — GET `/rest/api/latest/issue/{key}/comment`.
  ///
  /// Returns the `comments` array; an empty list when the body is not an
  /// object or the array is absent.
  Future<List<Map<String, dynamic>>> getComments(String key) async {
    final body = await _http.get('issue/$key/comment');
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final comments = decoded['comments'] as List? ?? [];
    return List<Map<String, dynamic>>.from(
      comments.map((c) => c as Map<String, dynamic>),
    );
  }

  /// `jira_assign` — PUT `/rest/api/latest/issue/{key}/assignee`.
  Future<void> assignTo(String key, String accountId) async {
    await _http.put(
      'issue/$key/assignee',
      body: jsonEncode({'accountId': accountId}),
    );
  }

  /// `jira_update_field` — PUT `/rest/api/latest/issue/{key}`.
  ///
  /// Sets a single [field] to [value] inside the `fields` object.
  Future<void> updateField(String key, String field, Object value) async {
    await _http.put(
      'issue/$key',
      body: jsonEncode({
        'fields': {field: value},
      }),
    );
  }

  /// `jira_create_ticket` — POST `/rest/api/latest/issue`.
  ///
  /// Creates a ticket in [project] with the given [issueType] name and
  /// [summary]; [description] is included only when provided.
  Future<Map<String, dynamic>> createTicketBasic(
    String project,
    String issueType,
    String summary, [
    String? description,
  ]) async {
    final fields = <String, dynamic>{
      'project': {'key': project},
      'issuetype': {'name': issueType},
      'summary': summary,
    };
    if (description != null) fields['description'] = description;
    final body =
        await _http.post('issue', body: jsonEncode({'fields': fields}));
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  /// `jira_get_transitions` — GET `/rest/api/latest/issue/{key}/transitions`.
  ///
  /// Returns the `transitions` array; an empty list when the body is not an
  /// object or the array is absent.
  Future<List<Map<String, dynamic>>> getTransitions(String key) async {
    final body = await _http.get('issue/$key/transitions');
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final transitions = decoded['transitions'] as List? ?? [];
    return List<Map<String, dynamic>>.from(
      transitions.map((t) => t as Map<String, dynamic>),
    );
  }

  /// `jira_delete_ticket` — DELETE `/rest/api/latest/issue/{key}`.
  Future<void> deleteTicket(String key) async {
    await _http.delete('issue/$key');
  }

  /// `jira_clear_field` — PUT `/rest/api/latest/issue/{key}`.
  ///
  /// Sets a single [field] to `null`, effectively clearing it.
  Future<void> clearField(String key, String field) async {
    await _http.put(
      'issue/$key',
      body: jsonEncode({
        'fields': {field: null},
      }),
    );
  }
}
