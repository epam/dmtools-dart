/// Rate-limit retry interceptor for the dio GitHub client (gh-351).
///
/// Dart port of the Java `RetryPolicy` rate-limit branches (Java fix
/// fab5b0ea, "honor GitHub X-RateLimit-Reset wait instead of capping at
/// 60s") onto the dio transport used by [GithubHttpClient]: on HTTP 429 the
/// interceptor reads `Retry-After` / `X-RateLimit-Reset`, waits until the
/// server-mandated reset time, and replays the request.
///
/// Semantics mirror the Java fix exactly:
/// - `X-RateLimit-Reset`: wait `(resetTime - now) + 1s` buffer, capped at
///   the configurable `RATE_LIMIT_MAX_WAIT_SECONDS` (default 3600s) —
///   never capped by `maxDelayMs` and never aborted.
/// - `Retry-After` on HTTP 429: honored up to the same rate-limit cap; the
///   300s abort is preserved only for non-rate-limit responses, which this
///   interceptor never handles.
/// - A 429 without either header falls back to the capped exponential
///   backoff of the underlying [SyncRetryPolicy].
library;

import 'dart:math';

import 'package:dio/dio.dart';

import '../js/sync_retry_policy.dart';

/// Retries GitHub API requests that fail with HTTP 429 after waiting for
/// the server-mandated rate-limit reset.
class GithubRateLimitRetryInterceptor extends Interceptor {
  /// Extra key counting retries already spent on a request (bounds the
  /// interceptor chain re-entry when the replayed request fails again).
  static const String _retryCountKey = 'dmtools.githubRateLimitRetry';

  /// Default total attempt budget (Java `RetryPolicy.DEFAULT_MAX_RETRIES`).
  static const int defaultMaxAttempts = 5;

  /// The retry policy carrying the delay math and the rate-limit cap.
  final SyncRetryPolicy policy;

  /// The dio instance the replayed request is dispatched through (the same
  /// instance this interceptor is attached to, so interceptors re-run).
  final Dio _dio;

  /// Total attempt budget: the original request plus at most
  /// `maxAttempts - 1` replays while the API keeps answering 429.
  final int maxAttempts;

  /// Sleep function executed before each replay (injected in tests).
  final Future<void> Function(Duration duration) _sleep;

  /// Creates the interceptor over [dio].
  ///
  /// [policy] defaults to the Java `new RetryPolicy(logger)` tuning
  /// (5 attempts, 1s base delay, 60s delay cap, 2.0 backoff, 0.3 jitter);
  /// [sleep] defaults to a real [Future.delayed].
  GithubRateLimitRetryInterceptor({
    required Dio dio,
    SyncRetryPolicy? policy,
    this.maxAttempts = defaultMaxAttempts,
    Future<void> Function(Duration duration)? sleep,
  })  : _dio = dio,
        policy = policy ??
            SyncRetryPolicy(
              maxAttempts: maxAttempts,
              baseDelayMs: 1000,
              maxDelayMs: 600,
              backoffMultiplier: 2.0,
              jitterFactor: 0.3,
              random: Random(),
            ),
        _sleep = sleep ?? ((duration) => Future.delayed(duration));

  /// Handles a failed request: only HTTP 429 responses are retried, after
  /// the server-mandated wait; everything else passes through untouched.
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final retriesUsed = (err.requestOptions.extra[_retryCountKey] as int?) ?? 0;
    if (response?.statusCode != 429 ||
        retriesUsed >= maxAttempts - 1 ||
        maxAttempts <= 1) {
      handler.next(err);
      return;
    }
    final delayMs = policy.statusDelayMs(
      retriesUsed + 1,
      _flattenHeaders(response!.headers),
      429,
    );
    if (delayMs == null) {
      handler.next(err); // Retry-After abort (unreachable for HTTP 429)
      return;
    }
    await _sleep(Duration(milliseconds: delayMs));
    err.requestOptions.extra[_retryCountKey] = retriesUsed + 1;
    try {
      handler.resolve(await _dio.fetch<String>(err.requestOptions));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Flattens dio's multi-value [headers] to the single-value map the
  /// policy's case-insensitive lookup expects.
  static Map<String, String> _flattenHeaders(Headers headers) => {
        for (final entry in headers.map.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.first,
      };
}
