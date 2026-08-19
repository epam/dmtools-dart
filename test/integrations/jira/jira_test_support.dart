/// Test doubles for exercising Jira clients against canned HTTP responses.
///
/// Provides a [Dio] whose transport ([RoutingAdapter]) answers every request
/// from a per-request router callback and records what was served, plus a
/// [mockJira] fixture that wires a real [JiraClient] (and [JiraHttpClient])
/// on top of it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked [JiraClient] plus the [RoutingAdapter] serving its requests.
typedef MockJiraFixture = ({JiraClient client, RoutingAdapter adapter});

/// A mocked [JiraHttpClient] plus the [RoutingAdapter] serving its requests.
typedef MockHttpFixture = ({JiraHttpClient http, RoutingAdapter adapter});

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

/// The Jira config injected for every fixture built by [mockJira].
const _testConfig = {
  'JIRA_BASE_PATH': 'https://jira.example.com',
  'JIRA_EMAIL': 'dev@example.com',
  'JIRA_API_TOKEN': 'tok-123',
};

/// Builds a [JiraClient] over a mocked [Dio] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockJiraFixture mockJira(String Function(RequestOptions options) router) {
  final httpFix = mockHttp(router);
  return (client: JiraClient(httpFix.http), adapter: httpFix.adapter);
}

/// Builds a [JiraHttpClient] over a mocked [Dio] routed by [router].
MockHttpFixture mockHttp(String Function(RequestOptions options) router) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    http: JiraHttpClient(PropertyReader(), dio: dio),
    adapter: adapter,
  );
}

/// Routes by request-path suffix, defaulting to [fallback].
///
/// Paths match with `endsWith` against the full request URL, so `'/search/jql'`
/// matches `.../rest/api/latest/search/jql` but not `.../rest/api/latest/search`.
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
