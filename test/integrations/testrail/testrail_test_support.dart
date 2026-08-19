/// Test doubles for exercising TestRail clients against canned HTTP responses.
///
/// Mirrors the Jira/GitHub test support: a [Dio] whose transport
/// ([RoutingAdapter]) answers every request from a per-request router callback
/// and records what was served, plus a [mockTestRail] fixture wiring a real
/// [TestRailClient] (and [TestRailHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [TestRailClient] plus the [RoutingAdapter] serving its requests.
typedef MockTestRailFixture = ({TestRailClient client, RoutingAdapter adapter});

/// A mocked [TestRailHttpClient] plus the [RoutingAdapter] serving requests.
typedef MockTestRailHttpFixture = ({
  TestRailHttpClient http,
  RoutingAdapter adapter
});

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

/// The TestRail config injected for every fixture built by [mockTestRail].
const _testConfig = {
  'TESTRAIL_BASE_PATH': 'https://tr.example.com',
  'TESTRAIL_USERNAME': 'dev@example.com',
  'TESTRAIL_API_KEY': 'key-123',
  'TESTRAIL_PROJECT': 'proj-1',
};

/// Builds a [TestRailClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockTestRailFixture mockTestRail(
  String Function(RequestOptions options) router,
) {
  final httpFix = mockTestRailHttp(router);
  return (client: TestRailClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [TestRailHttpClient] over a mocked [Dio] routed by [router].
MockTestRailHttpFixture mockTestRailHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: TestRailHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path substring, defaulting to [fallback].
///
/// TestRail URLs embed query-like route segments (`?/api/v2/...`), so routes
/// match with `contains` against the full request URL.
String routeByPath(
  Map<String, String> routes,
  RequestOptions options, {
  String fallback = '{}',
}) {
  for (final entry in routes.entries) {
    if (options.path.contains(entry.key)) return entry.value;
  }
  return fallback;
}
