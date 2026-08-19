/// Test doubles for exercising Confluence clients against canned HTTP
/// responses.
///
/// Provides a [Dio] whose transport ([RoutingAdapter]) answers every request
/// from a per-request router callback and records what was served, plus a
/// [mockConfluence] fixture that wires a real [ConfluenceClient] (and
/// [ConfluenceHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [ConfluenceClient] plus the [RoutingAdapter] serving its requests.
typedef MockConfluenceFixture = ({
  ConfluenceClient client,
  RoutingAdapter adapter,
});

/// A mocked [ConfluenceHttpClient] plus the [RoutingAdapter] serving its
/// requests.
typedef MockHttpFixture = ({
  ConfluenceHttpClient http,
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

/// The Confluence config injected for every fixture built by [mockConfluence].
const _testConfig = {
  'CONFLUENCE_BASE_PATH': 'https://confluence.example.com/wiki',
  'CONFLUENCE_EMAIL': 'dev@example.com',
  'CONFLUENCE_API_TOKEN': 'tok-123',
};

/// Builds a [ConfluenceClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockConfluenceFixture mockConfluence(
  String Function(RequestOptions options) router,
) {
  final httpFix = mockHttp(router);
  return (
    client: ConfluenceClient(httpFix.http),
    adapter: httpFix.adapter,
  );
}

/// Builds a [ConfluenceHttpClient] over a mocked [Dio] routed by [router].
MockHttpFixture mockHttp(String Function(RequestOptions options) router) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: ConfluenceHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Builds a [ConfluenceHttpClient] with a custom auth type (Basic/Bearer).
MockHttpFixture mockHttpWithAuth(
  String Function(RequestOptions options) router, {
  required String authType,
}) {
  PropertyReader.setOverrides({
    ..._testConfig,
    'CONFLUENCE_AUTH_TYPE': authType,
  });
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: ConfluenceHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
///
/// Paths match with `endsWith` against the full request URL, so `'/content'`
/// matches `.../wiki/rest/api/content` but not `.../wiki/rest/api/content/123`.
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
