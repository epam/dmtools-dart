/// Test doubles for exercising Teams clients against canned HTTP responses.
///
/// Provides a [Dio] whose transport ([RoutingAdapter]) answers every request
/// from a per-request router callback and records what was served, plus a
/// [mockTeams] fixture that wires a real [TeamsClient] (and [TeamsHttpClient])
/// on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [TeamsClient] plus the [RoutingAdapter] serving its requests.
typedef MockTeamsFixture = ({TeamsClient client, RoutingAdapter adapter});

/// A mocked [TeamsHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockTeamsHttpFixture = ({TeamsHttpClient http, RoutingAdapter adapter});

/// A canned-response [HttpClientAdapter] that records each served request.
class RoutingAdapter implements HttpClientAdapter {
  RoutingAdapter(this._router);

  final String Function(RequestOptions options) _router;

  /// Requests served so far, in call order.
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return ResponseBody.fromString(
      _router(options),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The Teams config injected for every fixture built by [mockTeams].
const _testConfig = {
  'TEAMS_BASE_PATH': 'https://graph.microsoft.com/v1.0',
  'TEAMS_REFRESH_TOKEN': 'teams-access-123',
};

/// Builds a [TeamsClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockTeamsFixture mockTeams(
  String Function(RequestOptions options) router,
) {
  final httpFix = mockHttp(router);
  return (client: TeamsClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [TeamsHttpClient] over a mocked [Dio] routed by [router].
///
/// The access token is passed explicitly — the factory accepts only resolved
/// access tokens, never a raw refresh token.
MockTeamsHttpFixture mockHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: TeamsHttpClient(
      PropertyReader(),
      dio: dio,
      token: _testConfig['TEAMS_REFRESH_TOKEN'],
    ),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
///
/// Paths match with `endsWith` against the full request URL, so `'/me'`
/// matches `.../v1.0/me`.
String routeByPath(
  Map<String, String> routes,
  RequestOptions options, {
  String fallback = '{}',
}) {
  for (final entry in routes.entries) {
    if (options.path.endsWith(entry.key)) return entry.value;
  }
  return fallback;
}
