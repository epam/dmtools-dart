/// Tests for the Java-parity Figma OAuth2 helpers (`figma_oauth2.dart`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/src/integrations/figma/figma_oauth2.dart';
import 'package:test/test.dart';

void main() {
  group('figmaBuildAuthorizationUrl', () {
    test('assembles the authorize URL with encoded components', () {
      final url = figmaBuildAuthorizationUrl(
        clientId: 'id x',
        redirectUri: 'http://localhost:8080/callback',
        state: 's1',
      );
      expect(
        url,
        'https://www.figma.com/oauth?client_id=id+x'
        '&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback'
        '&scope=file_content%3Aread+file_metadata%3Aread'
        '&state=s1&response_type=code',
      );
    });

    test('honors an explicit scope', () {
      final url = figmaBuildAuthorizationUrl(
        clientId: 'id',
        redirectUri: 'http://cb/',
        state: 's',
        scope: 'files:read',
      );
      expect(url, contains('scope=files%3Aread'));
    });
  });

  group('figmaNormalizeScope', () {
    test('falls back to the default minimal read scope', () {
      expect(figmaNormalizeScope(null), figmaDefaultOAuthScope);
      expect(figmaNormalizeScope('  '), figmaDefaultOAuthScope);
    });

    test('trims a provided scope', () {
      expect(figmaNormalizeScope(' a:b '), 'a:b');
    });
  });

  group('figmaTokenRequestBody', () {
    test('form-encodes the authorization_code grant', () {
      expect(
        figmaTokenRequestBody(
          clientId: 'id 1',
          clientSecret: 'sec&ret',
          code: 'c+d',
          redirectUri: 'http://cb/',
        ),
        'client_id=id+1&client_secret=sec%26ret&code=c%2Bd'
        '&redirect_uri=http%3A%2F%2Fcb%2F&grant_type=authorization_code',
      );
    });
  });

  group('figmaRefreshTokenBody', () {
    test('form-encodes the refresh_token grant', () {
      expect(
        figmaRefreshTokenBody(
            clientId: 'i', clientSecret: 's', refreshToken: 'r'),
        'client_id=i&client_secret=s&refresh_token=r&grant_type=refresh_token',
      );
    });
  });

  group('figmaParseTokenResponse', () {
    test('reads all three fields', () {
      final parsed = figmaParseTokenResponse(
        '{"access_token":"a","refresh_token":"r","expires_in":3600}',
      );
      expect(parsed.accessToken, 'a');
      expect(parsed.refreshToken, 'r');
      expect(parsed.expiresIn, 3600);
    });

    test('applies Java optString/optLong defaults', () {
      final parsed = figmaParseTokenResponse('{}');
      expect(parsed.accessToken, '');
      expect(parsed.refreshToken, '');
      expect(parsed.expiresIn, 3600);
    });
  });

  group('FigmaOAuth2Exchange', () {
    test('posts the form body to the token endpoint and parses tokens',
        () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _EchoAdapter((options, body) {
          requests.add(options);
          return '{"access_token":"tok","refresh_token":"ref","expires_in":7200}';
        });
      final exchange = FigmaOAuth2Exchange(dio);
      final tokens = await exchange.exchangeCode(
        code: 'code1',
        redirectUri: 'http://cb/',
        clientId: 'cid',
        clientSecret: 'cs',
      );
      expect(tokens.accessToken, 'tok');
      expect(tokens.expiresIn, 7200);
      final req = requests.single;
      expect(req.path, figmaOAuthTokenUrl);
      expect(req.method, 'POST');
      expect(
        (req.data as String).contains('grant_type=authorization_code'),
        isTrue,
      );
    });

    test('throws with the Java error text on a non-2xx response', () {
      final dio = Dio()
        ..httpClientAdapter = _EchoAdapter((options, body) {
          throw DioException.badResponse(
            statusCode: 400,
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 400,
              data: '{"error":"invalid_grant"}',
            ),
          );
        });
      final exchange = FigmaOAuth2Exchange(dio);
      expect(
        () => exchange.exchangeCode(
          code: 'bad',
          redirectUri: 'http://cb/',
          clientId: 'cid',
          clientSecret: 'cs',
        ),
        throwsA(
          predicate<StateError>(
            (e) =>
                e.message.contains(
                  'Figma OAuth2 token request failed [400]',
                ) &&
                e.message.contains('invalid_grant'),
          ),
        ),
      );
    });
  });
}

/// Adapter returning canned bodies, capturing the request for assertions.
class _EchoAdapter implements HttpClientAdapter {
  _EchoAdapter(this._respond);

  final String Function(RequestOptions options, String? body) _respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String? body;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      body =
          chunks.isEmpty ? null : utf8.decode(chunks.expand((c) => c).toList());
    }
    return ResponseBody.fromString(
      _respond(options, body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
