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

/// Low-level Jira HTTP transport used by [JiraClient].
class JiraHttpClient {
  final Dio _dio;
  final String _basePath;
  final String _authorization;
  final String _authType;

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
      dio: dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 60),
            ),
          ),
      basePath: basePath,
      authorization: token,
      authType: authType,
    );
  }

  JiraHttpClient._({
    required Dio dio,
    required String basePath,
    required String authorization,
    required String authType,
  })  : _dio = dio,
        _basePath = basePath,
        _authorization = authorization,
        _authType = authType;

  /// Builds a `/rest/api/latest/` URL for [path].
  String buildUrl(String path) => '$_basePath/rest/api/latest/$path';

  /// Builds a `/rest/api/3/` URL for [path] (ADF field updates).
  String buildV3Url(String path) => '$_basePath/rest/api/3/$path';

  /// Returns the auth + content headers sent with every request.
  Map<String, String> get headers => {
        'Authorization': '$_authType $_authorization',
        'X-Atlassian-Token': 'nocheck',
        'Content-Type': 'application/json',
      };

  /// Performs a GET against `/rest/api/latest/` and returns the response body.
  Future<String> get(String path, {Map<String, String>? queryParams}) async {
    final response = await _dio.get<String>(
      buildUrl(path),
      queryParameters: queryParams,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a GET against `/rest/api/3/` and returns the response body.
  Future<String> getV3(String path, {Map<String, String>? queryParams}) async {
    final response = await _dio.get<String>(
      buildV3Url(path),
      queryParameters: queryParams,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a POST against `/rest/api/latest/` and returns the response body.
  Future<String> post(String path, {Object? body}) async {
    final response = await _dio.post<String>(
      buildUrl(path),
      data: body,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a PUT against `/rest/api/latest/` and returns the response body.
  Future<String> put(String path, {Object? body}) async {
    final response = await _dio.put<String>(
      buildUrl(path),
      data: body,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a DELETE against `/rest/api/latest/` and returns the body.
  Future<String> delete(String path) async {
    final response = await _dio.delete<String>(
      buildUrl(path),
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
