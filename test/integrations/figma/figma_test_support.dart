/// Test doubles for exercising Figma clients against canned HTTP responses.
///
/// Mirrors the GitHub test support: a [Dio] whose transport ([RoutingAdapter])
/// answers every request from a per-request router callback and records what
/// was served, plus a [mockFigma] fixture wiring a real [FigmaClient] (and
/// [FigmaHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [FigmaClient] plus the [RoutingAdapter] serving its requests.
typedef MockFigmaFixture = ({FigmaClient client, RoutingAdapter adapter});

/// A mocked [FigmaHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockFigmaHttpFixture = ({FigmaHttpClient http, RoutingAdapter adapter});

/// A canned-response [HttpClientAdapter] that records each served request.
///
/// Routes to a String body by default; [RoutingAdapter.bytes] serves raw
/// bytes verbatim (binary image downloads must survive the transport
/// without a text-decoding round trip).
class RoutingAdapter implements HttpClientAdapter {
  RoutingAdapter(this._router) : _bytesRouter = null;

  RoutingAdapter.bytes(Uint8List Function(RequestOptions options) router)
      : _router = null,
        _bytesRouter = router;

  final String Function(RequestOptions options)? _router;
  final Uint8List Function(RequestOptions options)? _bytesRouter;

  /// Requests served so far, in call order.
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final bytes = _bytesRouter?.call(options);
    if (bytes != null) {
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      );
    }
    return ResponseBody.fromString(
      _router!(options),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The Figma config injected for every fixture built by [mockFigma].
const _testConfig = {
  'FIGMA_TOKEN': 'figma-token-abc',
  'FIGMA_BASE_PATH': 'https://figma.example.com/v1',
};

/// Builds a [FigmaClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockFigmaFixture mockFigma(String Function(RequestOptions options) router) {
  final httpFix = mockFigmaHttp(router);
  return (client: FigmaClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [FigmaHttpClient] over a mocked [Dio] routed by [router].
MockFigmaHttpFixture mockFigmaHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: FigmaHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Builds a [FigmaHttpClient] over a mocked [Dio] whose router returns
/// raw bytes — the regression fixture for binary image downloads.
MockFigmaHttpFixture mockFigmaHttpBytes(
  Uint8List Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter.bytes(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: FigmaHttpClient(PropertyReader(), dio: dio),
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
