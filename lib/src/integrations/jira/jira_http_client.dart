/// HTTP client for the Jira REST API.
///
/// Ports Java `BasicJiraClient` + `JiraClient.sign()` + `JiraClient.path()`:
/// auth header assembly, per-endpoint URL routing (`/rest/api/latest`,
/// `/rest/api/3`), and the `X-Atlassian-Token: nocheck` CSRF header.
///
/// Auth resolution (via [PropertyReader]):
/// `JIRA_EMAIL` + `JIRA_API_TOKEN` → `base64(email:token)`, or
/// `JIRA_LOGIN_PASS_TOKEN` as-is. The Authorization scheme comes from
/// `JIRA_AUTH_TYPE` (default `Basic`; `Bearer` for Server/DC PATs).
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Jira HTTP transport used by [JiraClient].
class JiraHttpClient extends BaseHttpClient {
  final String _authHeader;

  /// Creates a client from [reader]'s Jira configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `JIRA_BASE_PATH` or any auth credential
  /// (`JIRA_EMAIL`+`JIRA_API_TOKEN` / `JIRA_LOGIN_PASS_TOKEN`) is missing.
  factory JiraHttpClient(PropertyReader reader, {Dio? dio}) {
    final token = reader.getJiraLoginPassToken();
    final authType = reader.getJiraAuthType() ?? 'Basic';
    final basePath = reader.getJiraBasePath();
    if (basePath == null || basePath.isEmpty) {
      throw StateError('JIRA_BASE_PATH is not configured');
    }
    if (token == null || token.isEmpty) {
      throw StateError(
        'Jira auth not configured '
        '(need JIRA_EMAIL+JIRA_API_TOKEN or JIRA_LOGIN_PASS_TOKEN)',
      );
    }
    return JiraHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      authHeader: '$authType $token',
    );
  }

  JiraHttpClient._({
    required super.dio,
    required super.basePath,
    required String authHeader,
  }) : _authHeader = authHeader;

  @override
  Map<String, String> get authHeaders => {
        'Authorization': _authHeader,
        'X-Atlassian-Token': 'nocheck',
      };

  @override
  String buildUrl(String path) => '$basePath/rest/api/latest/$path';

  /// Builds a `/rest/api/3/` URL for [path] (ADF field updates).
  String buildV3Url(String path) => '$basePath/rest/api/3/$path';

  /// Performs a GET against `/rest/api/3/` and returns the response body.
  Future<String> getV3(String path, {Map<String, String>? queryParams}) async {
    final response = await dio.get<String>(
      buildV3Url(path),
      queryParameters: queryParams,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }
}
