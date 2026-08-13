/// Test doubles for exercising SharePoint clients against canned HTTP responses.
///
/// SharePoint reuses [TeamsHttpClient] as its transport, so this fixture wires
/// a real [SharepointClient] on top of a mocked [Dio] served by [RoutingAdapter]
/// (the same canned-response adapter used across integrations).
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [SharepointClient] plus the [RoutingAdapter] serving its requests.
typedef MockSharepointFixture = ({
  SharepointClient client,
  RoutingAdapter adapter,
});

/// A mocked [TeamsHttpClient] for SharePoint, plus its [RoutingAdapter].
typedef MockSharepointHttpFixture = ({
  TeamsHttpClient http,
  RoutingAdapter adapter,
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

/// The Teams/Graph config injected for every fixture built by [mockSharepoint].
const _testConfig = {
  'TEAMS_BASE_PATH': 'https://graph.microsoft.com/v1.0',
  'TEAMS_REFRESH_TOKEN': 'teams-access-123',
};

/// Builds a [SharepointClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockSharepointFixture mockSharepoint(
  String Function(RequestOptions options) router,
) {
  final httpFix = mockSharepointHttp(router);
  return (client: SharepointClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [TeamsHttpClient] for SharePoint over a mocked [Dio] routed by
/// [router].
MockSharepointHttpFixture mockSharepointHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: TeamsHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
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
