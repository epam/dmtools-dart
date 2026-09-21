/// Rate-limit / transient-failure retry policy for the sync HTTP transport
/// (gh-191, P6-JSY-18).
///
/// Dart port of the Java `RetryPolicy` + `RetryPolicyConfig`
/// (`dmtools-core/.../networking/`), wired into `JiraClient.execute`:
/// exponential backoff with jitter, `Retry-After` and `X-RateLimit-Reset`
/// header honoring, and a connection-error schedule for transport failures.
///
/// Configuration (Java `RetryPolicyConfig` parity):
/// - Cloud instances (`JIRA_CLOUD=true` or an `atlassian.net` URL) get the
///   Cloud-tuned policy: 7 attempts, 2s base delay, 120s cap, 2.0 backoff,
///   0.4 jitter.
/// - Everything else reads the `JIRA_RETRY_*` environment: `MAX_ATTEMPTS`
///   (5), `BASE_DELAY_MS` (1000), `MAX_DELAY_MS` (60000),
///   `BACKOFF_MULTIPLIER` (2.0), `JITTER_FACTOR` (0.3), `ENABLED` (true).
/// - The per-perform throttle (Java `BasicJiraClient`): `JIRA_WAIT_BEFORE_
///   PERFORM` (bool, default false) sleeps `SLEEP_TIME_REQUEST`
///   milliseconds (default 300) before each request execution.
library;

import 'dart:io' show Platform;
import 'dart:math';

/// Immutable retry policy; all delay math is pure and testable.
class SyncRetryPolicy {
  /// Total attempt budget, mirroring Java `maxRetries` (the loop runs while
  /// `attemptNumber <= maxRetries`, so 0 disables retrying entirely).
  final int maxAttempts;

  /// First backoff delay in milliseconds.
  final int baseDelayMs;

  /// Delay cap in milliseconds.
  final int maxDelayMs;

  /// Exponential multiplier applied per attempt.
  final double backoffMultiplier;

  /// Jitter factor: the delay moves by up to `jitterFactor / 2` in either
  /// direction (Java `addJitter`).
  final double jitterFactor;

  /// Random source for jitter (injected in tests).
  final Random random;

  /// Java `isWaitBeforePerform`: throttle every perform (env
  /// `JIRA_WAIT_BEFORE_PERFORM`, default false).
  final bool waitBeforePerform;

  /// Java `sleepTimeRequest`: the throttle length in milliseconds (env
  /// `SLEEP_TIME_REQUEST`, default 300).
  final int sleepTimeRequestMs;

  /// Creates a policy with explicit settings.
  const SyncRetryPolicy({
    required this.maxAttempts,
    required this.baseDelayMs,
    required this.maxDelayMs,
    required this.backoffMultiplier,
    required this.jitterFactor,
    this.random = const _NeutralRandom(),
    this.waitBeforePerform = false,
    this.sleepTimeRequestMs = 300,
  });

  /// Milliseconds to sleep before each request execution (Java
  /// `AbstractRestClient` pre-loop throttle); `0` disables the throttle.
  int get performDelayMs => waitBeforePerform ? sleepTimeRequestMs : 0;

  /// Java `RetryPolicyConfig.forJiraCloud`: Atlassian-recommended Cloud
  /// tuning — more attempts, longer cap, wider jitter.
  factory SyncRetryPolicy.forJiraCloud([Random? random]) => SyncRetryPolicy(
        maxAttempts: 7,
        baseDelayMs: 2000,
        maxDelayMs: 120000,
        backoffMultiplier: 2.0,
        jitterFactor: 0.4,
        random: random ?? Random(),
      );

  /// Java `RetryPolicyConfig.fromEnvironment`; [get] resolves `JIRA_RETRY_*`
  /// values (defaults to `Platform.environment` when omitted).
  factory SyncRetryPolicy.fromEnvironment(
          [String? Function(String key)? get, Random? random]) =>
      SyncRetryPolicy.fromEnvMap(
        (key) => get?.call(key) ?? Platform.environment[key],
        random,
      );

  /// Java `RetryPolicyConfig` semantics over an explicit key/value lookup.
  factory SyncRetryPolicy.fromEnvMap(String? Function(String) get,
          [Random? random]) =>
      (get('JIRA_RETRY_ENABLED')?.toLowerCase() == 'false')
          ? const SyncRetryPolicy(
              maxAttempts: 0,
              baseDelayMs: 0,
              maxDelayMs: 0,
              backoffMultiplier: 1.0,
              jitterFactor: 0.0,
            )
          : SyncRetryPolicy(
              maxAttempts: _intEnv(get, 'JIRA_RETRY_MAX_ATTEMPTS', 5),
              baseDelayMs: _intEnv(get, 'JIRA_RETRY_BASE_DELAY_MS', 1000),
              maxDelayMs: _intEnv(get, 'JIRA_RETRY_MAX_DELAY_MS', 60000),
              backoffMultiplier:
                  _doubleEnv(get, 'JIRA_RETRY_BACKOFF_MULTIPLIER', 2.0),
              jitterFactor: _doubleEnv(get, 'JIRA_RETRY_JITTER_FACTOR', 0.3),
              waitBeforePerform:
                  get('JIRA_WAIT_BEFORE_PERFORM')?.toLowerCase() == 'true',
              sleepTimeRequestMs: _intEnv(get, 'SLEEP_TIME_REQUEST', 300),
              random: random ?? Random(),
            );

  /// Java `JiraClient` constructor logic: `JIRA_CLOUD=true` or an
  /// `atlassian.net` base path selects the Cloud policy, everything else
  /// the environment/default policy.
  factory SyncRetryPolicy.forUrl(
    String url, {
    String? Function(String key)? get,
    Random? random,
  }) {
    final cloud = get?.call('JIRA_CLOUD')?.toLowerCase() == 'true' ||
        url.contains('atlassian.net');
    return cloud
        ? SyncRetryPolicy.forJiraCloud(random)
        : SyncRetryPolicy.fromEnvironment(get, random);
  }

  /// Whether [status] is retryable — Java `RetryPolicy.isRetryable` maps
  /// rate-limit/transient messages onto exactly these codes (429, and the
  /// 502/503/504 gateway family).
  bool isRetryableStatus(int status) =>
      status == 429 || status == 502 || status == 503 || status == 504;

  /// Whether another attempt may be made after [attempt] (1-based) failed:
  /// Java retries while `attemptNumber < maxRetries`.
  bool canRetryAfter(int attempt) => attempt < maxAttempts;

  /// Whether a failed request at 1-based [attempt] with [statusCode]
  /// (`0` = transport failure) should be retried.
  bool shouldRetry(int attempt, int statusCode) {
    if (!canRetryAfter(attempt)) return false;
    if (statusCode == 0) return true;
    return isRetryableStatus(statusCode);
  }

  /// Delay before the next attempt after a retryable-status [attempt]
  /// (1-based), honoring `Retry-After` then `X-RateLimit-Reset` from
  /// [headers], then exponential backoff with jitter. Returns `null` when a
  /// `Retry-After` above the 300s cap demands an abort (Java throws).
  int? statusDelayMs(int attempt, [Map<String, String> headers = const {}]) {
    final serverDelay = _serverDelayMs(headers, DateTime.now());
    if (serverDelay == null) return null; // Retry-After over the cap: abort
    final base = serverDelay != 0
        ? serverDelay
        : min(
            maxDelayMs,
            (baseDelayMs * pow(backoffMultiplier, attempt - 1)).toInt(),
          );
    return _addJitter(base);
  }

  /// Java's connection-error schedule: `200 * 2^(attempt-1)` capped at 5s,
  /// no jitter.
  int connectionDelayMs(int attempt) =>
      min(5000, 200 * pow(2, attempt - 1).toInt());

  /// Server-mandated delay: `Retry-After` seconds (abort above 300s,
  /// surfaced as `null`), else `X-RateLimit-Reset` (unix seconds, +1s
  /// buffer, capped at [maxDelayMs]). Returns `0` when no server header
  /// applies.
  int? _serverDelayMs(Map<String, String> headers, DateTime now) {
    final retryAfter = _header(headers, 'retry-after');
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        if (seconds > 300) return null; // abort
        return _addJitter(seconds * 1000);
      }
    }
    final reset = _header(headers, 'x-ratelimit-reset');
    if (reset != null) {
      final resetMs = int.tryParse(reset);
      if (resetMs != null) {
        final delay = resetMs * 1000 - now.millisecondsSinceEpoch;
        if (delay > 0) return min(delay + 1000, maxDelayMs);
      }
    }
    return 0;
  }

  /// Case-insensitive [name] lookup over [headers].
  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  /// Java `addJitter`: shift by up to `jitterFactor / 2` of the delay.
  int _addJitter(int delay) {
    if (jitterFactor == 0 || delay == 0) return delay;
    final jitter = delay * jitterFactor * (random.nextDouble() - 0.5);
    return max(0, delay + jitter.toInt());
  }

  static int _intEnv(String? Function(String) get, String key, int fallback) =>
      int.tryParse(get(key) ?? '') ?? fallback;

  static double _doubleEnv(
          String? Function(String) get, String key, double fallback) =>
      double.tryParse(get(key) ?? '') ?? fallback;
}

/// Jitter-neutral [Random] used as the const default (always returns the
/// 0.5 midpoint so `addJitter` is a no-op); the factories override it with
/// a live `Random()`.
class _NeutralRandom implements Random {
  const _NeutralRandom();

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => 0;
}
