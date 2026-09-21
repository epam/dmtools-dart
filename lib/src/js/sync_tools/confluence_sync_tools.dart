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
import '../../integrations/confluence/confluence_page_url.dart';
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
        'confluence_content_by_title': _contentByTitle,
        'confluence_content_by_title_and_space': _contentByTitleAndSpace,
        'confluence_contents_by_urls': _contentsByUrls,
        'confluence_download_pages': _downloadPages,
        'confluence_find_content': _findContent,
        'confluence_find_content_by_title_and_space':
            _findContentByTitleAndSpace,
        'confluence_find_or_create': _findOrCreate,
        'confluence_get_children_by_name': _getChildrenByName,
        'confluence_get_content_attachments': _getContentAttachments,
        'confluence_get_current_user_profile': _getCurrentUserProfile,
        'confluence_get_user_profile_by_id': _getUserProfileById,
        'confluence_search_content_by_text': _searchContentByText,
        'confluence_update_page_with_history': _updatePageWithHistory,
        'confluence_upload_attachment': _uploadAttachment,
        'confluence_upload_attachments': _uploadAttachments,
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
      rootUrl: basePath,
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

  /// `confluence_content_by_title` — GET `content?title=&expand=…` in the
  /// configured default space (Java `contentByTitleInDefaultSpace`).
  String _contentByTitle(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final space = _defaultSpace();
      if (space == null) return syncErr(_defaultSpaceRequired);
      return _titleAndSpaceContent(config, args, space);
    });
  }

  /// `confluence_content_by_title_and_space` — GET
  /// `content?title=&spaceKey=&expand=…` (Java `content`).
  String _contentByTitleAndSpace(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      return _titleAndSpaceContent(config, args, syncAsStr(args['space']));
    });
  }

  /// `confluence_find_content` — first match by title in the default space
  /// or JSON `null` (Java `findContentInDefaultSpace`).
  String _findContent(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final space = _defaultSpace();
      if (space == null) return syncErr(_defaultSpaceRequired);
      return _firstContent(config, args, space);
    });
  }

  /// `confluence_find_content_by_title_and_space` — first match by title in
  /// [ConfluenceSyncTools] space or JSON `null` (Java `findContent`).
  String _findContentByTitleAndSpace(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      return _firstContent(config, args, syncAsStr(args['space']));
    });
  }

  /// `confluence_find_or_create` — find by title in the default space or
  /// create under [parentId] (Java `findOrCreate`).
  String _findOrCreate(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final space = _defaultSpace();
      if (space == null) return syncErr(_defaultSpaceRequired);
      final existing = _contentList(
        _titleAndSpaceResponse(config, syncAsStr(args['title']), space),
      );
      if (existing.isNotEmpty) return jsonEncode(existing.first);
      return syncBodyOrError(SyncHttpClient.post(
        '${config.baseUrl}/content',
        headers: config.headers,
        body: jsonEncode(_pagePayload(args)..['space'] = {'key': space}),
      ));
    });
  }

  /// `confluence_get_children_by_name` — children of the page found by
  /// title in [spaceKey] (Java `getChildrenOfContentByName`).
  String _getChildrenByName(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final found = _contentList(_titleAndSpaceResponse(
        config,
        syncAsStr(args['contentName']),
        syncAsStr(args['spaceKey']),
      ));
      if (found.isEmpty) {
        return syncErr('Content not found: ${syncAsStr(args['contentName'])}');
      }
      final id = found.first['id']?.toString() ?? '';
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

  /// `confluence_get_content_attachments` — GET
  /// `content/{contentId}/child/attachment`, returning the `results` array.
  String _getContentAttachments(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final id = syncAsStr(args['contentId']);
      final resp = SyncHttpClient.get(
        '${config.baseUrl}/content/$id/child/attachment',
        headers: config.headers,
      );
      final results = _childrenResults(syncBodyOrError(resp));
      if (results == null) {
        return syncErr('Unexpected attachments response for $id');
      }
      return jsonEncode(results);
    });
  }

  /// `confluence_get_current_user_profile` — GET `user/current`.
  String _getCurrentUserProfile(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      return syncBodyOrError(SyncHttpClient.get(
        '${config.baseUrl}/user/current',
        headers: config.headers,
      ));
    });
  }

  /// `confluence_get_user_profile_by_id` — GET `user?accountId={userId}`.
  String _getUserProfileById(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      return syncBodyOrError(SyncHttpClient.get(
        '${config.baseUrl}/user?accountId=${syncAsStr(args['userId'])}',
        headers: config.headers,
      ));
    });
  }

  /// `confluence_search_content_by_text` — CQL `(title ~ … OR text ~ …)`
  /// search (Java `searchContentByText`; the GraphQL fast path is not
  /// ported — Dart always uses the REST search).
  String _searchContentByText(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final query = syncAsStr(args['query']);
      final limit = args['limit'] is num
          ? (args['limit'] as num).toInt()
          : (int.tryParse(syncAsStr(args['limit'])) ?? 20);
      final cql = Uri.encodeQueryComponent(
        '(title ~ "$query" OR text ~ "$query") ORDER BY lastModified ASC',
      );
      final resp = SyncHttpClient.get(
        '${config.baseUrl}/content/search?cql=$cql'
        '&limit=$limit'
        '&expand=${Uri.encodeQueryComponent(_searchExpand)}',
        headers: config.headers,
      );
      final body = syncBodyOrError(resp);
      final decoded = syncTryDecode(body);
      if (decoded is Map && decoded['results'] is List) {
        return jsonEncode(decoded['results']);
      }
      return body;
    });
  }

  /// `confluence_contents_by_urls` — resolve each URL to content, skipping
  /// failures like Java (`contentsByUrls`).
  String _contentsByUrls(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final urls = _stringList(args['urlStrings']);
      final contents = <Map<String, dynamic>>[];
      for (final url in urls) {
        if (url.isEmpty) continue;
        final content = _contentFromUrl(config, url);
        if (content != null) contents.add(content);
      }
      return jsonEncode(_applyFormatToList(contents, args['format']));
    });
  }

  /// `confluence_update_page_with_history` — like [ConfluenceSyncTools]
  /// update but the bumped version carries [historyComment] as its message
  /// (Java `confluence_update_page_with_history`).
  String _updatePageWithHistory(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final contentId = syncAsStr(args['contentId']);
      final version = _currentVersion(config, contentId);
      if (version == null) {
        return syncErr('Failed to fetch version for $contentId');
      }
      return syncBodyOrError(SyncHttpClient.put(
        '${config.baseUrl}/content/$contentId',
        headers: config.headers,
        body: jsonEncode(_updatePayload(
          args,
          contentId,
          version + 1,
          historyComment: syncAsStr(args['historyComment']),
        )),
      ));
    });
  }

  /// `confluence_upload_attachment` — multipart upload of one file with the
  /// skip-existing / overwrite policy (Java `AttachmentHelper`).
  String _uploadAttachment(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final file = File(syncAsStr(args['file']));
      if (!file.existsSync()) {
        return syncErr('File not found: ${file.path}');
      }
      final result = _SyncConfluenceAttachments(config).uploadWithPolicy(
        file,
        syncAsStr(args['contentId']),
        _flagOrFalse(args['updateIfExists']),
      );
      return jsonEncode(result);
    });
  }

  /// `confluence_upload_attachments` — upload every file in [directory]
  /// with the same policy; returns a JSON summary.
  String _uploadAttachments(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final dir = Directory(syncAsStr(args['directory']));
      if (!dir.existsSync()) {
        return syncErr('Directory not found: ${dir.path}');
      }
      final updateIfExists = _flagOrFalse(args['updateIfExists']);
      final helper = _SyncConfluenceAttachments(config);
      final uploaded = <String>[];
      final skipped = <String>[];
      final failed = <String>[];
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        try {
          final result = helper.uploadWithPolicy(
            entry,
            syncAsStr(args['contentId']),
            updateIfExists,
          );
          final bucket = result['status'] == 'skipped'
              ? skipped
              : result['status'] == 'failed'
                  ? failed
                  : uploaded;
          bucket.add(entry.uri.pathSegments.last);
        } on StateError {
          failed.add(entry.uri.pathSegments.last);
        }
      }
      return jsonEncode({
        'uploaded': uploaded,
        'skipped': skipped,
        'failed': failed,
      });
    });
  }

  /// `confluence_download_pages` — download pages (+ attachments) reached
  /// from [urlStrings] up to [depth] child-page levels, converted to
  /// Markdown (Java `ConfluencePageDownloader`; link-graph walking is
  /// limited to child pages).
  String _downloadPages(Map<String, dynamic> args) {
    return syncWithConfig(_config(), _notConfiguredError, (config) {
      final urls = _stringList(args['urlStrings']);
      final outputPath = syncAsStr(args['outputPath']);
      final depth = args['depth'] is num
          ? (args['depth'] as num).toInt()
          : (int.tryParse(syncAsStr(args['depth'])) ?? 1);
      final downloadAttachments = args['downloadAttachments'] == null ||
          args['downloadAttachments'] == true ||
          args['downloadAttachments'] == 'true';
      final downloader = _PageDownloader(
        config,
        Directory(outputPath),
        downloadAttachments,
      );
      final written = downloader.download(urls, depth);
      return 'Downloaded $written Confluence page(s) to $outputPath';
    });
  }

  /// The `CONFLUENCE_DEFAULT_SPACE` config value; `null` when unset.
  String? _defaultSpace() => _reader.getConfluenceDefaultSpace();

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
    int version, {
    String historyComment = '',
  }) =>
      _contentPayload(
        id: contentId,
        title: syncAsStr(args['title']),
        parentId: syncAsStr(args['parentId']),
        body: syncAsStr(args['body']),
        space: syncAsStr(args['space']),
        version: {
          'number': version,
          if (historyComment.isNotEmpty) 'message': historyComment,
        },
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

  /// Uploads [file] applying the Java `AttachmentHelper` policy: an
  /// existing attachment is skipped unless [updateIfExists], in which case
  /// the upload posts to the existing attachment's `/data` endpoint.
  ///
  /// Returns `{"status": "created"|"updated"|"skipped"|"failed",
  /// "attachment": <object?>}`.
  Map<String, dynamic> uploadWithPolicy(
    File file,
    String contentId,
    bool updateIfExists,
  ) {
    final name = file.uri.pathSegments.last;
    final existing = _existingByName(contentId, name);
    if (existing != null && !updateIfExists) {
      return {'status': 'skipped', 'attachment': existing};
    }
    final suffix = existing != null
        ? '/child/attachment/${existing['id']}/data'
        : '/child/attachment';
    final result = _multipartPost(
      '${_config.baseUrl}/content/$contentId$suffix',
      file,
    );
    if (result.statusCode == 0 || !result.isOk) {
      return {'status': 'failed', 'attachment': null};
    }
    final decoded = syncTryDecode(result.body);
    final attachment = decoded is Map && decoded['results'] is List
        ? (decoded['results'] as List).firstOrNull
        : decoded is Map<String, dynamic>
            ? decoded
            : null;
    return {
      'status': existing != null ? 'updated' : 'created',
      'attachment': attachment,
    };
  }

  /// The existing attachment object with [name] on [contentId], if any.
  Map<String, dynamic>? _existingByName(String contentId, String name) {
    final resp = SyncHttpClient.get(
      '${_config.baseUrl}/content/$contentId/child/attachment',
      headers: _config.headers,
    );
    if (!resp.isOk) return null;
    final results = _childrenResults(resp.body) ?? const [];
    for (final attachment in results) {
      if (attachment['title'] == name) return attachment;
    }
    return null;
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

/// Resolved sync integration config: root site URL, REST base URL, auth
/// headers.
typedef _Conf = ({
  String rootUrl,
  String baseUrl,
  Map<String, String> headers,
});

/// Error payload returned when Confluence config is incomplete.
const _notConfiguredError = 'Confluence not configured';

/// The Java `contentById` expand list (full storage, export view,
/// ancestors, and version).
const _contentExpand = 'body.storage,body.export_view,ancestors,version';

/// The Java `searchContentByText` expand list.
const _searchExpand = 'title,body.excerpt,history,space,body.storage';

/// Error when a default-space tool runs without `CONFLUENCE_DEFAULT_SPACE`
/// (Java `IllegalStateException`).
const _defaultSpaceRequired = 'Default space not set';

/// GETs `content?expand=…&title=…[&spaceKey=…]` (Java `content(title,
/// space)`; the spaceKey param is dropped for an empty space).
SyncHttpResponse _titleAndSpaceResponse(
  _Conf config,
  String title,
  String space,
) =>
    SyncHttpClient.get(
      '${config.baseUrl}/content?expand=${Uri.encodeQueryComponent(_contentExpand)}'
      '&title=${Uri.encodeQueryComponent(title)}'
      '${space.isEmpty ? '' : '&spaceKey=${Uri.encodeQueryComponent(space)}'}',
      headers: config.headers,
    );

/// The content objects of a title/space listing.
List<Map<String, dynamic>> _contentList(SyncHttpResponse resp) {
  final decoded = syncTryDecode(syncBodyOrError(resp));
  final results = decoded is Map ? decoded['results'] : decoded;
  if (results is! List) return const [];
  return results
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList(growable: false);
}

/// Runs the Java `applyFormat` contract over the `confluence_content…`
/// listing: converts each result's storage body when [format] asks for
/// Markdown and returns the re-encoded JSON.
String _titleAndSpaceContent(
        _Conf config, Map<String, dynamic> args, String space) =>
    jsonEncode(_applyFormatToList(
      _contentList(
        _titleAndSpaceResponse(config, syncAsStr(args['title']), space),
      ),
      args['format'],
    ));

/// The first content of a title/space listing, JSON `null` when none.
String _firstContent(
  _Conf config,
  Map<String, dynamic> args,
  String space,
) {
  final list = _applyFormatToList(
    _contentList(
      _titleAndSpaceResponse(config, syncAsStr(args['title']), space),
    ),
    args['format'],
  );
  return jsonEncode(list.isEmpty ? null : list.first);
}

/// Applies the Java `applyFormat` contract to a content list, in place.
List<Map<String, dynamic>> _applyFormatToList(
  List<Map<String, dynamic>> contents,
  dynamic format,
) {
  if (_isMarkdownFormat(format)) {
    for (final content in contents) {
      _convertStorageToMarkdown(content);
    }
  }
  return contents;
}

/// Coerces an array-ish arg into a string list.
List<String> _stringList(dynamic value) {
  if (value is List) return value.map(syncAsStr).toList();
  final single = syncAsStr(value);
  return single.isEmpty ? const [] : [single];
}

/// Reads a boolean flag that may arrive as bool or string.
bool _flagOrFalse(dynamic value) =>
    value == true || value == 'true' || value == 'True';

/// Resolves [urlString] to its content object (Java `contentByUrl`), or
/// `null` when the URL is malformed or the fetch fails.
Map<String, dynamic>? _contentFromUrl(_Conf config, String urlString) {
  final uri = Uri.tryParse(urlString);
  if (uri == null) return null;
  var ref = resolveConfluencePageUrl(uri);
  // The redirect follower tracks the *current* URL: each hop GETs the
  // Location resolved by the previous hop, never the original input.
  var current = urlString;
  for (var hops = 0; hops < 5; hops++) {
    if (ref is! ConfluenceRedirectRef) break;
    // Short link: follow the 3xx Location (curl never follows redirects).
    final resp = SyncHttpClient.get(current, headers: config.headers);
    final location = resp.headers.entries
        .where((e) => e.key.toLowerCase() == 'location')
        .map((e) => e.value)
        .firstOrNull;
    if (location == null || !resp.isRedirect) return null;
    final next = Uri.tryParse(location);
    if (next == null) return null;
    current = location;
    ref = resolveConfluencePageUrl(next);
  }
  if (ref is ConfluencePageIdRef) {
    final decoded = syncTryDecode(syncBodyOrError(_contentGet(
      config,
      '${ref.id}?expand=$_contentExpand',
    )));
    return decoded is Map<String, dynamic> ? decoded : null;
  }
  if (ref is ConfluenceDisplayRef) {
    final list = _contentList(
      _titleAndSpaceResponse(config, ref.title, ref.space),
    );
    return list.isEmpty ? null : list.first;
  }
  return null;
}

/// Depth-first page downloader: writes each page as Markdown and optionally
/// mirrors its attachments, then recurses into child pages down to
/// [depth] levels (Java `ConfluencePageDownloader`, limited to the child
/// graph).
class _PageDownloader {
  final _Conf _config;
  final Directory _output;
  final bool _downloadAttachments;

  /// Creates a downloader writing under [_output].
  _PageDownloader(this._config, this._output, this._downloadAttachments);

  int _written = 0;

  /// Downloads every seed [urls] subtree; returns the pages written.
  int download(List<String> urls, int depth) {
    for (final url in urls) {
      final content = _contentFromUrl(_config, url);
      if (content == null) continue;
      _downloadPage(content, depth);
    }
    return _written;
  }

  void _downloadPage(Map<String, dynamic> content, int depth) {
    final id = content['id']?.toString();
    if (id == null || id.isEmpty) return;
    final body = content['body'];
    final storage =
        body is Map ? body['storage'] as Map<String, dynamic>? : null;
    final value = storage?['value'];
    if (value is! String) return;
    _output.createSync(recursive: true);
    final fileName = _sanitize(content['title']?.toString() ?? id);
    File('${_output.path}/$fileName.md').writeAsStringSync(
      confluenceStorageToMarkdown(value),
    );
    _written++;
    if (_downloadAttachments) _downloadAttachmentsOf(id, fileName);
    if (depth > 1) {
      // Child pages carry no body unless the request expands it — without
      // the expand param every child bails at the `value is! String` guard
      // below and the subtree is silently dropped (gh-191 review).
      final resp =
          _contentGet(_config, '$id/child/page?limit=100&expand=$_contentExpand');
      for (final child in _childrenResults(syncBodyOrError(resp)) ??
          const <Map<String, dynamic>>[]) {
        _downloadPage(child, depth - 1);
      }
    }
  }

  void _downloadAttachmentsOf(String contentId, String pageFolder) {
    final resp = SyncHttpClient.get(
      '${_config.baseUrl}/content/$contentId/child/attachment',
      headers: _config.headers,
    );
    final results = _childrenResults(syncBodyOrError(resp)) ??
        const <Map<String, dynamic>>[];
    for (final attachment in results) {
      final links = attachment['_links'];
      final downloadPath = links is Map ? links['download'] : null;
      if (downloadPath is! String || downloadPath.isEmpty) continue;
      // `_links.download` is relative to the site root (`/download/…`).
      final url = downloadPath.startsWith('http')
          ? downloadPath
          : '${_config.rootUrl}$downloadPath';
      final resp = SyncHttpClient.get(url, headers: _config.headers);
      if (!resp.isOk) continue;
      final dir = Directory('${_output.path}/$pageFolder-attachments')
        ..createSync(recursive: true);
      File('${dir.path}/${_sanitize(attachment['title']?.toString() ?? 'file')}')
          .writeAsBytesSync(resp.bodyBytes);
    }
  }

  /// Filesystem-safe file name from a page title.
  static String _sanitize(String title) =>
      title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
}

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
