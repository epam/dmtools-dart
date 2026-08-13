/// Test doubles for exercising ADO clients against canned HTTP responses.
///
/// Mirrors the GitHub test support: a [Dio] whose transport ([RoutingAdapter])
/// answers every request from a per-request router callback and records what
/// was served, plus a [mockAdo] fixture wiring a real [AdoClient] (and
/// [AdoHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [AdoClient] plus the [RoutingAdapter] serving its requests.
typedef MockAdoFixture = ({AdoClient client, RoutingAdapter adapter});

/// A mocked [AdoHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockAdoHttpFixture = ({AdoHttpClient http, RoutingAdapter adapter});

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

/// The ADO config injected for every fixture built by [mockAdo].
const _testConfig = {
  'ADO_ORGANIZATION': 'contoso',
  'ADO_PROJECT': 'dmtools',
  'ADO_PAT_TOKEN': 'ado-pat-123',
  'ADO_BASE_PATH': 'https://ado.example.com',
};

/// Builds an [AdoClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockAdoFixture mockAdo(String Function(RequestOptions options) router) {
  final httpFix = mockAdoHttp(router);
  return (client: AdoClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds an [AdoHttpClient] over a mocked [Dio] routed by [router].
MockAdoHttpFixture mockAdoHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: AdoHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
///
/// Paths match with `endsWith` against the full request URL.
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
