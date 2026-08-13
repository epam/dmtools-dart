/// High-level Confluence Cloud API client — ports the top MCP tool methods.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// `ConfluenceClient`. Transport is delegated to [ConfluenceHttpClient];
/// this layer shapes requests and parses JSON into typed results.
library;

import 'dart:convert';

import 'confluence_http_client.dart';

/// Confluence Cloud API methods exposed to the MCP tool runtime.
class ConfluenceClient {
  final ConfluenceHttpClient _http;

  /// Creates a client backed by [_http].
  ConfluenceClient(this._http);

  /// `confluence_test` — connectivity check via GET `user/current`.
  ///
  /// Returns `success: true` with the user profile on success, or
  /// `success: false` with the error message on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('user/current');
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Confluence connection successful',
        'user': user['displayName'] ?? '',
        'email': user['email'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Confluence connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `confluence_get_page` — GET `content?spaceKey=&title=&expand=body.storage`.
  ///
  /// Returns the first matching page, or `null` when no page is found.
  Future<Map<String, dynamic>?> getPage(
    String spaceKey,
    String title,
  ) async {
    final body = await _http.get(
      'content',
      queryParams: {
        'spaceKey': spaceKey,
        'title': title,
        'expand': 'body.storage',
      },
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final results = decoded['results'] as List? ?? [];
    if (results.isEmpty) return null;
    return results.first as Map<String, dynamic>;
  }

  /// `confluence_create_page` — POST `content`.
  ///
  /// Creates a new page in [spaceKey] with the given [title] and storage-format
  /// [body]; returns the created page object from the API.
  Future<Map<String, dynamic>> createPage(
    String spaceKey,
    String title,
    String body,
  ) async {
    final responseBody = await _http.post(
      'content',
      body: jsonEncode(_pagePayload(spaceKey, title, body)),
    );
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// Builds the page creation/update payload.
  Map<String, dynamic> _pagePayload(
    String spaceKey,
    String title,
    String body,
  ) =>
      {
        'type': 'page',
        'title': title,
        'space': {'key': spaceKey},
        'body': {
          'storage': {'value': body, 'representation': 'storage'},
        },
      };

  /// `confluence_update_page` — PUT `content/{id}`.
  ///
  /// Updates the page with [id], bumping its version to [version].
  Future<Map<String, dynamic>> updatePage(
    String id,
    String title,
    String body,
    int version,
  ) async {
    final responseBody = await _http.put(
      'content/$id',
      body: jsonEncode(_updatePayload(id, title, body, version)),
    );
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// Builds the page update payload including the version number.
  Map<String, dynamic> _updatePayload(
    String id,
    String title,
    String body,
    int version,
  ) {
    final payload = _pagePayload('', title, body);
    payload['id'] = id;
    payload['version'] = {'number': version};
    return payload;
  }

  /// `confluence_search` — GET `content/search?cql=`.
  ///
  /// Returns the list of search results for the given CQL [query].
  Future<List<Map<String, dynamic>>> search(String query) async {
    final body = await _http.get(
      'content/search',
      queryParams: {'cql': query},
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final results = decoded['results'] as List? ?? [];
    return List<Map<String, dynamic>>.from(
      results.map((r) => r as Map<String, dynamic>),
    );
  }
}
