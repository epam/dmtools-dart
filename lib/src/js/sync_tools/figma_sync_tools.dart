/// Synchronous Figma tool executors for the JS tool bridge.
///
/// Each handler resolves its config from [PropertyReader], performs
/// blocking HTTP via [SyncHttpClient] (curl subprocess — safe inside
/// QuickJS callbacks), and returns a JSON result string. Tool names,
/// parameters, and response shapes port the Java `FigmaClient`
/// `@MCPTool` methods; the pure shaping and request building live in
/// `figma_document.dart` / `figma_url.dart` / `figma_oauth.dart` /
/// `figma_transfer.dart`, shared with the async [FigmaClient].
library;

import 'dart:convert';
import 'dart:io';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../integrations/figma/figma_document.dart';
import '../../integrations/figma/figma_http_client.dart';
import '../../integrations/figma/figma_oauth.dart';
import '../../integrations/figma/figma_transfer.dart';
import '../../integrations/figma/figma_url.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Figma executors: `figma_*` tool name → JSON result.
class FigmaSyncTools {
  final PropertyReader _reader;

  /// Creates Figma tooling reading config from [reader].
  FigmaSyncTools(this._reader);

  /// Tool executors; config is resolved inside each handler.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'figma_oauth2_get_auth_url': _oauth2GetAuthUrl,
        'figma_oauth2_exchange_code': _oauth2ExchangeCode,
        'figma_test': _me,
        'figma_me': _me,
        'figma_get_screen_source': _getScreenSource,
        'figma_download_node_image': _downloadNodeImage,
        'figma_download_image_of_file': _downloadImageOfFile,
        'figma_get_file_structure': _getFileStructure,
        'figma_get_icons': _getIcons,
        'figma_get_image_fills': _getImageFills,
        'figma_render_nodes': _renderNodes,
        'figma_download_image_as_file': _downloadImageAsFile,
        'figma_get_svg_content': _getSvgContent,
        'figma_get_node_details': _getNodeDetails,
        'figma_get_text_content': _getTextContent,
        'figma_get_styles': _getStyles,
        'figma_get_layers': _getLayers,
        'figma_get_layers_batch': _getLayersBatch,
        'figma_get_node_children': _getNodeChildren,
        'figma_list_team_projects': _listTeamProjects,
        'figma_list_project_files': _listProjectFiles,
        'figma_get_file_comments': _getFileComments,
      };

  /// Runs [body] mapping any failure to [failure] (JSON `null` for the
  /// Java tools that swallow their exceptions).
  String _guarded(String Function() body, [String failure = figmaJsonNull]) {
    try {
      return body();
    } on Object {
      return failure;
    }
  }

  /// Dispatches a Figma tool call, mirroring the dispatcher's errors.
  String dispatch(String toolName, Map<String, dynamic> args) {
    final fn = handlers[toolName];
    if (fn == null) return syncErr('Unsupported Figma tool: $toolName');
    return fn(args);
  }

  /// Builds Figma config, or `null` when the token is missing.
  _Conf? _config() {
    final token = _reader.getFigmaApiKey();
    if (token == null || token.isEmpty) return null;
    final basePath = _reader.getFigmaBasePath() ?? figmaDefaultBasePath;
    return (
      baseUrl: basePath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': syncJsonContentType,
      },
    );
  }

  /// `figma_test` / `figma_me` — GET `me`, Java `me()` result JSON.
  String _me(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final resp =
          SyncHttpClient.get('${config.baseUrl}/me', headers: config.headers);
      if (resp.statusCode == 0) {
        return jsonEncode(figmaMeResult(
          error: resp.body,
          errorClass: 'IOException',
        ));
      }
      return jsonEncode(figmaMeResult(body: resp.body));
    });
  }

  /// `figma_get_screen_source` — image URL of the URL's node, JSON `null`
  /// on any failure (Java swallows the exception).
  String _getScreenSource(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final url = syncAsStr(args['url']);
      try {
        final fileId = figmaParseFileId(url);
        final nodeId = figmaExtractQueryParam(url, figmaNodeIdParam);
        final response = _getJson(config, 'images/$fileId', {'ids': nodeId});
        return jsonEncode(figmaImagesOf(response)?[figmaColonNodeId(nodeId)]);
      } on Object {
        // Java catches and returns null.
        return figmaJsonNull;
      }
    });
  }

  /// `figma_download_node_image` — renders the node (png/2x defaults) and
  /// downloads it, returning the cached file path; JSON `null` when the
  /// API returns no image URL.
  String _downloadNodeImage(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final response = _getJson(
        config,
        'images/${_fileIdOf(args)}',
        figmaRenderParams(
          syncAsStr(args['nodeId']),
          _optional(args['format']) ?? 'png',
          args['scale'] is num ? (args['scale'] as num).toInt() : 2,
        ),
      );
      final imageUrl = figmaImagesOf(response)?[syncAsStr(args['nodeId'])];
      if (imageUrl is! String || imageUrl.isEmpty) {
        return figmaJsonNull;
      }
      return jsonEncode(_download(imageUrl));
    });
  }

  /// `figma_download_image_of_file` — screen source of the design URL
  /// downloaded to a file; JSON `null` when no http source resolves.
  String _downloadImageOfFile(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final source = jsonDecode(_getScreenSource(args));
      if (source is! String || !source.startsWith('http')) {
        return figmaJsonNull;
      }
      return jsonEncode(_download(source));
    });
  }

  /// `figma_get_file_structure` — full file (`geometry=paths&depth=2`) or
  /// URL `node-id` subtree; JSON `null` on failure (Java parity).
  String _getFileStructure(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return _guarded(() {
        final request =
            figmaStructureRequest(figmaCleanHref(syncAsStr(args['href'])));
        final response = _getJson(config, request.path, request.params);
        return response == null ? figmaJsonNull : jsonEncode(response);
      });
    });
  }

  /// `figma_get_icons` — deduplicated exportable elements envelope, JSON
  /// `null` on failure (Java parity).
  String _getIcons(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return _guarded(() {
        final clean = figmaCleanHref(syncAsStr(args['href']));
        final structure = _getStructureJson(config, clean);
        if (structure == null) {
          return figmaJsonNull;
        }
        final unique = <String, Map<String, dynamic>>{};
        for (final icon in figmaFindAllComponents(structure)) {
          final id = icon['id'];
          if (id != null && !unique.containsKey(id)) {
            unique[id as String] = icon;
          }
        }
        return jsonEncode(
          figmaIconsResult(figmaParseFileId(clean), unique.values.toList()),
        );
      });
    });
  }

  /// `figma_get_image_fills` — raw `files/{fileId}/images` body; errors
  /// surface as an error envelope (Java rethrows).
  String _getImageFills(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return syncBodyOrError(SyncHttpClient.get(
        '${config.baseUrl}/files/${_fileIdOf(args)}/images',
        headers: config.headers,
      ));
    });
  }

  /// `figma_render_nodes` — batched (100/request) renders merged into one
  /// `nodeId → URL` map.
  String _renderNodes(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final fileId = _fileIdOf(args);
      final format = _optional(args['format']) ?? 'png';
      final combined = <String, dynamic>{};
      for (final batch in figmaBatches(syncAsStr(args['nodeIds']).split(','))) {
        final response = _getJson(config, 'images/$fileId', {
          'ids': batch.join(','),
          'format': format,
        });
        figmaImagesOf(response)
            ?.forEach((key, value) => combined['$key'] = value);
      }
      return jsonEncode(combined);
    });
  }

  /// `figma_download_image_as_file` — export URL for the node in the
  /// format, downloaded; JSON `null` on any failure (Java parity).
  String _downloadImageAsFile(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final imageUrl = _imageById(
        config,
        syncAsStr(args['href']),
        syncAsStr(args['nodeId']),
        syncAsStr(args['format']),
      );
      if (imageUrl == null || imageUrl.isEmpty) {
        return figmaJsonNull;
      }
      try {
        return jsonEncode(_download(imageUrl));
      } on Object {
        return figmaJsonNull;
      }
    });
  }

  /// `figma_get_svg_content` — SVG markup of the node as text, JSON
  /// `null` on any failure (Java parity).
  String _getSvgContent(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final svgUrl = _imageById(
        config,
        syncAsStr(args['href']),
        syncAsStr(args['nodeId']),
        'svg',
      );
      if (svgUrl == null || svgUrl.isEmpty) {
        return figmaJsonNull;
      }
      try {
        final resp = SyncHttpClient.get(svgUrl, headers: const {});
        if (!resp.isOk) {
          return figmaJsonNull;
        }
        return jsonEncode(resp.body);
      } on Object {
        return figmaJsonNull;
      }
    });
  }

  /// `figma_get_node_details` — document of the first requested node (max
  /// 10); JSON `null` when absent or on failure (Java parity).
  String _getNodeDetails(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return _guarded(() {
        final ids = figmaCappedTrimmedIds(
            syncAsStr(args['nodeIds']), figmaMaxDetailIds);
        final response = _nodesJson(config, _fileIdOf(args), ids);
        final document =
            response == null ? null : figmaNodeDocument(response, ids.first);
        return document == null ? figmaJsonNull : jsonEncode(document);
      });
    });
  }

  /// `figma_get_text_content` — TEXT-node entries keyed by node id (max
  /// 20); JSON `null` on failure (Java parity).
  String _getTextContent(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return _guarded(() {
        final ids =
            figmaCappedTrimmedIds(syncAsStr(args['nodeIds']), figmaMaxTextIds);
        final response = _nodesJson(config, _fileIdOf(args), ids);
        return response == null
            ? figmaJsonNull
            : jsonEncode(figmaTextContent(response, ids));
      });
    });
  }

  /// `figma_get_styles` — the empty design-token envelope (Java parity);
  /// JSON `null` on failure.
  String _getStyles(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return _guarded(() {
        final resp = SyncHttpClient.get(
          '${config.baseUrl}/files/${_fileIdOf(args)}/styles',
          headers: config.headers,
        );
        return resp.isOk ? jsonEncode(figmaStylesResult()) : figmaJsonNull;
      });
    });
  }

  /// `figma_get_layers` — first-level layers of the URL's node (raw
  /// dashed `parentNodeId`); JSON `null` without children (Java parity).
  String _getLayers(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final target = _urlNodeId(args);
      return _guarded(() {
        final response = _nodesJson(config, target.fileId, [target.nodeId]);
        final document =
            figmaNodeDocument(response, figmaColonNodeId(target.nodeId));
        final children = document == null
            ? const <Map<String, dynamic>>[]
            : figmaLayerSummaries(document);
        if (children.isEmpty) {
          return figmaJsonNull;
        }
        return jsonEncode(
            {'parentNodeId': target.nodeId, 'children': children});
      });
    });
  }

  /// `figma_get_layers_batch` — layers for up to 10 nodes keyed by colon
  /// id; an empty map JSON on failure (Java parity).
  String _getLayersBatch(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      return _guarded(() {
        final requested = syncAsStr(args['nodeIds']).split(',');
        final ids = requested.length > figmaMaxDetailIds
            ? requested.sublist(0, figmaMaxDetailIds)
            : requested;
        final response = _nodesJson(config, _fileIdOf(args), ids);
        final results = <String, Map<String, dynamic>>{};
        for (final rawId in ids) {
          final document =
              figmaNodeDocument(response, figmaColonNodeId(rawId.trim()));
          if (document == null) {
            continue;
          }
          final colonId = figmaColonNodeId(rawId.trim());
          results[colonId] = {
            'parentNodeId': colonId,
            'children': figmaLayerSummaries(document),
          };
        }
        return jsonEncode(results);
      }, '{}');
    });
  }

  /// `figma_get_node_children` — immediate children (`depth=1`, raw node
  /// id as parent); JSON `null` when absent. Errors surface (Java
  /// rethrows).
  String _getNodeChildren(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final target = _urlNodeId(args);
      final response =
          _nodesJson(config, target.fileId, [target.nodeId], depth: '1');
      final document = figmaNodeDocument(response, target.nodeId);
      if (document == null) {
        return figmaJsonNull;
      }
      return jsonEncode({
        'parentNodeId': target.nodeId,
        'children': figmaLayerSummaries(document),
      });
    });
  }

  /// `figma_list_team_projects` — projects array JSON.
  String _listTeamProjects(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final teamId = figmaExtractTeamId(syncAsStr(args['teamIdOrUrl']));
      final response = _getJson(config, 'teams/$teamId/projects', const {});
      return jsonEncode(response?['projects'] ?? const []);
    });
  }

  /// `figma_list_project_files` — files array JSON.
  String _listProjectFiles(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final projectId =
          figmaExtractProjectId(syncAsStr(args['projectIdOrUrl']));
      final response = _getJson(config, 'projects/$projectId/files', const {});
      return jsonEncode(response?['files'] ?? const []);
    });
  }

  /// `figma_get_file_comments` — comments array JSON; [href] may be a
  /// design URL or a raw file key.
  String _getFileComments(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfigured, (config) {
      final href = syncAsStr(args['href']);
      String fileKey;
      try {
        fileKey = figmaParseFileId(href);
      } on Object {
        fileKey = href;
      }
      final response = _getJson(config, 'files/$fileKey/comments', const {});
      return jsonEncode(response?['comments'] ?? const []);
    });
  }

  /// `figma_oauth2_get_auth_url` — Java `oauth2GetAuthUrl` parity.
  String _oauth2GetAuthUrl(Map<String, dynamic> args) {
    final clientId = _reader.getFigmaClientId() ?? '';
    if (clientId.isEmpty) {
      return syncErr('FIGMA_CLIENT_ID is not configured');
    }
    final clientSecret = _reader.getFigmaClientSecret() ?? '';
    if (clientSecret.isEmpty) {
      return syncErr('FIGMA_CLIENT_SECRET is not configured');
    }
    final redirectUri = _redirectUri(args);
    if (redirectUri == null) {
      return _redirectUriError();
    }
    final state = _optional(args['state']) ??
        DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final authUrl = figmaBuildAuthorizationUrl(
      clientId: clientId,
      redirectUri: redirectUri,
      state: state,
      scope: _optional(args['scope']) ?? _reader.getFigmaOAuth2Scopes(),
    );
    return jsonEncode({
      'authorization_url': authUrl,
      'instructions': 'Open this URL in your browser, authorize the app, '
          "then copy the 'code' query parameter from the redirect URL and "
          'call figma_oauth2_exchange_code.',
      'state': state,
    });
  }

  /// `figma_oauth2_exchange_code` — Java `oauth2ExchangeCode` parity.
  String _oauth2ExchangeCode(Map<String, dynamic> args) {
    final credentialsError = _oauth2CredentialsError();
    if (credentialsError != null) {
      return credentialsError;
    }
    final redirectUri = _redirectUri(args);
    if (redirectUri == null) {
      return _redirectUriError();
    }
    return _oauth2Exchange(redirectUri, syncAsStr(args['code']));
  }

  /// POSTs the token request and builds the result envelope — Java
  /// `oauth2ExchangeCode` network half, split out of
  /// [_oauth2ExchangeCode] to keep the CRAP score under the threshold.
  String _oauth2Exchange(String redirectUri, String code) {
    final resp = SyncHttpClient.post(
      figmaOAuthTokenUrl,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: figmaTokenRequestBody(
        clientId: _reader.getFigmaClientId() ?? '',
        clientSecret: _reader.getFigmaClientSecret() ?? '',
        code: code,
        redirectUri: redirectUri,
      ),
    );
    if (!resp.isOk) {
      return syncErr(
        'Token exchange failed: Figma OAuth2 token request failed '
        '[${resp.statusCode}]: ${resp.body}',
      );
    }
    final tokens = figmaParseTokenResponse(resp.body);
    return jsonEncode({
      'access_token': tokens.accessToken,
      'refresh_token': tokens.refreshToken,
      'expires_in': tokens.expiresIn,
      'instructions': 'Add FIGMA_OAUTH_REFRESH_TOKEN=${tokens.refreshToken}'
          ' to your dmtools.env to enable automatic token refresh. You can '
          'also set FIGMA_OAUTH_ACCESS_TOKEN=${tokens.accessToken} for '
          'immediate use (expires in ${tokens.expiresIn}s).',
    });
  }

  /// The shared missing-credentials error envelope, or `null` when both
  /// Figma OAuth2 client credentials are configured — split out of
  /// [_oauth2ExchangeCode] to keep the CRAP score under the threshold.
  String? _oauth2CredentialsError() {
    final clientId = _reader.getFigmaClientId() ?? '';
    final clientSecret = _reader.getFigmaClientSecret() ?? '';
    if (clientId.isEmpty || clientSecret.isEmpty) {
      return syncErr(
        'FIGMA_CLIENT_ID and FIGMA_CLIENT_SECRET must be configured',
      );
    }
    return null;
  }

  /// Redirect URI from args or env, or `null` when unusable.
  String? _redirectUri(Map<String, dynamic> args) {
    final uri = _optional(args['redirectUri']) ?? _reader.getFigmaRedirectUri();
    return uri == null || uri.isEmpty ? null : uri;
  }

  /// The shared missing-redirect-URI error envelope.
  String _redirectUriError() => syncErr(
        'redirectUri is required (or set FIGMA_REDIRECT_URI in dmtools.env)',
      );

  /// File key of the args' `href` (cleaned).
  String _fileIdOf(Map<String, dynamic> args) =>
      figmaParseFileId(figmaCleanHref(syncAsStr(args['href'])));

  /// GET `files/{fileId}/nodes` for the comma-joined [ids] with an
  /// optional `depth`.
  Map<String, dynamic>? _nodesJson(
    _Conf config,
    String fileId,
    List<String> ids, {
    String? depth,
  }) {
    final params = <String, String>{'ids': ids.join(',')};
    if (depth != null) {
      params['depth'] = depth;
    }
    return _getJson(config, 'files/$fileId/nodes', params);
  }

  /// (fileId, node-id) pair extracted from the args' `href`.
  ({String fileId, String nodeId}) _urlNodeId(Map<String, dynamic> args) =>
      figmaUrlNodeId(figmaCleanHref(syncAsStr(args['href'])));

  /// GETs one API path and decodes the JSON object body, or `null` when
  /// the request failed or the body was not a JSON object.
  Map<String, dynamic>? _getJson(
    _Conf config,
    String path, [
    Map<String, String> queryParams = const {},
  ]) {
    final uri = Uri.parse('${config.baseUrl}/$path').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final resp = SyncHttpClient.get(uri.toString(), headers: config.headers);
    if (!resp.isOk) {
      return null;
    }
    final decoded = syncTryDecode(resp.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Fetches and decodes a design structure (shared by the icon/structure
  /// tools); `null` on failure.
  Map<String, dynamic>? _getStructureJson(_Conf config, String cleanHref) {
    final request = figmaStructureRequest(cleanHref);
    return _getJson(config, request.path, request.params);
  }

  /// Export URL of a node in a format — Java `getImageById`; `null` on
  /// failure.
  String? _imageById(
    _Conf config,
    String href,
    String nodeId,
    String format,
  ) {
    try {
      return figmaImagesOf(_getJson(
        config,
        'images/${figmaParseFileId(figmaCleanHref(href))}',
        figmaIconRenderParams(nodeId, format),
      ))?[figmaColonNodeId(nodeId)]
          ?.toString();
    } on Object {
      return null;
    }
  }

  /// Downloads [url] to the md5-named cache file, returning its path —
  /// Java `downloadImage` + `getCachedFile` parity.
  String _download(String url) {
    final file = figmaCacheFileFor(url, _cacheDir);
    if (!file.existsSync()) {
      final resp = syncCurlStaged(
        'GET',
        url,
        headers: const {},
        outputFile: file.path,
      );
      if (resp.statusCode == 0 || !resp.isOk) {
        if (file.existsSync()) {
          file.deleteSync();
        }
        throw StateError('Download failed [${resp.statusCode}]');
      }
    }
    return file.path;
  }

  /// Optional string argument: `null` or blank → `null`.
  String? _optional(dynamic value) {
    final str = value?.toString() ?? '';
    return str.isEmpty ? null : str;
  }
}

/// Resolved sync integration config: base URL plus auth headers.
typedef _Conf = ({String baseUrl, Map<String, String> headers});

/// Error payload returned when Figma config is incomplete.
const _notConfigured = 'Figma not configured';

/// Cache directory for downloaded images (async client parity).
final _cacheDir = '${Directory.systemTemp.path}/dmtools_figma_cache';
