import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'teams_test_support.dart';

/// Coverage + behavior tests for [TeamsOAuth] — the refresh-token exchange.
void main() {
  tearDown(PropertyReader.clearOverrides);

  test('exchanges the refresh token at the tenant token endpoint', () async {
    late RequestOptions captured;
    final token = await TeamsOAuth.refreshAccessToken(
      'refresh/1',
      'client-1',
      'tenant-1',
      dio: _dio((o) {
        captured = o;
        return '{"access_token":"at-1","expires_in":3600}';
      }),
    );
    expect(token, 'at-1');
    expect(
      captured.path,
      'https://login.microsoftonline.com/tenant-1/oauth2/v2.0/token',
    );
    expect(captured.method, 'POST');
    expect(captured.data, contains('grant_type=refresh_token'));
    expect(captured.data, contains('client_id=client-1'));
    expect(captured.data, contains('refresh_token=refresh%2F1'));
  });

  test('throws StateError when the answer has no access token', () async {
    await expectLater(
      TeamsOAuth.refreshAccessToken(
        'r',
        'c',
        'common',
        dio: _dio((o) => '{"error":"invalid_grant"}'),
      ),
      throwsStateError,
    );
  });

  test('resolveAccessToken returns null without a configured refresh token',
      () async {
    PropertyReader.clearOverrides();
    expect(await TeamsOAuth.resolveAccessToken(PropertyReader()), isNull);
  });
}

/// Builds a [Dio] over the Teams [RoutingAdapter] fake transport.
Dio _dio(String Function(RequestOptions options) router) =>
    Dio()..httpClientAdapter = RoutingAdapter(router);
