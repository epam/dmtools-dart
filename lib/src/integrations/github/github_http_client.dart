/// HTTP client for the GitHub REST API.
///
/// Ports the transport layer used by the Java DMTools GitHub integration:
/// Bearer-token auth assembled from `SOURCE_GITHUB_TOKEN`, the base URL from
/// `SOURCE_GITHUB_BASE_PATH` (default `https://api.github.com`), and the
/// `Accept`/`X-GitHub-Api-Version` headers GitHub recommends on every call.
library;

import 'dart:math';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../js/sync_retry_policy.dart';
import '../base_http_client.dart';
import '../github_rate_limit_retry.dart';

/// Low-level GitHub HTTP transport used by [GithubClient].
class GithubHttpClient extends BaseHttpClient {
  final String _token;

  /// Creates a client from [reader]'s GitHub configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts. Either way the
  /// transport gets a [GithubRateLimitRetryInterceptor] so GitHub 429
  /// rate-limit responses are retried after honoring the server-mandated
  /// wait (Java fix fab5b0ea, gh-351).
  ///
  /// Throws [StateError] when `SOURCE_GITHUB_TOKEN` is missing or empty.
  factory GithubHttpClient(PropertyReader reader, {Dio? dio}) {
    final token = reader.getGithubToken();
    final basePath = reader.getGithubBasePath();
    if (token == null || token.isEmpty) {
      throw StateError(
        'GitHub auth not configured (SOURCE_GITHUB_TOKEN is required)',
      );
    }
    final clientDio = dio ?? BaseHttpClient.createDefaultDio();
    clientDio.interceptors.add(GithubRateLimitRetryInterceptor(
      dio: clientDio,
      policy: SyncRetryPolicy(
        maxAttempts: GithubRateLimitRetryInterceptor.defaultMaxAttempts,
        baseDelayMs: 1000,
        maxDelayMs: 600,
        backoffMultiplier: 2.0,
        jitterFactor: 0.3,
        rateLimitMaxWaitSeconds: _rateLimitMaxWaitSeconds(reader),
        random: Random(),
      ),
    ));
    return GithubHttpClient._(
      dio: clientDio,
      basePath: basePath,
      token: token,
    );
  }

  /// Java `RetryPolicy.resolveRateLimitMaxWaitSeconds`: parses the
  /// `RATE_LIMIT_MAX_WAIT_SECONDS` property through [reader]'s resolution
  /// chain, falling back to [SyncRetryPolicy.defaultRateLimitMaxWaitSeconds]
  /// when unset, unparsable, or `<= 0`.
  static int _rateLimitMaxWaitSeconds(PropertyReader reader) {
    final value = (reader.getValue('RATE_LIMIT_MAX_WAIT_SECONDS') ?? '').trim();
    final parsed = int.tryParse(value);
    return (parsed != null && parsed > 0)
        ? parsed
        : SyncRetryPolicy.defaultRateLimitMaxWaitSeconds;
  }

  GithubHttpClient._({
    required super.dio,
    required super.basePath,
    required String token,
  }) : _token = token;

  @override
  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  @override
  String buildUrl(String path) => '$basePath/$path';
}
