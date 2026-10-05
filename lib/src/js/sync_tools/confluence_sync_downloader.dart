part of 'confluence_sync_tools.dart';

/// Depth-first page downloader: writes each page as Markdown and
/// optionally mirrors its attachments, then recurses into child pages
/// down to [depth] levels (Java `ConfluencePageDownloader`, limited to
/// the child graph).
///
/// gh-348 (dm.ai d61a4abd / 8cbf550d parity):
/// - Seed URLs resolve concurrently (one `resolve` pool job each).
/// - Attachment work is collected during the page walk and drained
///   afterwards: listing fetches for all pages go out together, then
///   every attachment downloads concurrently with the transient-failure
///   retry schedule; results are written in listing order.
/// - A failed download never leaves a partial file behind.
class _PageDownloader {
  final _Conf _config;
  final Directory _output;
  final bool _downloadAttachments;

  /// Creates a downloader writing under [_output].
  _PageDownloader(this._config, this._output, this._downloadAttachments);

  int _written = 0;

  /// Pages whose attachments still need downloading (content id + the
  /// sanitized page title used as its folder name).
  final List<({String contentId, String pageFolder})> _attachmentPages =
      <({String contentId, String pageFolder})>[];

  /// Downloads every seed [urls] subtree; returns the pages written.
  int download(List<String> urls, int depth) {
    for (final content in _resolveSeeds(urls)) {
      if (content != null) _downloadPage(content, depth);
    }
    _downloadCollectedAttachments();
    return _written;
  }

  /// Resolves the non-empty seed [urls] to content objects concurrently
  /// (input order; `null` entries failed and are skipped like Java).
  List<Map<String, dynamic>?> _resolveSeeds(List<String> urls) {
    final candidates = <String>[
      for (final url in urls)
        if (url.trim().isNotEmpty) url,
    ];
    return _runConfluenceParallel(_resolveJobs(_config, candidates));
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
    if (_downloadAttachments) {
      _attachmentPages.add((contentId: id, pageFolder: fileName));
    }
    if (depth > 1) {
      // Child pages carry no body unless the request expands it — without
      // the expand param every child bails at the `value is! String` guard
      // below and the subtree is silently dropped (gh-191 review).
      final resp = _contentGet(
          _config, '$id/child/page?limit=100&expand=$_contentExpand');
      for (final child in _childrenResults(syncBodyOrError(resp)) ??
          const <Map<String, dynamic>>[]) {
        _downloadPage(child, depth - 1);
      }
    }
  }

  /// Drains [ _attachmentPages]: concurrent listing fetches, then
  /// concurrent attachment downloads, then ordered file writes.
  void _downloadCollectedAttachments() {
    if (_attachmentPages.isEmpty) return;
    final listings = _runConfluenceParallel(_listingJobs());
    final downloads = <SyncParallelJob>[];
    final targets = <_AttachmentTarget>[];
    for (var i = 0; i < listings.length; i++) {
      _collectAttachmentJobs(
          listings[i], _attachmentPages[i], downloads, targets);
    }
    final responses = _runConfluenceParallel(downloads);
    for (var i = 0; i < responses.length; i++) {
      _writeAttachment(responses[i], targets[i]);
    }
  }

  /// One listing GET per collected page, keyed by the page position.
  List<SyncParallelJob> _listingJobs() => <SyncParallelJob>[
        for (var i = 0; i < _attachmentPages.length; i++)
          SyncParallelJob(
            index: i,
            kind: _kJobHttpGet,
            args: <String, dynamic>{
              ..._jobArgsOf(_config),
              'url': '${_config.baseUrl}/content/'
                  '${_attachmentPages[i].contentId}/child/attachment',
            },
          ),
      ];

  /// Parses one page's listing [envelope] and appends a download job +
  /// write target per attachment carrying a `_links.download` path.
  void _collectAttachmentJobs(
    Map<String, dynamic>? envelope,
    ({String contentId, String pageFolder}) page,
    List<SyncParallelJob> downloads,
    List<_AttachmentTarget> targets,
  ) {
    final resp = _httpJobResponse(envelope);
    if (resp == null || !resp.isOk) return;
    final results = _childrenResults(resp.body) ??
        const <Map<String, dynamic>>[];
    final baseHost = Uri.tryParse(_config.rootUrl)?.host;
    for (final attachment in results) {
      final downloadPath = _attachmentDownloadPath(attachment);
      if (downloadPath == null) continue;
      downloads.add(SyncParallelJob(
        index: downloads.length,
        kind: _kJobAttachmentGet,
        args: <String, dynamic>{
          ..._jobArgsOf(_config),
          'url': _attachmentUrl(downloadPath, _config.rootUrl),
          'headers': _attachmentHeaders(downloadPath, baseHost),
        },
      ));
      targets.add((
        pageFolder: page.pageFolder,
        title: _sanitize(attachment['title']?.toString() ?? 'file'),
      ));
    }
  }

  /// Writes one downloaded attachment next to its page; drops partial
  /// files on failure (Java `RestClient.downloadFile` cleanup, 8cbf550d).
  void _writeAttachment(
    Map<String, dynamic>? envelope,
    _AttachmentTarget target,
  ) {
    final resp = _httpJobResponse(envelope);
    final file = _attachmentFile(target);
    if (resp == null || !resp.isOk) {
      // A leftover partial file would look "already downloaded" to the
      // next run — remove it (Java parity: truncate-then-fail cleanup).
      _deleteQuietly(file);
      return;
    }
    try {
      file.writeAsBytesSync(resp.bodyBytes, flush: true);
    } catch (_) {
      _deleteQuietly(file);
    }
  }

  /// The target file of one attachment inside its page's folder.
  File _attachmentFile(_AttachmentTarget target) {
    final dir = Directory('${_output.path}/${target.pageFolder}-attachments')
      ..createSync(recursive: true);
    return File('${dir.path}/${target.title}');
  }

  /// Best-effort [file] removal (partial-download cleanup).
  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Unremovable leftovers are logged by the caller's skip, not thrown.
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

  /// The fetch URL of an attachment: `_links.download` is relative to the
  /// site root (`/download/…`) unless it is already absolute.
  static String _attachmentUrl(String downloadPath, String rootUrl) =>
      downloadPath.startsWith('http') ? downloadPath : '$rootUrl$downloadPath';

  /// Headers for one attachment fetch. `_links.download` is
  /// server-controlled content: the Confluence credentials never travel
  /// to a foreign host.
  Map<String, String> _attachmentHeaders(
    String downloadPath,
    String? baseHost,
  ) {
    var headers = _config.headers;
    if (downloadPath.startsWith('http') &&
        Uri.tryParse(downloadPath)?.host != baseHost) {
      headers = {...headers}..removeWhere(
          (key, _) => key.toLowerCase() == HttpHeaders.authorizationHeader,
        );
    }
    return headers;
  }

  /// Filesystem-safe file name from a page title.
  static String _sanitize(String title) =>
      title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
}

/// Where one downloaded attachment lands: its page folder + file name.
typedef _AttachmentTarget = ({String pageFolder, String title});

/// Java `Confluence.ATTACHMENT_DOWNLOAD_ATTEMPTS` (dm.ai 8cbf550d):
/// total tries for one attachment download.
const confluenceAttachmentDownloadAttempts = 4;

/// Java `Confluence.ATTACHMENT_RETRY_BASE_DELAY_MS` (dm.ai 8cbf550d):
/// the backoff base; attempt `n` waits `base * 2^(n-1) + jitter(base/2)`.
const confluenceAttachmentRetryBaseDelayMs = 1000;

/// Java `Confluence.isTransientDownloadFailure` parity (dm.ai 8cbf550d):
/// 429/408, 5xx, and transport failures (`statusCode == 0` — any network
/// error surfaces as such in [SyncHttpResponse]) may succeed on retry;
/// other 4xx will not.
bool isConfluenceTransientAttachmentFailure(int statusCode) =>
    statusCode == 0 ||
    statusCode == 408 ||
    statusCode == 429 ||
    statusCode >= 500;

/// Downloads one attachment with the Java retry schedule (dm.ai
/// 8cbf550d): up to [confluenceAttachmentDownloadAttempts] tries, backing
/// off `baseDelayMs * 2^(attempt-1) + jitter(baseDelayMs / 2)` between
/// transient failures and giving up immediately on client errors.
///
/// [fetch], [sleepDelay], and [random] are injectable for tests. The
/// default transport ([SyncHttpClient.get]) applies its own retry policy
/// on top, so the schedules compose rather than conflict.
SyncHttpResponse fetchConfluenceAttachmentWithRetry(
  String url,
  Map<String, String> headers, {
  SyncHttpResponse Function(String url, Map<String, String> headers)? fetch,
  void Function(int delayMs)? sleepDelay,
  int baseDelayMs = confluenceAttachmentRetryBaseDelayMs,
  Random? random,
}) {
  final get = fetch ?? SyncHttpClient.get;
  final pause = sleepDelay ?? (ms) => sleep(Duration(milliseconds: ms));
  final rnd = random ?? Random();
  for (var attempt = 1; ; attempt++) {
    final resp = get(url, headers);
    if (resp.isOk ||
        !isConfluenceTransientAttachmentFailure(resp.statusCode) ||
        attempt >= confluenceAttachmentDownloadAttempts) {
      return resp;
    }
    final jitter = baseDelayMs < 2 ? 1 : rnd.nextInt(baseDelayMs ~/ 2);
    pause(baseDelayMs * (1 << (attempt - 1)) + jitter);
  }
}
