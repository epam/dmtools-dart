/// High-level Bitrise API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a Bitrise MCP tool. Transport is delegated to
/// [BitriseHttpClient]; this layer shapes requests and parses JSON into typed
/// results. App slugs are URL-encoded automatically.
library;

import 'dart:convert';

import 'bitrise_http_client.dart';

/// Bitrise API methods exposed to the MCP tool runtime.
class BitriseClient {
  final BitriseHttpClient _http;

  /// Creates a client backed by [_http].
  BitriseClient(this._http);

  /// URL-encodes an app slug for safe path-segment use.
  String _encodeSlug(String slug) => Uri.encodeComponent(slug);

  /// `bitrise_test` — connectivity check via GET `apps`.
  ///
  /// Returns the accessible app count on success, or an error map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('apps');
      final decoded = jsonDecode(body);
      final appCount = decoded is List ? decoded.length : 0;
      return {
        'success': true,
        'message': 'Bitrise connection successful',
        'apps': appCount,
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Bitrise connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `bitrise_get_builds` — GET `apps/{slug}/builds`.
  ///
  /// Returns the decoded response object (contains `data` + `paging`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getBuilds(String appSlug) async {
    final body = await _http.get('apps/${_encodeSlug(appSlug)}/builds');
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `bitrise_trigger_build` — POST `apps/{slug}/builds`.
  ///
  /// Triggers a build with empty build params (the server applies workflow
  /// defaults). Returns the decoded response object, or `null` for non-object
  /// bodies.
  Future<Map<String, dynamic>?> triggerBuild(String appSlug) async {
    final result = await _http.post(
      'apps/${_encodeSlug(appSlug)}/builds',
      body: jsonEncode({'build_params': <String, dynamic>{}}),
    );
    final decoded = jsonDecode(result);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }
}
