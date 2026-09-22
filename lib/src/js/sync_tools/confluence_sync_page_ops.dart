part of 'confluence_sync_tools.dart';

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
    final existing = _existingByName(
        contentId, file.uri.pathSegments.last);
    if (existing != null && !updateIfExists) {
      return {'status': 'skipped', 'attachment': existing};
    }
    return _uploadForPolicy(contentId, existing, file);
  }

  /// Upload tail shared by the create/update policy paths: picks the
  /// endpoint suffix (existing attachments PUT to their `/data` endpoint),
  /// POSTs the multipart body, and labels the outcome.
  Map<String, dynamic> _uploadForPolicy(
    String contentId,
    Map<String, dynamic>? existing,
    File file,
  ) {
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
    return {
      'status': existing != null ? 'updated' : 'created',
      'attachment': _uploadedAttachment(result.body),
    };
  }

  /// The attachment object of an upload response body (Java takes
  /// `results[0]` of the wrapper, else the decoded object itself).
  static Map<String, dynamic>? _uploadedAttachment(String body) {
    final decoded = syncTryDecode(body);
    if (decoded is Map && decoded['results'] is List) {
      return (decoded['results'] as List).firstOrNull;
    }
    return decoded is Map<String, dynamic> ? decoded : null;
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
