/// HTTP client for the Atlassian Rovo remote MCP endpoint.
///
/// Ports the transport layer used by the Java DMTools `RovoMcpClient`:
/// Basic (`base64(email:api_token)`) or Bearer token auth assembled from
/// `ROVO_EMAIL` + `ROVO_API_TOKEN` or `ROVO_LOGIN_PASS_TOKEN`, and the remote
/// MCP endpoint URL from `ROVO_MCP_URL` (default
/// `https://mcp.atlassian.com/v2/mcp`).
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Default Atlassian Rovo remote MCP URL.
const String rovoDefaultMcpUrl = 'https://mcp.atlassian.com/v2/mcp';

/// Low-level Rovo HTTP transport used by [RovoClient].
class RovoHttpClient extends BaseHttpClient {
  final String _authValue;

  /// Optional default Atlassian Cloud ID configured via `ROVO_CLOUD_ID`.
  final String? defaultCloudId;

  /// Creates a client from [reader]'s Rovo configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when Rovo authentication credentials are missing.
  factory RovoHttpClient(PropertyReader reader, {Dio? dio}) {
    final token = reader.getRovoLoginPassToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError(
        'Rovo auth not configured '
        '(need ROVO_LOGIN_PASS_TOKEN or ROVO_EMAIL+ROVO_API_TOKEN)',
      );
    }
    final authType = reader.getRovoAuthType();
    final trimmedToken = token.trim();
    final authValue = _startsWithAuthScheme(trimmedToken)
        ? trimmedToken
        : '$authType $trimmedToken';
    return RovoHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: reader.getRovoMcpUrl(),
      authValue: authValue,
      defaultCloudId: reader.getRovoCloudId(),
    );
  }

  /// Creates a client with explicit configuration (primarily for testing).
  RovoHttpClient.custom({
    required super.dio,
    required super.basePath,
    required String token,
    String authType = 'Basic',
    this.defaultCloudId,
  }) : _authValue = _startsWithAuthScheme(token.trim())
            ? token.trim()
            : '${authType.trim().isEmpty ? 'Basic' : authType.trim()} ${token.trim()}';

  RovoHttpClient._({
    required super.dio,
    required super.basePath,
    required String authValue,
    this.defaultCloudId,
  }) : _authValue = authValue;

  static bool _startsWithAuthScheme(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('basic ') || lower.startsWith('bearer ');
  }

  @override
  Map<String, String> get authHeaders => {
        'Authorization': _authValue,
        'Accept': 'application/json, text/event-stream',
      };

  @override
  String buildUrl(String path) => path.isEmpty ? basePath : '$basePath/$path';
}
