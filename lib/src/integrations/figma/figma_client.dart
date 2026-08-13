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
  Future<Map<String, dynamic>> _fetchMe() => _getJson('me');

  /// GET helper that decodes the response body as a JSON object.
  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    final body = await _http.get(path, queryParams: queryParams);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// POST helper that JSON-encodes [body] and decodes the response.
  Future<Map<String, dynamic>> _postJson(String path, Object body) async {
    final response = await _http.post(path, body: jsonEncode(body));
    return jsonDecode(response) as Map<String, dynamic>;
  }

  /// `figma_get_file` — GET `/files/{key}`.
  Future<Map<String, dynamic>> getFile(String key) => _getJson('files/$key');

  /// `figma_get_file_nodes` — GET `/files/{key}/nodes?ids={nodeIds}`.
  Future<Map<String, dynamic>> getFileNodes(String key, String nodeIds) =>
      _getJson('files/$key/nodes', queryParams: {'ids': nodeIds});

  /// `figma_get_image` — GET `/images/{key}?ids={nodeId}`.
  Future<Map<String, dynamic>> getImage(String key, String nodeId) =>
      _getJson('images/$key', queryParams: {'ids': nodeId});

  /// `figma_get_comments` — GET `/files/{key}/comments`.
  Future<Map<String, dynamic>> getComments(String key) =>
      _getJson('files/$key/comments');

  /// `figma_post_comment` — POST `/files/{key}/comments` with `{message}`.
  Future<Map<String, dynamic>> postComment(String key, String message) =>
      _postJson('files/$key/comments', {'message': message});

  /// `figma_get_components` — GET `/files/{key}/components`.
  Future<Map<String, dynamic>> getComponents(String key) =>
      _getJson('files/$key/components');

  /// `figma_get_component_sets` — GET `/files/{key}/component_sets`.
  Future<Map<String, dynamic>> getComponentSets(String key) =>
      _getJson('files/$key/component_sets');

  /// `figma_get_variable_collections` — GET `/files/{key}/variables/local`.
  Future<Map<String, dynamic>> getVariableCollections(String key) =>
      _getJson('files/$key/variables/local');

  /// `figma_get_library_components` — GET `/libraries/{libraryKey}/components`.
  Future<Map<String, dynamic>> getLibraryComponents(String libraryKey) =>
      _getJson('libraries/$libraryKey/components');

  /// `figma_get_styles` — GET `/files/{key}/styles`.
  Future<Map<String, dynamic>> getStyles(String key) =>
      _getJson('files/$key/styles');

  /// `figma_export_image` — GET `/images/{key}` with optional format/scale.
  Future<Map<String, dynamic>> exportImage(
    String key, {
    String? format,
    double? scale,
  }) {
    final params = <String, dynamic>{};
    if (format != null) params['format'] = format;
    if (scale != null) params['scale'] = scale;
    return _getJson('images/$key', queryParams: params);
  }
}
