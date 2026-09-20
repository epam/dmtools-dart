import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'figma_executor_test_support.dart';
import 'figma_test_support.dart';

/// Tests for the OAuth tool handlers on [FigmaToolExecutor]
/// (`figma_oauth2_get_auth_url` / `figma_oauth2_exchange_code`).
void main() {
  tearDown(PropertyReader.clearOverrides);
  oauthGetAuthUrlTests();
  oauthExchangeCodeTests();
}

void oauthGetAuthUrlTests() {
  group('FigmaToolExecutor OAuth get_auth_url', () {
    test('reports a missing client id', () async {
      final f = executorFixture();
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {}),
      ) as Map<String, dynamic>;
      expect(result['error'], 'FIGMA_CLIENT_ID is not configured');
    });

    test('reports a missing client secret', () async {
      final f = executorFixture();
      PropertyReader.setOverrides({'FIGMA_CLIENT_ID': 'cid'});
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {}),
      ) as Map<String, dynamic>;
      expect(result['error'], 'FIGMA_CLIENT_SECRET is not configured');
    });

    test('reports a missing redirect URI', () async {
      final f = executorFixture();
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
      });
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {}),
      ) as Map<String, dynamic>;
      expect(
        result['error'],
        'redirectUri is required (or set FIGMA_REDIRECT_URI in dmtools.env)',
      );
    });

    test('builds the authorization URL from config', () async {
      final f = executorFixture();
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://localhost:8080/callback',
      });
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {
          'state': 'xyz',
        }),
      ) as Map<String, dynamic>;
      expect(
        result['authorization_url'],
        'https://www.figma.com/oauth?client_id=cid'
        '&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback'
        '&scope=file_content%3Aread+file_metadata%3Aread'
        '&state=xyz&response_type=code',
      );
      expect(result['state'], 'xyz');
      expect(result['instructions'], isNotNull);
    });
  });
}

void oauthExchangeCodeTests() {
  group('FigmaToolExecutor OAuth exchange_code', () {
    test('reports incomplete config', () async {
      final f = executorFixture();
      final result = jsonDecode(
        await f.executor
            .execute('figma_oauth2_exchange_code', {'code': 'c'}),
      ) as Map<String, dynamic>;
      expect(
        result['error'],
        'FIGMA_CLIENT_ID and FIGMA_CLIENT_SECRET must be configured',
      );
    });

    test('returns tokens and instructions', () async {
      final spy = SpyFigmaClient(mockFigmaHttp(spyRouter).http);
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://cb/',
      });
      final executor =
          FigmaToolExecutor(spy, PropertyReader(), _FakeExchange());
      final result = jsonDecode(
        await executor.execute('figma_oauth2_exchange_code', {'code': 'c'}),
      ) as Map<String, dynamic>;
      expect(result['access_token'], 'at');
      expect(result['refresh_token'], 'rt');
      expect(result['expires_in'], 3600);
      expect(
        result['instructions'],
        contains('FIGMA_OAUTH_REFRESH_TOKEN=rt'),
      );
    });

    test('wraps failures in the Java error text', () async {
      final spy = SpyFigmaClient(mockFigmaHttp(spyRouter).http);
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://cb/',
      });
      final executor = FigmaToolExecutor(
        spy,
        PropertyReader(),
        _FakeExchange(fail: true),
      );
      final result = jsonDecode(
        await executor.execute('figma_oauth2_exchange_code', {'code': 'c'}),
      ) as Map<String, dynamic>;
      expect(result['error'], startsWith('Token exchange failed:'));
    });
  });
}

/// A canned [FigmaOAuth2Exchange].
class _FakeExchange extends FigmaOAuth2Exchange {
  /// Creates the fake; [fail] makes the exchange throw.
  _FakeExchange({this.fail = false});

  final bool fail;

  @override
  Future<FigmaTokenResponse> exchangeCode({
    required String code,
    required String redirectUri,
    required String clientId,
    required String clientSecret,
  }) async {
    if (fail) {
      throw StateError('Figma OAuth2 token request failed [400]: bad');
    }
    return (accessToken: 'at', refreshToken: 'rt', expiresIn: 3600);
  }
}
