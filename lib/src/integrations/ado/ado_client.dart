/// High-level Azure DevOps API client — ports the ADO subset of the Java MCP
/// tools.
///
/// Each method corresponds to a Java `@MCPTool`-annotated method (or a
/// net-new PR tool, for which there is no Java client yet). Transport is
/// delegated to [AdoHttpClient]; this layer only shapes requests and parses
/// JSON into typed results.
library;

import 'dart:convert';

import 'ado_http_client.dart';

/// Azure DevOps API methods exposed to the MCP tool runtime.
class AdoClient {
  final AdoHttpClient _http;

  /// Creates a client backed by [_http].
  AdoClient(this._http);

  /// `ado_test` — connectivity check via GET `{org}/_apis/connection-data`.
  ///
  /// Returns `success` + the authenticated user descriptor on success, or a
  /// failure map on error.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.getOrg('connection-data');
      final data = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Azure DevOps connection successful',
        'authenticatedUser': data['authenticatedUser'],
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Azure DevOps connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `ado_get_work_item` — GET `{org}/{project}/_apis/wit/workitems/{id}`.
  Future<Map<String, dynamic>> getWorkItem(int id) async {
    final body = await _http.get('wit/workitems/$id');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_create_work_item` — POST `{org}/{project}/_apis/wit/workitems/$type`.
  ///
  /// The body is a JSON Patch document (ADO's required wire format) that sets
  /// `System.Title`; the `Content-Type` is `application/json-patch+json`.
  Future<Map<String, dynamic>> createWorkItem(String type, String title) async {
    final body = await _http.postPatch(
      'wit/workitems/\$$type',
      body: jsonEncode([
        {'op': 'add', 'path': '/fields/System.Title', 'value': title},
      ]),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_list_prs` — GET `{org}/{project}/_apis/git/pullrequests`.
  ///
  /// [status] defaults to `active` (ADO's default) when omitted, passed as
  /// `searchCriteria.status`.
  Future<List<Map<String, dynamic>>> listPrs([String? status]) async {
    final body = await _http.get(
      'git/pullrequests',
      queryParams: {'searchCriteria.status': status ?? 'active'},
    );
    return (jsonDecode(body) as List)
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
  }

  /// `ado_get_pr` — GET `{org}/{project}/_apis/git/pullrequests/{id}`.
  Future<Map<String, dynamic>> getPr(int id) async {
    final body = await _http.get('git/pullrequests/$id');
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
