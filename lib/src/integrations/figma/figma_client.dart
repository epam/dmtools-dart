/// High-level Figma API client — ports the Figma `@MCPTool` catalog of the
/// Java integration client.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// `FigmaClient`. Transport is delegated to [FigmaHttpClient]; this layer
/// shapes requests and parses JSON into typed results. URL handling ports
/// `figma_url.dart`; result envelopes port `figma_document.dart`; OAuth2
/// ports `figma_oauth2.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'figma_document.dart';
import 'figma_http_client.dart';
import 'figma_url.dart';

/// Figma API methods exposed to the MCP tool runtime.
class FigmaClient {
  final FigmaHttpClient _http;

  /// Cache directory for downloaded images (Java `getCachedFile` parity:
  /// md5-named files, reused across calls).
  final String cacheDir;

  /// Creates a client backed by [_http].
  ///
  /// [cacheDir] overrides where [downloadImage] stores files (tests);
  /// production code gets `<systemTemp>/dmtools_figma_cache`.
  FigmaClient(
    this._http, {
    String? cacheDir,
  }) : cacheDir = cacheDir ?? _defaultCacheDir;

  static final _defaultCacheDir =
      '${Directory.systemTemp.path}/dmtools_figma_cache';

  /// `figma_test` / `figma_me` — GET `/me`, Java `me()` shape.
  ///
  /// Returns `{success, message, user: {id, handle, email?}}` on success;
  /// `{success: false, message, error?}` describing the failure otherwise.
  Future<Map<String, dynamic>> me() async {
    try {
      final body = await _http.get('me');
      return figmaMeResult(body: body);
    } on Object catch (failure) {
      return figmaMeResult(
        error: '$failure',
        errorClass: failure.runtimeType.toString(),
      );
    }
  }

  /// `figma_test` — connectivity check; Java returns the `me()` map.
  Future<Map<String, dynamic>> testConnection() => me();

  /// `figma_me` — the `me()` map as a JSON string (Java `meMCP`).
  Future<String> meJson() async => jsonEncode(await me());

  /// GET helper that decodes the response body as a JSON object.
  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    final body = await _http.get(path, queryParams: queryParams);
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// GET helper returning the raw response body (non-JSON endpoints).
  Future<String> _getText(
    String path, {
    Map<String, dynamic>? queryParams,
  }) =>
      _http.get(path, queryParams: queryParams);

  /// POST helper that JSON-encodes [body] and decodes the response.
  Future<Map<String, dynamic>> _postJson(String path, Object body) async {
    final response = await _http.post(path, body: jsonEncode(body));
    return jsonDecode(response) as Map<String, dynamic>;
  }

  /// `figma_get_file_structure` — GET `/files/{fileId}` (full file, size
  /// limited) or GET `/files/{fileId}/nodes?ids=` (URL `node-id` subtree).
  ///
  /// Returns the decoded response, or `null` on any failure (Java logs and
  /// returns null).
  Future<Map<String, dynamic>?> getFileStructure(String href) async {
    final clean = figmaCleanHref(href);
    final fileId = figmaParseFileId(clean);
    String? nodeId;
    try {
      nodeId = figmaExtractQueryParam(clean, 'node-id');
    } on StateError {
      nodeId = null;
    }
    try {
      if (nodeId != null && nodeId.isNotEmpty) {
        return await _getJson('files/$fileId/nodes', queryParams: {
          'ids': nodeId,
        });
      }
      return await _getJson('files/$fileId', queryParams: const {
        'geometry': 'paths',
        'depth': '2',
      });
    } on Object {
      return null;
    }
  }

  /// `figma_get_icons` — exportable visual elements of the design,
  /// deduplicated by node id; `null` on failure (Java parity).
  Future<Map<String, dynamic>?> getIcons(String href) async {
    try {
      final response = await getFileStructure(href);
      if (response == null) {
        return null;
      }
      final fileId = figmaParseFileId(figmaCleanHref(href));
      final unique = <String, Map<String, dynamic>>{};
      for (final icon in figmaFindAllComponents(response)) {
        final id = icon['id'];
        if (id != null && !unique.containsKey(id)) {
          unique[id as String] = icon;
        }
      }
      return figmaIconsResult(fileId, unique.values.toList());
    } on Object {
      return null;
    }
  }

  /// `figma_get_image_fills` — GET `/files/{fileId}/images`, raw body.
  Future<String> getImageFills(String href) => _getText(
        'files/${figmaParseFileId(figmaCleanHref(href))}/images',
      );

  /// `figma_render_nodes` — batched (100/request) node renders merged into
  /// one `nodeId → URL` map, JSON-encoded. Errors propagate (Java parity).
  Future<String> renderNodes(
    String href,
    String nodeIds, {
    String? format,
  }) async {
    final fileId = figmaParseFileId(figmaCleanHref(href));
    final effectiveFormat = (format == null || format.isEmpty) ? 'png' : format;
    final ids = nodeIds.split(',');
    final combined = <String, dynamic>{};
    for (var i = 0; i < ids.length; i += 100) {
      final end = (i + 100 > ids.length) ? ids.length : i + 100;
      final batchIds = ids.sublist(i, end).join(',');
      final response = await _getJson('images/$fileId', queryParams: {
        'ids': batchIds,
        'format': effectiveFormat,
      });
      final images = response['images'];
      if (images is Map) {
        images.forEach((key, value) => combined['$key'] = value);
      }
    }
    return jsonEncode(combined);
  }

  /// `figma_get_screen_source` — image URL of the URL's node, `null` on
  /// any failure (Java swallows the exception).
  Future<String?> getImageOfSource(String url) async {
    try {
      final fileId = figmaParseFileId(url);
      final nodeId = figmaExtractQueryParam(url, 'node-id');
      final response = await _getJson('images/$fileId', queryParams: {
        'ids': nodeId,
      });
      final images = response['images'];
      if (images is Map) {
        return images[figmaColonNodeId(nodeId)]?.toString();
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// `figma_download_node_image` — renders [nodeId] (format default png,
  /// scale default 2) and downloads it; `null` when no URL is returned.
  Future<String?> downloadNodeImage(
    String href,
    String nodeId, {
    String? format,
    int? scale,
  }) async {
    final fileId = figmaParseFileId(figmaCleanHref(href));
    final effectiveFormat = (format == null || format.isEmpty) ? 'png' : format;
    final effectiveScale = scale ?? 2;
    final response = await _getJson('images/$fileId', queryParams: {
      'ids': nodeId,
      'format': effectiveFormat,
      'scale': '$effectiveScale',
    });
    final images = response['images'];
    final imageUrl = images is Map ? images[nodeId]?.toString() : null;
    if (imageUrl == null) {
      return null;
    }
    return downloadImage(imageUrl);
  }

  /// Downloads [url] to the cache, returning the local file path.
  ///
  /// Java `downloadImage` + `getCachedFile`: md5-named file (`.png` when
  /// the URL contains "images"), reused without re-fetching when present.
  Future<String> downloadImage(String url) async {
    final file = _cacheFileFor(url);
    if (file.existsSync()) {
      return file.path;
    }
    final body = await _http.getAbsolute(url);
    file.writeAsBytesSync(utf8.encode(body), flush: true);
    return file.path;
  }

  /// Cache file for [url] — md5 name, `.png` suffix for image URLs.
  File _cacheFileFor(String url) {
    final name = md5.convert(utf8.encode(url)).toString();
    final suffix = url.contains('images') ? '.png' : '';
    final dir = Directory(cacheDir)..createSync(recursive: true);
    return File('${dir.path}/$name$suffix');
  }

  /// `figma_download_image_of_file` — converts a design URL to a
  /// downloaded image file; `null` when no http source resolves.
  Future<String?> convertUrlToFile(String href) async {
    final imageUrl = await getImageOfSource(figmaCleanHref(href));
    if (imageUrl == null || !imageUrl.startsWith('http')) {
      return null;
    }
    return downloadImage(imageUrl);
  }

  /// `figma_download_image_as_file` — export URL for [nodeId] in [format],
  /// downloaded; `null` on any failure (Java parity).
  Future<String?> downloadIconFile(
    String href,
    String nodeId,
    String format,
  ) async {
    try {
      final imageUrl = await getImageById(href, nodeId, format);
      if (imageUrl == null || imageUrl.isEmpty) {
        return null;
      }
      return await downloadImage(imageUrl);
    } on Object {
      return null;
    }
  }

  /// Export URL of [nodeId] in [format] — Java `getImageById` (png adds a
  /// 2x scale); `null` on failure.
  Future<String?> getImageById(
    String href,
    String nodeId,
    String format,
  ) async {
    try {
      final fileId = figmaParseFileId(figmaCleanHref(href));
      final params = <String, dynamic>{
        'ids': nodeId,
        'format': format,
      };
      if (format == 'png') {
        params['scale'] = '2';
      }
      final response = await _getJson('images/$fileId', queryParams: params);
      final images = response['images'];
      if (images is Map) {
        return images[figmaColonNodeId(nodeId)]?.toString();
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// `figma_get_svg_content` — SVG markup of [nodeId] as text; `null` on
  /// any failure (Java parity).
  Future<String?> getSvgContent(String href, String nodeId) async {
    try {
      final svgUrl = await getImageById(href, nodeId, 'svg');
      if (svgUrl == null || svgUrl.isEmpty) {
        return null;
      }
      return await _http.getAbsolute(svgUrl);
    } on Object {
      return null;
    }
  }

  /// `figma_get_node_details` — the document of the first requested node
  /// (max 10 ids); `null` when absent or on failure (Java parity).
  Future<Map<String, dynamic>?> getNodeDetails(
    String href,
    String nodeIds,
  ) async {
    try {
      final fileId = figmaParseFileId(figmaCleanHref(href));
      final ids = _cappedTrimmedIds(nodeIds, 10);
      final response = await _getJson('files/$fileId/nodes', queryParams: {
        'ids': ids.join(','),
      });
      return figmaNodeDocument(response, ids.first);
    } on Object {
      return null;
    }
  }

  /// `figma_get_text_content` — TEXT-node entries keyed by node id (max 20
  /// ids); `null` on failure (Java parity).
  Future<Map<String, dynamic>?> getTextContent(
    String href,
    String nodeIds,
  ) async {
    try {
      final fileId = figmaParseFileId(figmaCleanHref(href));
      final ids = _cappedTrimmedIds(nodeIds, 20);
      final response = await _getJson('files/$fileId/nodes', queryParams: {
        'ids': ids.join(','),
      });
      return figmaTextContent(response, ids);
    } on Object {
      return null;
    }
  }

  /// Splits [nodeIds], trims each, and caps the list at [max] (Java
  /// `Arrays.copyOf` parity).
  List<String> _cappedTrimmedIds(String nodeIds, int max) {
    final ids = nodeIds.split(',').map((id) => id.trim()).toList();
    return ids.length > max ? ids.sublist(0, max) : ids;
  }

  /// `figma_get_styles` (Java parity) — hits the styles endpoint but
  /// returns the empty token envelope (`{colorStyles: [], textStyles: []}`);
  /// `null` on failure.
  Future<Map<String, dynamic>?> getDesignStyles(String href) async {
    try {
      final fileId = figmaParseFileId(figmaCleanHref(href));
      await _getText('files/$fileId/styles');
      return figmaStylesResult();
    } on Object {
      return null;
    }
  }

  /// `figma_get_layers` — first-level layers of the URL's node (raw
  /// dashed `parentNodeId`); `null` when there are no children or on
  /// request failure (Java parity).
  Future<Map<String, dynamic>?> getLayers(String href) async {
    final clean = figmaCleanHref(href);
    final fileId = figmaParseFileId(clean);
    final nodeId = figmaExtractQueryParam(clean, 'node-id');
    try {
      final response = await _getJson('files/$fileId/nodes', queryParams: {
        'ids': nodeId,
      });
      final document = _nodeDocumentByColonId(response, nodeId);
      if (document == null) {
        return null;
      }
      final children = figmaLayerSummaries(document);
      if (children.isEmpty) {
        return null;
      }
      return {'parentNodeId': nodeId, 'children': children};
    } on Object {
      return null;
    }
  }

  /// `figma_get_layers_batch` — layers for up to 10 nodes keyed by colon
  /// id; an empty map on failure (Java parity).
  Future<Map<String, Map<String, dynamic>>> getLayersBatch(
    String href,
    String nodeIds,
  ) async {
    try {
      final fileId = figmaParseFileId(figmaCleanHref(href));
      final requested = nodeIds.split(',');
      final ids = requested.length > 10 ? requested.sublist(0, 10) : requested;
      final response = await _getJson('files/$fileId/nodes', queryParams: {
        'ids': ids.join(','),
      });
      final results = <String, Map<String, dynamic>>{};
      for (final rawId in ids) {
        final colonId = figmaColonNodeId(rawId.trim());
        final document = _nodeDocumentByColonId(response, rawId.trim());
        if (document == null) {
          continue;
        }
        final children = figmaLayerSummaries(document);
        results[colonId] = {'parentNodeId': colonId, 'children': children};
      }
      return results;
    } on Object {
      return {};
    }
  }

  /// `figma_get_node_children` — immediate children of the URL's node
  /// (`depth=1`, raw node id as parent); `null` when absent. Errors
  /// propagate (Java rethrows).
  Future<Map<String, dynamic>?> getNodeChildren(String href) async {
    final clean = figmaCleanHref(href);
    final fileId = figmaParseFileId(clean);
    final nodeId = figmaExtractQueryParam(clean, 'node-id');
    final response = await _getJson('files/$fileId/nodes', queryParams: {
      'ids': nodeId,
      'depth': '1',
    });
    final nodes = response['nodes'];
    final nodeData = nodes is Map ? nodes[nodeId] : null;
    final document = _documentOf(nodeData);
    if (document == null) {
      return null;
    }
    return {
      'parentNodeId': nodeId,
      'children': figmaLayerSummaries(document),
    };
  }

  /// Looks up a node document by colon-normalized id (getLayers parity:
  /// response keys are colon-separated).
  Map<String, dynamic>? _nodeDocumentByColonId(
    Map<String, dynamic> response,
    String nodeId,
  ) {
    final nodes = response['nodes'];
    if (nodes is! Map) {
      return null;
    }
    return _documentOf(nodes[figmaColonNodeId(nodeId)]);
  }

  /// Reads `document` out of a node-data envelope.
  Map<String, dynamic>? _documentOf(dynamic nodeData) {
    if (nodeData is Map && nodeData['document'] is Map) {
      return Map<String, dynamic>.from(nodeData['document'] as Map);
    }
    return null;
  }

  /// `figma_list_team_projects` — projects array of the team (raw numeric
  /// id or `/team/<id>` URL).
  Future<List<dynamic>> listTeamProjects(String teamIdOrUrl) async {
    final teamId = figmaExtractTeamId(teamIdOrUrl);
    final response = await _getJson('teams/$teamId/projects');
    return (response['projects'] as List?) ?? const [];
  }

  /// `figma_list_project_files` — files array of the project (raw numeric
  /// id or `/project/<id>` URL).
  Future<List<dynamic>> listProjectFiles(String projectIdOrUrl) async {
    final projectId = figmaExtractProjectId(projectIdOrUrl);
    final response = await _getJson('projects/$projectId/files');
    return (response['files'] as List?) ?? const [];
  }

  /// `figma_get_file_comments` — comments array of the file; [href] may be
  /// a design URL or a raw file key (Java falls back to the raw value).
  Future<List<dynamic>> getFileComments(String href) async {
    String fileKey;
    try {
      fileKey = figmaParseFileId(href);
    } on Object {
      fileKey = href;
    }
    final response = await _getJson('files/$fileKey/comments');
    return (response['comments'] as List?) ?? const [];
  }

  /// `figma_get_file` — GET `/files/{key}`.
  Future<Map<String, dynamic>> getFile(String key) => _getJson('files/$key');

  /// `figma_get_file_nodes` — GET `/files/{key}/nodes?ids={nodeIds}`.
  Future<Map<String, dynamic>> getFileNodes(String key, String nodeIds) =>
      _getJson('files/$key/nodes', queryParams: {'ids': nodeIds});

  /// `figma_get_node` — GET `/files/{key}/nodes?ids={nodeId}` (singular).
  Future<Map<String, dynamic>> getNode(String key, String nodeId) =>
      _getJson('files/$key/nodes', queryParams: {'ids': nodeId});

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

  /// `figma_get_style` — GET `/files/{key}/styles` (Dart-only singular).
  Future<Map<String, dynamic>> getStyle(String key) =>
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
