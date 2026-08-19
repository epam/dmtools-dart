/// HTTP client for the GitLab REST API.
///
/// Auth uses the `PRIVATE-TOKEN` header resolved from `GITLAB_TOKEN` via
/// [PropertyReader]. All endpoints live under `/api/v4/`, routed through
/// the configured `GITLAB_BASE_PATH` (e.g. `https://gitlab.example.com`).
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level GitLab HTTP transport used by [GitlabClient].
class GitlabHttpClient extends BaseHttpClient {
  final String _token;

  /// Creates a client from [reader]'s GitLab configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `GITLAB_BASE_PATH` or `GITLAB_TOKEN` is missing.
  factory GitlabHttpClient(PropertyReader reader, {Dio? dio}) {
    final basePath = reader.getGitLabBasePath();
    final token = reader.getGitLabToken();
    if (basePath == null || basePath.isEmpty) {
      throw StateError('GITLAB_BASE_PATH is not configured');
    }
    if (token == null || token.isEmpty) {
      throw StateError('GITLAB_TOKEN is not configured');
    }
    return GitlabHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      token: token,
    );
  }

  GitlabHttpClient._({
    required super.dio,
    required super.basePath,
    required String token,
  }) : _token = token;

  @override
  Map<String, String> get authHeaders => {
        'PRIVATE-TOKEN': _token,
      };

  @override
  String buildUrl(String path) => '$basePath/api/v4/$path';
}
