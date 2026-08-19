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
      final appCount = _unwrapList(decoded).length;
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
    return _decodeObject(body) ?? const {};
  }

  /// `bitrise_trigger_build` — POST `apps/{slug}/builds`.
  ///
  /// Triggers a build with empty build params (the server applies workflow
  /// defaults). Returns the decoded response object, or `null` for non-object
  /// bodies.
  Future<Map<String, dynamic>?> triggerBuild(String appSlug) =>
      _postBuild(appSlug, const {});

  /// `bitrise_get_apps` — GET `apps`.
  ///
  /// Returns the decoded list of app objects, or an empty list for non-array
  /// bodies.
  Future<List<Map<String, dynamic>>> getApps() async {
    final body = await _http.get('apps');
    return _decodeList(body);
  }

  /// `bitrise_get_build_detail` — GET `apps/{appSlug}/builds/{buildSlug}`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getBuildDetail(
    String appSlug,
    String buildSlug,
  ) async {
    final body = await _http.get(
      'apps/${_encodeSlug(appSlug)}/builds/${_encodeSlug(buildSlug)}',
    );
    return _decodeObject(body);
  }

  /// `bitrise_abort_build` — POST `apps/{appSlug}/builds/{buildSlug}/abort`.
  ///
  /// Aborts an in-progress build. Returns the decoded response object, or
  /// `null` when the body is not a JSON object.
  Future<Map<String, dynamic>?> abortBuild(
    String appSlug,
    String buildSlug,
  ) async {
    final body = await _http.post(
      'apps/${_encodeSlug(appSlug)}/builds/${_encodeSlug(buildSlug)}/abort',
    );
    return _decodeObject(body);
  }

  /// `bitrise_trigger_build_with_params` — POST `apps/{appSlug}/builds`.
  ///
  /// Triggers a build with the given [workflow] and optional [environments].
  /// Returns the decoded response object, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> triggerBuildWithParams(
    String appSlug,
    String workflow,
    List<Map<String, dynamic>>? environments,
  ) async {
    final buildParams = <String, dynamic>{'workflow_id': workflow};
    if (environments != null) {
      buildParams['environments'] = environments;
    }
    return _postBuild(appSlug, buildParams);
  }

  /// `bitrise_get_workflows` — GET `apps/{appSlug}/build-workflows`.
  ///
  /// Mirrors Java `bitrise_list_workflows`, which reads the workflow list
  /// from the `build-workflows` endpoint (the v0.1 API has no
  /// `build-slots` route). Returns the decoded response object, or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getWorkflows(String appSlug) async {
    final body =
        await _http.get('apps/${_encodeSlug(appSlug)}/build-workflows');
    return _decodeObject(body) ?? const {};
  }

  /// `bitrise_get_artifacts` — GET `apps/{appSlug}/builds/{buildSlug}/artifacts`.
  ///
  /// Returns the decoded response object (contains `data` + `paging`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getArtifacts(
    String appSlug,
    String buildSlug,
  ) async {
    final body = await _http.get(
      'apps/${_encodeSlug(appSlug)}/builds/${_encodeSlug(buildSlug)}/artifacts',
    );
    return _decodeObject(body) ?? const {};
  }

  /// `bitrise_get_artifact_detail` — GET
  /// `apps/{appSlug}/builds/{buildSlug}/artifacts/{artifactSlug}`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getArtifactDetail(
    String appSlug,
    String buildSlug,
    String artifactSlug,
  ) async {
    final body = await _http.get(
      'apps/${_encodeSlug(appSlug)}/builds/${_encodeSlug(buildSlug)}'
      '/artifacts/${_encodeSlug(artifactSlug)}',
    );
    return _decodeObject(body);
  }

  /// POSTs [buildParams] to `apps/{appSlug}/builds` and decodes the object.
  Future<Map<String, dynamic>?> _postBuild(
    String appSlug,
    Map<String, dynamic> buildParams,
  ) async {
    final result = await _http.post(
      'apps/${_encodeSlug(appSlug)}/builds',
      body: jsonEncode({'build_params': buildParams}),
    );
    return _decodeObject(result);
  }

  /// Parses [body] as a JSON object map, or returns null on mismatch.
  Map<String, dynamic>? _decodeObject(String body) {
    final parsed = jsonDecode(body);
    return parsed is Map<String, dynamic> ? parsed : null;
  }

  /// Parses [body] as a JSON object list, or returns empty on mismatch.
  ///
  /// Bitrise v0.1 wraps list responses in `{data: [...], paging: {...}}` —
  /// the wrapped shape is unwrapped first; a bare array is accepted as a
  /// fallback for older/mock endpoints.
  List<Map<String, dynamic>> _decodeList(String body) {
    final parsed = jsonDecode(body);
    return _unwrapList(parsed)
        .cast<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// Extracts the list payload from a Bitrise response ([decoded]).
  List _unwrapList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return data;
    }
    return const [];
  }
}
