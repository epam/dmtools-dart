/// High-level Figma API client — ports the Figma subset of the Java MCP tools.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// integration client. Transport is delegated to [FigmaHttpClient]; this
/// layer only shapes requests and parses JSON into typed results.
library;

import 'dart:convert';

import 'figma_http_client.dart';

/// Figma API methods exposed to the MCP tool runtime.
class FigmaClient {
  final FigmaHttpClient _http;

  /// Creates a client backed by [_http].
  FigmaClient(this._http);

  /// `figma_test` — connectivity check via GET `/me`.
  ///
  /// Returns the Figma user profile on success, or an error map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final profile = await _fetchMe();
      final handle = profile['handle'] ?? profile['email'] ?? '';
      return <String, dynamic>{
        'success': true,
        'message': 'Figma connection successful',
        'user': handle,
      };
    } on Object catch (failure) {
      return <String, dynamic>{
        'success': false,
        'message': 'Figma connection failed',
        'error': failure.toString(),
      };
    }
  }

  /// Fetches the authenticated user from GET `/me`.
  Future<Map<String, dynamic>> _fetchMe() async {
    final body = await _http.get('me');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `figma_get_file` — GET `/files/{key}`.
  Future<Map<String, dynamic>> getFile(String key) async {
    final body = await _http.get('files/$key');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `figma_get_file_nodes` — GET `/files/{key}/nodes?ids={nodeIds}`.
  Future<Map<String, dynamic>> getFileNodes(String key, String nodeIds) async {
    final body = await _http.get(
      'files/$key/nodes',
      queryParams: {'ids': nodeIds},
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `figma_get_image` — GET `/images/{key}?ids={nodeId}`.
  Future<Map<String, dynamic>> getImage(String key, String nodeId) async {
    final body = await _http.get(
      'images/$key',
      queryParams: {'ids': nodeId},
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
