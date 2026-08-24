/// Synchronous Confluence tool executors for the JS tool bridge.
///
/// Public counterpart of the dispatcher's private Confluence section: each
/// handler resolves its config from [PropertyReader], performs blocking HTTP
/// via [SyncHttpClient] (curl subprocess — safe inside QuickJS callbacks),
/// and returns a JSON result string. Tool names, parameters, and URL shapes
/// port the Java `Confluence.java` `@MCPTool` methods; the three legacy
/// handlers (`confluence_search`, `confluence_get_page`,
/// `confluence_create_page`) move here unchanged from the dispatcher so it
/// can drop its private section.
library;

import 'dart:convert';
import 'dart:io';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../integrations/confluence/confluence_markdown.dart';
import '../../integrations/confluence/markdown_confluence_sync.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Confluence executors: `confluence_*` tool name → JSON result.
class ConfluenceSyncTools {
  final PropertyReader _reader;

  /// Creates Confluence tooling reading config from [reader].
  ConfluenceSyncTools(this._reader);

  /// Tool executors; config is resolved inside each handler.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'confluence_search': _search,
        'confluence_get_page': _getPage,
        'confluence_create_page': _createPage,
        'confluence_update_page': _updatePage,
        'confluence_content_by_id': _contentById,
        'confluence_get_children_by_id': _getChildrenById,
        'confluence_sync_markdown_directory': _syncMarkdownDirectory,
      };

  /// Dispatches a Confluence tool call, mirroring the dispatcher's errors.
  String dispatch(String toolName, Map<String, dynamic> args) {
    final fn = handlers[toolName];
    if (fn == null) return syncErr('Unsupported Confluence tool: $toolName');
    return fn(args);
  }

  /// Builds Confluence config, or `null` when base path / auth is missing.
  ///
  /// Mirrors the dispatcher section this class replaces: `{authType} {token}`
  /// Authorization and the `/wiki/rest/api` suffix (the sync-path convention;
  /// the async [ConfluenceHttpClient] appends only `/rest/api`).
  _Conf? _config() {
    final basePath = _reader.getConfluenceBasePath();
    if (basePath == null || basePath.isEmpty) return null;
    final token = _reader.getConfluenceLoginPassToken();
    if (token == null || token.isEmpty) return null;
    final authType = _reader.getConfluenceAuthType();
    return (
      baseUrl: '$basePath/wiki/rest/api',
      headers: {
        'Authorization': '$authType $token',
        'Accept': syncJsonContentType,
        'Content-Type': syncJsonContentType,
      },
    );
  }

  /// `confluence_search` — GET `content/search?cql={cql}`.
  String _search(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final cql = Uri.encodeQueryComponent(syncAsStr(args['cql']));
      return syncBodyOrError(SyncHttpClient.get(
        '${config.baseUrl}/content/search?cql=$cql',
        headers: config.headers,
      ));
    });
  }

  /// `confluence_get_page` — GET `content?spaceKey=&title=&expand=body.storage`.
  String _getPage(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final spaceKey = Uri.encodeQueryComponent(syncAsStr(args['spaceKey']));
      final title = Uri.encodeQueryComponent(syncAsStr(args['title']));
      return syncBodyOrError(SyncHttpClient.get(
        '${config.baseUrl}/content?spaceKey=$spaceKey&title=$title'
        '&expand=body.storage',
        headers: config.headers,
      ));
    });
  }

  /// `confluence_create_page` — POST `content` with the storage-format page
  /// (Java `createPage`; `ancestors` included when `parentId` is given).
  String _createPage(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      return syncBodyOrError(SyncHttpClient.post(
        '${config.baseUrl}/content',
        headers: config.headers,
        body: jsonEncode(_pagePayload(args)),
      ));
    });
  }

  /// `confluence_update_page` — PUT `content/{contentId}` with a bumped
  /// version (Java `updatePage`: fetch current version, +1, ancestors, space).
  String _updatePage(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final contentId = syncAsStr(args['contentId']);
      final version = _currentVersion(config, contentId);
      if (version == null)
        return syncErr('Failed to fetch version for $contentId');
      return syncBodyOrError(SyncHttpClient.put(
        '${config.baseUrl}/content/$contentId',
        headers: config.headers,
        body: jsonEncode(_updatePayload(args, contentId, version + 1)),
      ));
    });
  }

  /// `confluence_content_by_id` — GET `content/{id}` with the standard
  /// expand list.
  String _contentById(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final id = syncAsStr(args['contentId']);
      final body = syncBodyOrError(
        _contentGet(config, '$id?expand=$_contentExpand'),
      );
      return _applyFormat(body, args['format']);
    });
  }

  /// `confluence_get_children_by_id` — GET
  /// `content/{contentId}/child/page?limit=100&expand=…`, returning the
  /// `results` array (Java returns the content list, not the wrapper).
  String _getChildrenById(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final id = syncAsStr(args['contentId']);
      final resp = _contentGet(
        config,
        '$id/child/page?limit=100&expand=$_contentExpand',
      );
      final results = _childrenResults(syncBodyOrError(resp));
      if (results == null) {
        return syncErr('Unexpected children response for $id');
      }
      if (_isMarkdownFormat(args['format'])) {
        for (final content in results) {
          _convertStorageToMarkdown(content);
        }
      }
      return jsonEncode(results);
    });
  }

  /// `confluence_sync_markdown_directory` — mirrors a local Markdown tree
  /// into a Confluence page subtree (Java `syncMarkdownDirectory`).
  String _syncMarkdownDirectory(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final directory = syncAsStr(args['directory']);
      final dir = Directory(directory);
      if (!dir.existsSync()) {
        return syncErr('Directory not found: $directory');
      }
      final engine = MarkdownConfluenceSync(
        _SyncConfluenceAttachments(config),
        _SyncConfluencePageOps(config),
      );
      return engine.syncDirectory(
        dir,
        syncAsStr(args['parentId']),
        syncAsStr(args['space']),
        args['deleteOrphans'] == true || args['deleteOrphans'] == 'true',
        syncAsStr(args['attachmentsDir']).isEmpty
            ? null
            : syncAsStr(args['attachmentsDir']),
      );
    });
  }

  /// Builds the page creation payload (Java `createPage` wire format).
  Map<String, dynamic> _pagePayload(Map<String, dynamic> args) {
    final payload = <String, dynamic>{
      'type': 'page',
      'title': syncAsStr(args['title']),
      'space': {'key': syncAsStr(args['space'])},
      'body': {
        'storage': {
          'value': syncAsStr(args['body']),
          'representation': 'storage'
        },
      },
    };
    final parentId = syncAsStr(args['parentId'] ?? args['parentPageId']);
    if (parentId.isNotEmpty) {
      payload['ancestors'] = [
        {'id': parentId},
      ];
    }
    return payload;
  }

  /// Builds the page update payload (Java `updatePage` wire format).
  Map<String, dynamic> _updatePayload(
    Map<String, dynamic> args,
    String contentId,
    int version,
  ) =>
      _contentPayload(
        id: contentId,
        title: syncAsStr(args['title']),
        parentId: syncAsStr(args['parentId']),
        body: syncAsStr(args['body']),
        space: syncAsStr(args['space']),
        version: {'number': version},
      );

  /// Fetches the current version number of [contentId]; `null` on failure.
  int? _currentVersion(_Conf config, String contentId) =>
      _versionNumberOf(_versionResponse(config, contentId));
}

/// Page CRUD over [SyncHttpClient] for [MarkdownConfluenceSync].
class _SyncConfluencePageOps implements ConfluencePageOperations {
  final _Conf _config;

  /// Creates page operations bound to a resolved [_config].
  _SyncConfluencePageOps(this._config);

  @override
  Map<String, dynamic> createPage(
    String title,
    String parentId,
    String body,
    String space,
  ) {
    final resp = SyncHttpClient.post(
      '${_config.baseUrl}/content',
      headers: _config.headers,
      body: jsonEncode(
        _contentPayload(
            title: title, parentId: parentId, body: body, space: space),
      ),
    );
    return _decodeOrThrow(resp, 'createPage');
  }

  @override
  Map<String, dynamic> updatePage(
    String contentId,
    String title,
    String parentId,
    String body,
    String space, [
    String historyComment = '',
  ]) {
    final version = _fetchVersion(contentId);
    final resp = SyncHttpClient.put(
      '${_config.baseUrl}/content/$contentId',
      headers: _config.headers,
      body: jsonEncode(_contentPayload(
        id: contentId,
        title: title,
        parentId: parentId,
        body: body,
        space: space,
        version: {'number': version + 1, 'message': historyComment},
      )),
    );
    return _decodeOrThrow(resp, 'updatePage');
  }

  @override
  List<Map<String, dynamic>> getChildren(String contentId) {
    final resp = SyncHttpClient.get(
      '${_config.baseUrl}/content/$contentId/child/page?limit=100',
      headers: _config.headers,
    );
    final decoded = _decodeOrThrow(resp, 'getChildren');
    final results = decoded['results'];
    if (results is! List) return const [];
    return results.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  @override
  String deletePage(String contentId) => syncBodyOrError(SyncHttpClient.delete(
        '${_config.baseUrl}/content/$contentId',
        headers: _config.headers,
      ));

  @override
  Map<String, dynamic> getContent(String contentId) {
    final resp = SyncHttpClient.get(
      '${_config.baseUrl}/content/$contentId'
      '?expand=body.storage,ancestors,version',
      headers: _config.headers,
    );
    return _decodeOrThrow(resp, 'getContent');
  }

  /// Fetches the current version number of [contentId]; `0` on failure.
  int _fetchVersion(String contentId) =>
      _versionNumberOf(_versionResponse(_config, contentId)) ?? 0;

  /// Decodes a JSON object response or throws with the operation context.
  Map<String, dynamic> _decodeOrThrow(SyncHttpResponse resp, String op) {
    if (resp.statusCode == 0) {
      throw StateError('$op failed: ${resp.body}');
    }
    final decoded = syncTryDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw StateError('$op returned a non-object response');
  }
}

/// Attachment listing + multipart upload over curl for the sync engine.
class _SyncConfluenceAttachments implements SyncAttachmentHelper {
  final _Conf _config;

  /// Creates attachment operations bound to a resolved [_config].
  _SyncConfluenceAttachments(this._config);

  @override
  List<String> listAttachmentNames(String contentId) {
    final resp = SyncHttpClient.get(
      '${_config.baseUrl}/content/$contentId/child/attachment',
      headers: _config.headers,
    );
    if (!resp.isOk) return const [];
    final decoded = syncTryDecode(resp.body);
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (r is Map && r['title'] is String) r['title'] as String,
    ];
  }

  @override
  void uploadAttachment(String contentId, File file) {
    final url = '${_config.baseUrl}/content/$contentId/child/attachment';
    final result = _multipartPost(url, file);
    if (result.statusCode == 0 || !result.isOk) {
      throw StateError('Attachment upload failed: ${result.body}');
    }
  }

  /// POSTs [file] as `multipart/form-data` via a curl `-F` invocation.
  ///
  /// [SyncHttpClient] only carries JSON bodies, so the multipart call
  /// stages its headers in a temp file (same secrecy contract) and runs
  /// curl directly with `-F "file=@…"`.
  SyncHttpResponse _multipartPost(String url, File file) => syncCurlStaged(
        'POST',
        url,
        headers: {
          ..._config.headers,
          'X-Atlassian-Token': 'nocheck',
        }..remove('Content-Type'),
        multipartFile: file.path,
      );
}

// ── Shared helpers ─────────────────────────────────────────────────────────

/// Resolved sync integration config: base URL plus auth headers.
typedef _Conf = ({String baseUrl, Map<String, String> headers});

/// Error payload returned when Confluence config is incomplete.
const _notConfiguredError = 'Confluence not configured';

/// The Java `contentById` expand list (full storage, export view,
/// ancestors, and version).
const _contentExpand = 'body.storage,body.export_view,ancestors,version';

/// GETs `content/{suffix}` with the resolved config's auth headers.
SyncHttpResponse _contentGet(_Conf config, String suffix) =>
    SyncHttpClient.get('${config.baseUrl}/content/$suffix',
        headers: config.headers);

/// Builds the `content` request payload shared by page create/update
/// (Java wire format: [id]/version keys appear only when given).
Map<String, dynamic> _contentPayload({
  String? id,
  required String title,
  required String parentId,
  required String body,
  required String space,
  Map<String, dynamic>? version,
}) =>
    {
      if (id != null) 'id': id,
      'type': 'page',
      'title': title,
      'ancestors': [
        {'id': parentId},
      ],
      'space': {'key': space},
      if (version != null) 'version': version,
      'body': {
        'storage': {'value': body, 'representation': 'storage'},
      },
    };

/// GETs `content/{contentId}?expand=version`.
SyncHttpResponse _versionResponse(_Conf config, String contentId) =>
    SyncHttpClient.get(
      '${config.baseUrl}/content/$contentId?expand=version',
      headers: config.headers,
    );

/// Reads `version.number` from a `?expand=version` response; `null` when
/// the response failed or carries no numeric version.
int? _versionNumberOf(SyncHttpResponse resp) {
  if (!resp.isOk) return null;
  final decoded = syncTryDecode(resp.body);
  if (decoded is! Map) return null;
  final version = decoded['version'];
  if (version is Map && version['number'] is num) {
    return (version['number'] as num).toInt();
  }
  return null;
}

/// The `results` page list of a children response; `null` when the body is
/// not a results object.
List<Map<String, dynamic>>? _childrenResults(String body) {
  final decoded = syncTryDecode(body);
  if (decoded is! Map || decoded['results'] is! List) return null;
  return (decoded['results'] as List)
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList();
}

/// Whether [format] requests Markdown conversion (Java `isMarkdownFormat`).
bool _isMarkdownFormat(dynamic format) {
  final f = format?.toString().toLowerCase() ?? '';
  return f == 'md' || f == 'markdown';
}

/// Applies the Java `applyFormat` contract to a JSON response body string:
/// converts `body.storage.value` to Markdown when requested.
String _applyFormat(String body, dynamic format) {
  if (!_isMarkdownFormat(format)) return body;
  final decoded = syncTryDecode(body);
  if (decoded is! Map<String, dynamic>) return body;
  _convertStorageToMarkdown(decoded);
  return jsonEncode(decoded);
}

/// Converts one content object's storage body to Markdown, in place.
void _convertStorageToMarkdown(Map<String, dynamic> content) {
  final body = content['body'];
  if (body is! Map) return;
  final storage = body['storage'];
  if (storage is! Map || storage['value'] is! String) return;
  body.remove('export_view'); // large, redundant once Markdown is returned
  storage['value'] = confluenceStorageToMarkdown(storage['value'] as String);
  storage['representation'] = 'markdown';
}
