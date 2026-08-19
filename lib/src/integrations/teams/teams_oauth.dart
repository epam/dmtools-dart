/// OAuth2 helpers for the Microsoft integrations (Teams / SharePoint).
///
/// Ports the refresh leg of Java `OAuth2AuthenticationFlow`: exchanges a
/// refresh token for a short-lived Graph access token at the
/// `login.microsoftonline.com` token endpoint. The device-code and
/// authorization-code legs land together with the `teams_auth_*` tool port.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Token-endpoint template — `{tenant}` is replaced per call (Java parity).
const _tokenEndpoint =
    'https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token';

/// Refresh-token → access-token exchange for Microsoft Graph.
class TeamsOAuth {
  /// Exchanges [refreshToken] for an access token using [clientId] and
  /// [tenantId], mirroring Java `OAuth2AuthenticationFlow.refreshAccessToken`.
  ///
  /// Pass [dio] to inject a custom transport (tests); production code omits
  /// it and gets the default 60s-timeout [Dio]. Throws [StateError] when the
  /// endpoint answers without a usable `access_token`.
  static Future<String> refreshAccessToken(
    String refreshToken,
    String clientId,
    String tenantId, {
    Dio? dio,
  }) async {
    final client = dio ?? BaseHttpClient.createDefaultDio();
    final response = await client.post<String>(
      _tokenEndpoint.replaceFirst('{tenant}', tenantId),
      data:
          'grant_type=refresh_token&client_id=${Uri.encodeQueryComponent(clientId)}'
          '&refresh_token=${Uri.encodeQueryComponent(refreshToken)}',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final decoded = jsonDecode(response.data ?? '{}');
    final access =
        decoded is Map<String, dynamic> ? decoded['access_token'] : null;
    if (access is! String || access.isEmpty) {
      throw StateError('Token refresh failed: $decoded');
    }
    return access;
  }

  /// Resolves a Graph access token from [reader]'s configuration.
  ///
  /// Returns `null` when no refresh token is configured (caller decides
  /// whether to skip or fail); throws when the exchange itself fails.
  static Future<String?> resolveAccessToken(PropertyReader reader) async {
    final refreshToken = reader.getTeamsRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    return refreshAccessToken(
      refreshToken,
      reader.getTeamsClientId() ?? '',
      reader.getTeamsTenantId(),
    );
  }
}
