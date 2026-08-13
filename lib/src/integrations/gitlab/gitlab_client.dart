/// High-level GitLab API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a GitLab MCP tool. Transport is delegated to
/// [GitlabHttpClient]; this layer shapes requests and parses JSON into typed
/// results. Project identifiers may be numeric ids or `group/project` paths
/// and are URL-encoded automatically.
library;

import 'dart:convert';

import 'gitlab_http_client.dart';

/// GitLab API methods exposed to the MCP tool runtime.
class GitlabClient {
  final GitlabHttpClient _http;

  /// Creates a client backed by [_http].
  GitlabClient(this._http);

  /// URL-encodes a project id or `group/project` path for path segments.
  String _encodeProject(String project) => Uri.encodeComponent(project);

  /// `gitlab_test` — connectivity check via GET `/api/v4/user`.
  ///
  /// Returns the GitLab user profile on success, or an error map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('user');
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'GitLab connection successful',
        'user': user['name'] ?? user['username'] ?? '',
        'email': user['email'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'GitLab connection failed',
        'error': e.toString(),
      };
    }
  }

  /// GETs [path] and returns the JSON object body, or `null` if not a map.
  Future<Map<String, dynamic>?> _getObject(String path) async {
    final body = await _http.get(path);
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  /// POSTs [path] with [payload] and returns the JSON object body, or `null`.
  Future<Map<String, dynamic>?> _postObject(
    String path,
    Object? payload,
  ) async {
    final result = await _http.post(path, body: payload);
    final decoded = jsonDecode(result);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  /// `gitlab_get_mr` — GET `/api/v4/projects/{id}/merge_requests/{iid}`.
  ///
  /// [project] is the numeric id or `group/project` path. Returns `null`
  /// for non-object bodies.
  Future<Map<String, dynamic>?> getMr(String project, int iid) => _getObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid',
      );

  /// `gitlab_list_mrs` — GET `/api/v4/projects/{id}/merge_requests`.
  ///
  /// [project] is the numeric id or `group/project` path. [state] filters
  /// by MR state (`opened`, `closed`, `merged`, `all`); defaults to `opened`.
  Future<List<Map<String, dynamic>>> listMrs(
    String project, [
    String state = 'opened',
  ]) async {
    final body = await _http.get(
      'projects/${_encodeProject(project)}/merge_requests',
      queryParams: {'state': state, 'per_page': 20},
    );
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return List<Map<String, dynamic>>.from(
      decoded.map((i) => i as Map<String, dynamic>),
    );
  }

  /// `gitlab_create_mr_note` — POST a note on a merge request.
  ///
  /// Returns the created note object, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> createMrNote(
    String project,
    int iid,
    String body,
  ) =>
      _postObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid/notes',
        jsonEncode({'body': body}),
      );

  /// `gitlab_get_issue` — GET `/api/v4/projects/{id}/issues/{iid}`.
  ///
  /// Returns `null` for non-object bodies.
  Future<Map<String, dynamic>?> getIssue(String project, int iid) =>
      _getObject('projects/${_encodeProject(project)}/issues/$iid');
}
