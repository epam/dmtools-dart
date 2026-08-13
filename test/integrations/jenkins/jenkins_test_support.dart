/// Test doubles for exercising Jenkins clients against canned HTTP responses.
///
/// Provides a [Dio] whose transport ([RoutingAdapter]) answers every request
/// from a per-request router callback and records what was served, plus a
/// [mockJenkins] fixture that wires a real [JenkinsClient] (and
/// [JenkinsHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [JenkinsClient] plus the [RoutingAdapter] serving its requests.
typedef MockJenkinsFixture = ({JenkinsClient client, RoutingAdapter adapter});

/// A mocked [JenkinsHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockHttpFixture = ({JenkinsHttpClient http, RoutingAdapter adapter});

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

/// The Jenkins config injected for every fixture built by [mockJenkins].
const _testConfig = {
  'JENKINS_BASE_PATH': 'http://jenkins.example.com',
  'JENKINS_USER': 'dev',
  'JENKINS_API_TOKEN': 'token-123',
};

/// Builds a [JenkinsClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockJenkinsFixture mockJenkins(String Function(RequestOptions options) router) {
  final httpFix = mockHttp(router);
  return (client: JenkinsClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [JenkinsHttpClient] over a mocked [Dio] routed by [router].
MockHttpFixture mockHttp(String Function(RequestOptions options) router) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: JenkinsHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
///
/// Paths match with `endsWith` against the full request URL, so `'/api/json'`
/// matches `http://jenkins.example.com/api/json`.
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
