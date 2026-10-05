part of 'confluence_sync_tools.dart';

/// Parallel Confluence execution over [SyncWorkerPool] (gh-348 — Java
/// `ConfluenceParallel` + `ConfluencePageDownloader` perf/robustness
/// ports, dm.ai d61a4abd / 8cbf550d).
///
/// Job kinds served by [_runConfluenceJob] in every pool worker (and on
/// the calling isolate as the inline fallback when the pool is not
/// booted):
/// - [_kJobResolve] — one `contentByUrl` resolution (redirect hops
///   included) for a single URL;
/// - [_kJobHttpGet] — one plain GET (attachment listings);
/// - [_kJobAttachmentGet] — one attachment download with the transient
///   retry schedule ([fetchConfluenceAttachmentWithRetry]).
///
/// Results travel as sendable maps; HTTP responses are wrapped by
/// [_httpJobEnvelope] and rebuilt by [_httpJobResponse].

/// Registry name of the Confluence pool runner.
const _kConfluenceRunnerName = 'confluence';

/// Job kind: resolve one page URL to its content object.
const _kJobResolve = 'resolve';

/// Job kind: one plain GET (attachment listings).
const _kJobHttpGet = 'http-get';

/// Job kind: one attachment download with transient-failure retry.
const _kJobAttachmentGet = 'attachment-get';

/// Java `ConfluenceParallel.DEFAULT_PARALLELISM` (dm.ai d61a4abd).
const _defaultConfluenceParallelism = 4;

/// Java `ConfluenceParallel.MAX_PARALLELISM` (dm.ai d61a4abd).
const _maxConfluenceParallelism = 16;

/// The shared Confluence pool; boots at CLI startup next to
/// `SyncHttpBridge.shared.boot()` (both must complete while the event
/// loop is alive).
final SyncWorkerPool _confluenceSyncPool = _createConfluencePool();

SyncWorkerPool _createConfluencePool() {
  registerSyncWorkerRunner(_kConfluenceRunnerName, _runConfluenceJob);
  return SyncWorkerPool(
    _kConfluenceRunnerName,
    name: 'confluence-parallel',
    workerCount: confluenceSyncParallelism(),
  );
}

/// The shared Confluence parallel worker pool (gh-348).
///
/// Booted by the CLI before any JS runs; when unbooted (tests, embedded
/// use) every parallel call falls back to inline sequential execution
/// with identical semantics.
SyncWorkerPool get confluenceSyncWorkerPool => _confluenceSyncPool;

/// Java `ConfluenceParallel.parallelism()` parity (dm.ai d61a4abd):
/// the `CONFLUENCE_PARALLELISM` config value clamped to
/// `[1, _maxConfluenceParallelism]`, defaulting to 4 when unset or
/// unparsable.
int confluenceSyncParallelism([PropertyReader? reader]) {
  final raw = (reader ?? PropertyReader()).getValue('CONFLUENCE_PARALLELISM');
  final parsed = int.tryParse((raw ?? '').trim());
  if (parsed == null) return _defaultConfluenceParallelism;
  if (parsed < 1) return 1;
  if (parsed > _maxConfluenceParallelism) return _maxConfluenceParallelism;
  return parsed;
}

/// The Confluence pool runner ([SyncWorkerRunner]): executes one job by
/// [kind]. Never throws — a failed job reports `null` (Java parity: a
/// failing task yields null instead of aborting the others).
Map<String, dynamic>? _runConfluenceJob(
  String kind,
  Map<String, dynamic> args,
) {
  switch (kind) {
    case _kJobHttpGet:
      return _httpJobEnvelope(SyncHttpClient.get(
        args['url'] as String,
        headers: _argsHeaders(args),
        followRedirects: args['followRedirects'] == true,
      ));
    case _kJobAttachmentGet:
      return _httpJobEnvelope(fetchConfluenceAttachmentWithRetry(
        args['url'] as String,
        _argsHeaders(args),
        baseDelayMs:
            args['baseDelayMs'] as int? ?? confluenceAttachmentRetryBaseDelayMs,
      ));
    case _kJobResolve:
      return _resolveContentJob(args);
    default:
      return null;
  }
}

/// The `resolve` job body: rebuilds the resolved config worker-side and
/// runs the Java `contentByUrl` resolution for one URL; `null` on any
/// failure (the caller skips it like Java's warn + continue).
Map<String, dynamic>? _resolveContentJob(Map<String, dynamic> args) {
  final config = (
    rootUrl: args['rootUrl'] as String,
    baseUrl: args['baseUrl'] as String,
    headers: _argsHeaders(args),
    apiVersion: '${args['apiVersion']}',
    attachmentRetryBaseDelayMs:
        args['baseDelayMs'] as int? ?? confluenceAttachmentRetryBaseDelayMs,
  );
  try {
    return _contentFromUrl(config, args['url'] as String);
  } catch (_) {
    return null;
  }
}

/// One `resolve` job per URL of [urls]; results keep the input order.
List<SyncParallelJob> _resolveJobs(_Conf config, List<String> urls) => [
      for (var i = 0; i < urls.length; i++)
        SyncParallelJob(
          index: i,
          kind: _kJobResolve,
          args: {..._jobArgsOf(config), 'url': urls[i]},
        ),
    ];

/// The sendable config fields shared by every Confluence job.
Map<String, dynamic> _jobArgsOf(_Conf config) => <String, dynamic>{
      'rootUrl': config.rootUrl,
      'baseUrl': config.baseUrl,
      'headers': config.headers,
      'apiVersion': config.apiVersion,
      'baseDelayMs': config.attachmentRetryBaseDelayMs,
    };

/// String map coercion of a job's `headers` argument.
Map<String, String> _argsHeaders(Map<String, dynamic> args) =>
    (args['headers'] as Map).map((k, v) => MapEntry('$k', '$v'));

/// Wraps a sync HTTP response into a sendable job-result map.
Map<String, dynamic> _httpJobEnvelope(SyncHttpResponse resp) =>
    <String, dynamic>{
      'status': resp.statusCode,
      'headers': resp.headers,
      'body': base64Encode(resp.bodyBytes),
    };

/// Rebuilds the response wrapped by [_httpJobEnvelope]; `null` when the
/// job failed.
SyncHttpResponse? _httpJobResponse(Map<String, dynamic>? envelope) {
  if (envelope == null) return null;
  return SyncHttpResponse(
    envelope['status'] as int,
    '',
    (envelope['headers'] as Map).map((k, v) => MapEntry('$k', '$v')),
    base64Decode(envelope['body'] as String),
  );
}

/// Runs [jobs] on the Confluence pool, or inline — in input order, one
/// at a time on the calling isolate — when the pool is not booted.
List<Map<String, dynamic>?> _runConfluenceParallel(
  List<SyncParallelJob> jobs,
) {
  final pool = confluenceSyncWorkerPool;
  if (pool.ready) return pool.run(jobs);
  return <Map<String, dynamic>?>[for (final job in jobs) _runJobInline(job)];
}

/// Executes one job on the calling isolate with pool-failure semantics
/// (any throw degrades to `null`).
Map<String, dynamic>? _runJobInline(SyncParallelJob job) {
  try {
    return _runConfluenceJob(job.kind, job.args);
  } catch (_) {
    return null;
  }
}
