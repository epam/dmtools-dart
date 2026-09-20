/// Figma OAuth2 helpers — Java `FigmaOAuth2TokenManager` parity.
///
/// Pure pieces (authorization-URL construction, form body encoding, token
/// response parsing) are shared by the async MCP client and the sync
/// JS-surface executors; [FigmaOAuth2Exchange] performs the async token
/// POST for the MCP tool path.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

/// Figma OAuth2 authorize endpoint.
const figmaOAuthAuthorizeUrl = 'https://www.figma.com/oauth';

/// Figma OAuth2 token endpoint.
const figmaOAuthTokenUrl = 'https://api.figma.com/v1/oauth/token';

/// Java `DEFAULT_FIGMA_OAUTH_SCOPE` — minimal read scope.
const figmaDefaultOAuthScope = 'file_content:read file_metadata:read';

/// Java `normalizeScope`: trims, falling back to the default scope.
String figmaNormalizeScope(String? scope) {
  final trimmed = scope?.trim() ?? '';
  return trimmed.isEmpty ? figmaDefaultOAuthScope : trimmed;
}

/// Builds the authorization URL — Java `buildAuthorizationUrl`.
String figmaBuildAuthorizationUrl({
  required String clientId,
  required String redirectUri,
  required String state,
  String? scope,
}) {
  final effectiveScope = figmaNormalizeScope(scope);
  return '$figmaOAuthAuthorizeUrl'
      '?client_id=${Uri.encodeQueryComponent(clientId)}'
      '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
      '&scope=${Uri.encodeQueryComponent(effectiveScope)}'
      '&state=${Uri.encodeQueryComponent(state)}'
      '&response_type=code';
}

/// Form body for the `authorization_code` grant — Java
/// `exchangeCodeForTokens`.
String figmaTokenRequestBody({
  required String clientId,
  required String clientSecret,
  required String code,
  required String redirectUri,
}) =>
    'client_id=${Uri.encodeQueryComponent(clientId)}'
    '&client_secret=${Uri.encodeQueryComponent(clientSecret)}'
    '&code=${Uri.encodeQueryComponent(code)}'
    '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
    '&grant_type=authorization_code';

/// Form body for the `refresh_token` grant — Java `refreshAccessToken`.
String figmaRefreshTokenBody({
  required String clientId,
  required String clientSecret,
  required String refreshToken,
}) =>
    'client_id=${Uri.encodeQueryComponent(clientId)}'
    '&client_secret=${Uri.encodeQueryComponent(clientSecret)}'
    '&refresh_token=${Uri.encodeQueryComponent(refreshToken)}'
    '&grant_type=refresh_token';

/// A parsed OAuth2 token response — Java `TokenResponse`.
typedef FigmaTokenResponse = ({
  String accessToken,
  String refreshToken,
  int expiresIn
});

/// Parses a token endpoint body with the Java `optString`/`optLong`
/// defaults (empty strings, 3600s).
FigmaTokenResponse figmaParseTokenResponse(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  return (
    accessToken: json['access_token']?.toString() ?? '',
    refreshToken: json['refresh_token']?.toString() ?? '',
    expiresIn:
        json['expires_in'] is num ? (json['expires_in'] as num).toInt() : 3600,
  );
}

/// Async token-endpoint caller for the MCP tool path.
class FigmaOAuth2Exchange {
  final Dio _dio;

  /// Creates an exchanger over [_dio] (inject a mock adapter in tests).
  FigmaOAuth2Exchange([Dio? dio]) : _dio = dio ?? Dio();

  /// Exchanges an authorization code for tokens — Java
  /// `exchangeCodeForTokens`. Throws [StateError] with the Java message
  /// (`Figma OAuth2 token request failed [code]: body`) on a non-2xx.
  Future<FigmaTokenResponse> exchangeCode({
    required String code,
    required String redirectUri,
    required String clientId,
    required String clientSecret,
  }) =>
      _post(figmaTokenRequestBody(
        clientId: clientId,
        clientSecret: clientSecret,
        code: code,
        redirectUri: redirectUri,
      ));

  /// Refreshes an access token — Java `refreshAccessToken`.
  Future<FigmaTokenResponse> refresh({
    required String refreshToken,
    required String clientId,
    required String clientSecret,
  }) =>
      _post(figmaRefreshTokenBody(
        clientId: clientId,
        clientSecret: clientSecret,
        refreshToken: refreshToken,
      ));

  Future<FigmaTokenResponse> _post(String body) async {
    Response<String> response;
    try {
      response = await _dio.post<String>(
        figmaOAuthTokenUrl,
        data: body,
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      throw StateError(
        'Figma OAuth2 token request failed [$status]: ${e.response?.data ?? e.message}',
      );
    }
    final data = response.data ?? '';
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw StateError(
        'Figma OAuth2 token request failed [${response.statusCode}]: $data',
      );
    }
    return figmaParseTokenResponse(data);
  }
}
