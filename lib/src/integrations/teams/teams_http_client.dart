/// HTTP client for the Microsoft Graph API (Teams / SharePoint transport).
///
/// Ports the transport layer used by the Java DMTools Teams integration:
/// Bearer-token auth against Microsoft Graph, base URL resolved from
/// `TEAMS_BASE_PATH` (default `https://graph.microsoft.com/v1.0`). The same
/// transport is shared by [SharepointClient] since SharePoint also targets
/// the Graph API with identical auth.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Microsoft Graph HTTP transport used by [TeamsClient] and
/// [SharepointClient].
///
/// Stores the bearer token and emits `Authorization: Bearer …` via
/// [authHeaders]; [buildUrl] prefixes [path] with [basePath]. Extends
/// [BaseHttpClient] directly because the token is resolved by the OAuth
/// device/refresh flow rather than a single env-var getter.
class TeamsHttpClient extends BaseHttpClient {
  final String _token;

  /// Creates a client from [reader]'s Teams configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts. Pass [token] to
  /// supply an access token resolved by the OAuth flow; when omitted the
  /// client falls back to `TEAMS_REFRESH_TOKEN`.
  ///
  /// Throws [StateError] when no token is configured.
  factory TeamsHttpClient(
    PropertyReader reader, {
    Dio? dio,
    String? token,
  }) {
    final basePath = reader.getTeamsBasePath();
    final resolved = token ?? reader.getTeamsRefreshToken();
    if (resolved == null || resolved.isEmpty) {
      throw StateError('Teams access token is not configured');
    }
    return TeamsHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      token: resolved,
    );
  }

  const TeamsHttpClient._({
    required super.dio,
    required super.basePath,
    required String token,
  }) : _token = token;

  @override
  Map<String, String> get authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  String buildUrl(String path) => '$basePath/$path';
}
