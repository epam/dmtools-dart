/// Test doubles for exercising GitHub clients against canned HTTP responses.
///
/// Mirrors the Jira test support: a [Dio] whose transport ([RoutingAdapter])
/// answers every request from a per-request router callback and records what
/// was served, plus a [mockGithub] fixture wiring a real [GithubClient] (and
/// [GithubHttpClient]) on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [GithubClient] plus the [RoutingAdapter] serving its requests.
typedef MockGithubFixture = ({GithubClient client, RoutingAdapter adapter});

/// A mocked [GithubHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockGithubHttpFixture = ({
  GithubHttpClient http,
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

/// The GitHub config injected for every fixture built by [mockGithub].
const _testConfig = {
  'SOURCE_GITHUB_TOKEN': 'gh-token-123',
  'SOURCE_GITHUB_BASE_PATH': 'https://github.example.com/api/v3',
};

/// Builds a [GithubClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockGithubFixture mockGithub(String Function(RequestOptions options) router) {
  final httpFix = mockGithubHttp(router);
  return (client: GithubClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [GithubHttpClient] over a mocked [Dio] routed by [router].
MockGithubHttpFixture mockGithubHttp(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: GithubHttpClient(PropertyReader(), dio: dio),
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
