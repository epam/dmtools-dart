/// HTTP client for the GitHub REST API.
///
/// Ports the transport layer used by the Java DMTools GitHub integration:
/// Bearer-token auth assembled from `SOURCE_GITHUB_TOKEN`, the base URL from
/// `SOURCE_GITHUB_BASE_PATH` (default `https://api.github.com`), and the
/// `Accept`/`X-GitHub-Api-Version` headers GitHub recommends on every call.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level GitHub HTTP transport used by [GithubClient].
class GithubHttpClient extends BaseHttpClient {
  final String _token;

  /// Creates a client from [reader]'s GitHub configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
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
    return GithubHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      token: token,
    );
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
