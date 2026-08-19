/// HTTP client for the Confluence Cloud REST API.
///
/// Ports the Java `ConfluenceClient` transport layer: auth header assembly
/// and per-endpoint URL routing (`/wiki/rest/api`). Unlike Jira, Confluence
/// derives the Authorization scheme from `CONFLUENCE_AUTH_TYPE` — `Bearer`
/// sends the raw `CONFLUENCE_API_TOKEN` (PAT), while the default `Basic`
/// sends `base64(email:token)` — all resolved via [PropertyReader] getters.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Confluence HTTP transport used by [ConfluenceClient].
class ConfluenceHttpClient extends BaseHttpClient {
  final String _authValue;

  /// Creates a client from [reader]'s Confluence configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `CONFLUENCE_BASE_PATH` or any auth credential
  /// (`CONFLUENCE_EMAIL`+`CONFLUENCE_API_TOKEN` /
  /// `CONFLUENCE_LOGIN_PASS_TOKEN`) is missing.
  factory ConfluenceHttpClient(PropertyReader reader, {Dio? dio}) {
    final token = reader.getConfluenceLoginPassToken();
    final authType = reader.getConfluenceAuthType();
    final basePath = reader.getConfluenceBasePath();
    if (basePath == null || basePath.isEmpty) {
      throw StateError('CONFLUENCE_BASE_PATH is not configured');
    }
    if (token == null || token.isEmpty) {
      throw StateError(
        'Confluence auth not configured '
        '(need CONFLUENCE_EMAIL+CONFLUENCE_API_TOKEN '
        'or CONFLUENCE_LOGIN_PASS_TOKEN)',
      );
    }
    return ConfluenceHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      authValue: '$authType $token',
    );
  }

  ConfluenceHttpClient._({
    required super.dio,
    required super.basePath,
    required String authValue,
  }) : _authValue = authValue;

  @override
  Map<String, String> get authHeaders => {
        'Authorization': _authValue,
        'Accept': 'application/json',
      };

  /// Builds a REST URL under [basePath].
  ///
  /// By Java convention `CONFLUENCE_BASE_PATH` already contains the
  /// `/wiki` segment (e.g. `https://org.atlassian.net/wiki`); Java's
  /// `Confluence.java` builds `getBasePath() + "/rest/api/" + path`, so
  /// no `/wiki` is appended here.
  @override
  String buildUrl(String path) => '$basePath/rest/api/$path';
}
