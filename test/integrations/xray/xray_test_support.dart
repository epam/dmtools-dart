/// Test doubles for exercising Xray clients against canned HTTP responses.
///
/// Mirrors the Jira/TestRail test support: a [Dio] whose transport
/// ([RoutingAdapter]) answers every request from a per-request router callback
/// and records what was served, plus a [mockXray] fixture wiring a real
/// [XrayClient] (and [XrayHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [XrayClient] plus the [RoutingAdapter] serving its requests.
typedef MockXrayFixture = ({XrayClient client, RoutingAdapter adapter});

/// A mocked [XrayHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockXrayHttpFixture = ({XrayHttpClient http, RoutingAdapter adapter});

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

/// The Xray config injected for every fixture built by [mockXray].
const _testConfig = {
  'XRAY_BASE_PATH': 'https://xray.example.com',
  'XRAY_CLIENT_ID': 'client-123',
  'XRAY_CLIENT_SECRET': 'secret-456',
};

/// Builds an [XrayClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockXrayFixture mockXray(String Function(RequestOptions options) router) {
  final httpFix = mockXrayHttp(router);
  return (client: XrayClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds an [XrayHttpClient] over a mocked [Dio] routed by [router].
MockXrayHttpFixture mockXrayHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: XrayHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
///
/// Paths match with `endsWith` against the full request URL, so `'/tests'`
/// matches `.../api/v2/tests` but not `.../api/v2/test/PROJ-1/testexecutions`.
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
