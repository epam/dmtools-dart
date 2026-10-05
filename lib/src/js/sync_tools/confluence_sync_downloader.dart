part of 'confluence_sync_tools.dart';

/// Depth-first page downloader: writes each page as Markdown and optionally
/// mirrors its attachments, then recurses into child pages down to
/// [depth] levels (Java `ConfluencePageDownloader`, limited to the child
/// graph).
class _PageDownloader {
  final _Conf _config;
  final Directory _output;
  final bool _downloadAttachments;
  final ConfluenceExcerptInliner _excerptInliner;
  final ConfluenceMentionResolver _mentionResolver;

  /// Creates a downloader writing under [_output]; the excerpt-include
  /// inliner and mention resolver reuse one HTTP-backed client (Java
  /// `ConfluencePageDownloader`, dm.ai 932e0db0 / bb1b51e9).
  _PageDownloader(this._config, this._output, this._downloadAttachments)
      : _excerptInliner = ConfluenceExcerptInliner(
          _SyncConfluenceResolverClient(_config),
        ),
        _mentionResolver = ConfluenceMentionResolver(
          _SyncConfluenceResolverClient(_config),
        );

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
      confluenceStorageToMarkdown(_resolvedBody(content, value)),
    );
    _written++;
    if (_downloadAttachments) _downloadAttachmentsOf(id, fileName);
    if (depth > 1) {
      // v1 child pages carry no body unless the request expands it —
      // without the expand param every child bails at the
      // `value is! String` guard below and the subtree is silently
      // dropped (gh-191 review). The v2 children listing always carries
      // bodies (body-format=storage is part of the request).
      for (final child in _childrenResults(
              syncBodyOrError(_childrenResponse(_config, id))) ??
          const <Map<String, dynamic>>[]) {
        _downloadPage(child, depth - 1);
      }
    }
  }

  /// The storage body with excerpt includes materialized (resolved in the
  /// page's own space when the include carries no space key) and user
  /// mentions replaced by `@Display Name` (Java `ConfluencePageDownloader`
  /// pipeline: `toMarkdown(mentionResolver.resolve(inliner.inline(…)))`).
  String _resolvedBody(Map<String, dynamic> content, String storage) {
    final inlined = _excerptInliner.inline(
      storage,
      confluenceSpaceKeyOf(content),
    );
    return _mentionResolver.resolve(inlined);
  }

  void _downloadAttachmentsOf(String contentId, String pageFolder) {
    final resp = _attachmentsResponse(_config, contentId);
    final results = _childrenResults(syncBodyOrError(resp)) ??
        const <Map<String, dynamic>>[];
    final baseHost = Uri.tryParse(_config.rootUrl)?.host;
    for (final attachment in results) {
      final downloadPath = _attachmentDownloadPath(attachment);
      if (downloadPath == null) continue;
      _downloadOneAttachment(attachment, downloadPath, baseHost, pageFolder);
    }
  }

  /// The `_links.download` path of [attachment]; `null` when absent or
  /// empty.
  static String? _attachmentDownloadPath(Map<String, dynamic> attachment) {
    final links = attachment['_links'];
    final downloadPath = links is Map ? links['download'] : null;
    return downloadPath is String && downloadPath.isNotEmpty
        ? downloadPath
        : null;
  }

  /// Fetches and writes one attachment next to its page.
  void _downloadOneAttachment(
    Map<String, dynamic> attachment,
    String downloadPath,
    String? baseHost,
    String pageFolder,
  ) {
    // `_links.download` is relative to the site root (`/download/…`).
    final url = downloadPath.startsWith('http')
        ? downloadPath
        : '${_config.rootUrl}$downloadPath';
    // `_links.download` is server-controlled content: the Confluence
    // credentials never travel to a foreign host.
    var headers = _config.headers;
    if (downloadPath.startsWith('http') &&
        Uri.tryParse(downloadPath)?.host != baseHost) {
      headers = {...headers}..removeWhere(
          (key, _) => key.toLowerCase() == HttpHeaders.authorizationHeader,
        );
    }
    final resp = SyncHttpClient.get(url, headers: headers);
    if (!resp.isOk) return;
    final dir = Directory('${_output.path}/$pageFolder-attachments')
      ..createSync(recursive: true);
    File('${dir.path}/${_sanitize(attachment['title']?.toString() ?? 'file')}')
        .writeAsBytesSync(resp.bodyBytes);
  }

  /// Filesystem-safe file name from a page title.
  static String _sanitize(String title) =>
      title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
}
