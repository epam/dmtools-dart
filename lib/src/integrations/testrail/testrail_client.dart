/// High-level TestRail API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a TestRail API endpoint. Transport is delegated
/// to [TestRailHttpClient]; this layer only shapes requests and parses JSON
/// into typed results.
library;

import 'dart:convert';

import 'testrail_http_client.dart';

/// TestRail API methods exposed to the MCP tool runtime.
class TestRailClient {
  final TestRailHttpClient _http;

  /// Creates a client backed by [_http].
  TestRailClient(this._http);

  /// `testrail_test` — connectivity check via GET `get_user_by_email`.
  ///
  /// Uses the configured username as the email lookup. Returns `success: true`
  /// with the user name on success, or `success: false` with the error on
  /// failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get(
        'get_user_by_email&email=${_http.username}',
      );
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'TestRail connection successful',
        'user': user['name'] ?? '',
        'email': user['email'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'TestRail connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `testrail_get_case` — GET `get_case/{id}`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getCase(int id) async {
    return _decodeMap(await _http.get('get_case/$id'));
  }

  /// `testrail_get_cases` — GET `get_cases/{projectId}&suite_id={suiteId}`.
  ///
  /// The project ID comes from the configured `TESTRAIL_PROJECT`.
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getCases(int suiteId) async {
    final body = await _http.get(
      'get_cases/${_http.projectId}&suite_id=$suiteId',
    );
    return _decodeList(body);
  }

  /// `testrail_add_result` — POST `add_result/{testId}`.
  ///
  /// Sets [statusId] and [comment] on the new result for test [testId].
  Future<Map<String, dynamic>> addResult(
    int testId,
    int statusId,
    String comment,
  ) async {
    final body = await _http.post(
      'add_result/$testId',
      body: jsonEncode({'status_id': statusId, 'comment': comment}),
    );
    return _decodeMap(body) ?? {};
  }

  /// Decodes a JSON body to a map, or `null` when not an object.
  Map<String, dynamic>? _decodeMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Decodes a JSON array of objects, tolerating non-array bodies.
  List<Map<String, dynamic>> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return List<Map<String, dynamic>>.from(
      decoded.map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }
}
