part of 'confluence_client.dart';

/// Upload/download transfer methods of [ConfluenceClient] (the Java
/// `ConfluenceAttachmentHelper` + `ConfluencePageDownloader` surface).
extension ConfluenceTransfer on ConfluenceClient {
  /// `confluence_upload_attachment` — multipart upload of one file with the
  /// skip-existing / overwrite policy (Java `AttachmentHelper`).
  ///
  /// Returns `{status: created|updated|skipped|failed, attachment: …}`.
  Future<Map<String, dynamic>> uploadAttachment(
    String contentId,
    String filePath, [
    bool updateIfExists = false,
  ]) async {
    final file = File(filePath);
    final name = file.uri.pathSegments.last;
    final existing = await _attachmentByName(contentId, name);
    if (existing != null && !updateIfExists) {
      return {'status': 'skipped', 'attachment': existing};
    }
    final pathSuffix = existing != null
        ? 'content/$contentId/child/attachment/${existing['id']}/data'
        : 'content/$contentId/child/attachment';
    try {
      final body = await _http.dio.post<dynamic>(
        _http.buildUrl(pathSuffix),
        data: FormData.fromMap(<String, dynamic>{
          'file': await MultipartFile.fromFile(filePath, filename: name),
        }),
        options: Options(headers: {
          ..._http.authHeaders,
          'X-Atlassian-Token': 'nocheck',
        }),
      );
      final decoded = _decodeDioBody(body.data);
      final attachment = decoded?['results'] is List
          ? (decoded!['results'] as List).firstOrNull
          : decoded;
      return {
        'status': existing != null ? 'updated' : 'created',
        'attachment': attachment,
      };
    } on DioException {
      return {'status': 'failed', 'attachment': null};
    }
  }

  /// `confluence_upload_attachments` — upload every file in [directory]
  /// with the same policy; returns a JSON summary.
  Future<Map<String, dynamic>> uploadAttachments(
    String contentId,
    String directory, [
    bool updateIfExists = false,
  ]) async {
    final uploaded = <String>[];
    final skipped = <String>[];
    final failed = <String>[];
    for (final entry in Directory(directory).listSync()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final result = await uploadAttachment(
        contentId,
        entry.path,
        updateIfExists,
      );
      (switch (result['status']) {
        'created' || 'updated' => uploaded,
        'skipped' => skipped,
        _ => failed,
      })
          .add(name);
    }
    return {'uploaded': uploaded, 'skipped': skipped, 'failed': failed};
  }

  /// `confluence_download_pages` — downloads pages (+ attachments) reached
  /// from [urlStrings] up to [depth] child-page levels, converted to
  /// Markdown (Java `ConfluencePageDownloader`; the link-graph walk is
  /// limited to child pages). Returns the Java summary line.
  Future<String> downloadPages(
    List<String> urlStrings,
    String outputPath, [
    int depth = 1,
    bool downloadAttachments = true,
  ]) async {
    var written = 0;
    for (final url in urlStrings) {
      final content = await contentByUrl(url);
      if (content == null) continue;
      written += await _downloadPageTree(
          content, Directory(outputPath), depth, downloadAttachments);
    }
    return 'Downloaded $written Confluence page(s) to $outputPath';
  }

  /// Recursively writes [content] and its child-page subtree, returning
  /// the number of pages written.
  Future<int> _downloadPageTree(
    Map<String, dynamic> content,
    Directory output,
    int depth,
    bool downloadAttachments,
  ) async {
    final id = content['id']?.toString();
    if (id == null || id.isEmpty) return 0;
    final body = content['body'];
    final storage = body is Map ? body['storage'] as Map? : null;
    final value = storage?['value'];
    if (value is! String) return 0;
    output.createSync(recursive: true);
    final fileName =
        ConfluenceClient._sanitizeFileName(content['title']?.toString() ?? id);
    File('${output.path}/$fileName.md')
        .writeAsStringSync(confluenceStorageToMarkdown(value));
    var written = 1;
    if (downloadAttachments) {
      await _downloadAttachmentsOf(id, output, fileName);
    }
    if (depth > 1) {
      for (final child in await _getChildrenWithBody(id)) {
        written += await _downloadPageTree(
            child, output, depth - 1, downloadAttachments);
      }
    }
    return written;
  }

  /// Child pages fetched with `expand=body.storage` (the downloader needs
  /// each child's storage body; plain `getContentChildren` omits bodies,
  /// which made every child bail before being written — gh-191 review).
  Future<List<Map<String, dynamic>>> _getChildrenWithBody(String id) async {
    final body = await _http.get(
      'content/$id/child/page',
      queryParams: const {
        'limit': '100',
        'expand': 'body.storage,body.export_view,ancestors,version',
      },
    );
    final decoded = jsonDecode(body);
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }

  /// Mirrors the attachments of [contentId] into `output/{page}-attachments`.
  Future<void> _downloadAttachmentsOf(
    String contentId,
    Directory output,
    String pageFolder,
  ) async {
    for (final attachment in await getPageAttachments(contentId)) {
      final links = attachment['_links'];
      final downloadPath = links is Map ? links['download'] : null;
      if (downloadPath is! String || downloadPath.isEmpty) continue;
      await _downloadOneAttachment(
          attachment, downloadPath, output, pageFolder);
    }
  }

  /// Fetches and writes one attachment next to its page. `_links.download`
  /// is server-controlled content: the Confluence credentials never travel
  /// to a foreign host.
  Future<void> _downloadOneAttachment(
    Map<String, dynamic> attachment,
    String downloadPath,
    Directory output,
    String pageFolder,
  ) async {
    // `_links.download` is relative to the wiki base (`/wiki/download/…`
    // on Cloud): Java concatenates basePath + link, so the `/wiki`
    // segment survives.
    final uri = downloadPath.startsWith('http')
        ? Uri.tryParse(downloadPath)
        : Uri.tryParse('${_http.basePath}$downloadPath');
    if (uri == null) return;
    final baseHost = Uri.tryParse(_http.basePath)?.host;
    final headers = {..._http.headers};
    if (downloadPath.startsWith('http') && uri.host != baseHost) {
      headers.removeWhere(
        (key, _) => key.toLowerCase() == HttpHeaders.authorizationHeader,
      );
    }
    try {
      final response = await _http.dio.get<List<int>>(
        '$uri',
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
        ),
      );
      final bytes = response.data;
      if (bytes == null) return;
      final dir = Directory('${output.path}/$pageFolder-attachments')
        ..createSync(recursive: true);
      File(
        '${dir.path}/'
        '${ConfluenceClient._sanitizeFileName(attachment['title']?.toString() ?? 'file')}',
      ).writeAsBytesSync(bytes);
    } on DioException {
      return; // one dead attachment never aborts the page download
    }
  }

  /// The existing attachment object with [name] on [contentId], if any.
  Future<Map<String, dynamic>?> _attachmentByName(
    String contentId,
    String name,
  ) async {
    for (final attachment in await getPageAttachments(contentId)) {
      if (attachment['title'] == name) return attachment;
    }
    return null;
  }
}
