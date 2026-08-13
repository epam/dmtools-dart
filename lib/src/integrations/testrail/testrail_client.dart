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
  Future<List<Map<String, dynamic>>> getCases(int suiteId) async =>
      _getList('get_cases/${_http.projectId}&suite_id=$suiteId');

  /// `testrail_add_result` — POST `add_result/{testId}`.
  ///
  /// Sets [statusId] and [comment] on the new result for test [testId].
  Future<Map<String, dynamic>> addResult(
    int testId,
    int statusId,
    String comment,
  ) =>
      _postForMap(
        'add_result/$testId',
        {'status_id': statusId, 'comment': comment},
      );

  /// `testrail_get_runs` — GET `get_runs/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getRuns(int projectId) async =>
      _getList('get_runs/$projectId');

  /// `testrail_get_sections` — GET `get_sections/{projectId}&suite_id={suiteId}`.
  ///
  /// The project ID comes from the configured `TESTRAIL_PROJECT`.
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getSections(int suiteId) async =>
      _getList('get_sections/${_http.projectId}&suite_id=$suiteId');

  /// `testrail_add_case` — POST `add_case/{sectionId}`.
  ///
  /// Creates a new test case with [title] under [sectionId].
  Future<Map<String, dynamic>> addCase(int sectionId, String title) =>
      _postForMap('add_case/$sectionId', {'title': title});

  /// `testrail_update_case` — POST `update_case/{id}`.
  ///
  /// Updates test case [id] with the provided [fields] map.
  Future<Map<String, dynamic>> updateCase(
    int id,
    Map<String, dynamic> fields,
  ) =>
      _postForMap('update_case/$id', fields);

  /// `testrail_get_milestones` — GET `get_milestones/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getMilestones(int projectId) async =>
      _getList('get_milestones/$projectId');

  /// `testrail_get_plans` — GET `get_plans/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getPlans(int projectId) async =>
      _getList('get_plans/$projectId');

  /// `testrail_add_run` — POST `add_run/{projectId}`.
  ///
  /// Creates a new test run named [name] under [projectId].
  Future<Map<String, dynamic>> addRun(int projectId, String name) =>
      _postForMap('add_run/$projectId', {'name': name});

  /// `testrail_update_run` — POST `update_run/{runId}`.
  ///
  /// Renames the test run [runId] to [name].
  Future<Map<String, dynamic>> updateRun(int runId, String name) =>
      _postForMap('update_run/$runId', {'name': name});

  /// `testrail_get_case_types` — GET `get_case_types/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getCaseTypes(int projectId) async =>
      _getList('get_case_types/$projectId');

  /// `testrail_get_priorities` — GET `get_priorities`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getPriorities() async =>
      _getList('get_priorities');

  /// `testrail_get_statuses` — GET `get_statuses`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getStatuses() async =>
      _getList('get_statuses');

  /// GETs [path] and decodes the JSON array response.
  Future<List<Map<String, dynamic>>> _getList(String path) async =>
      _decodeList(await _http.get(path));

  /// POSTs [payload] to [path] and returns the decoded object, or `{}`.
  Future<Map<String, dynamic>> _postForMap(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final body = await _http.post(path, body: jsonEncode(payload));
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
