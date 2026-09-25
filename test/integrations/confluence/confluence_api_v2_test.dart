import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Confluence v2 REST API path (`CONFLUENCE_API_VERSION=v2`), required when
/// authenticating with Atlassian granular/scoped API tokens — the legacy v1
/// content endpoints return 401 scope-mismatch under such tokens.
///
/// Java parity: `ConfluenceApiV2Test`.
void main() {
  tearDown(PropertyReader.clearOverrides);
  apiVersionConfigTests();
  httpClientV2Tests();
  getPageByIdV2Tests();
  getContentChildrenV2Tests();
  testConnectionV2Tests();
}

/// Builds a v2-aware client over a mocked [Dio] routed by [router].
///
/// `CONFLUENCE_API_VERSION` is set to [apiVersion] for the fixture build, then
/// cleared (the [ConfluenceHttpClient] snapshots it at construction).
MockConfluenceFixture mockConfluenceV2(
  String Function(RequestOptions options) router, {
  String apiVersion = 'v2',
}) {
  PropertyReader.setOverrides({
    ..._testConfig,
    'CONFLUENCE_API_VERSION': apiVersion,
  });
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  final http = ConfluenceHttpClient(PropertyReader(), dio: dio);
  PropertyReader.clearOverrides();
  return (client: ConfluenceClient(http), adapter: adapter);
}

/// The Confluence config reused by the v2 fixtures (mirrors
/// `confluence_test_support._testConfig`, which is private).
const _testConfig = {
  'CONFLUENCE_BASE_PATH': 'https://confluence.example.com/wiki',
  'CONFLUENCE_EMAIL': 'dev@example.com',
  'CONFLUENCE_API_TOKEN': 'tok-123',
};

/// `PropertyReader.getConfluenceApiVersion` — the `CONFLUENCE_API_VERSION` flag.
void apiVersionConfigTests() {
  group('PropertyReader.getConfluenceApiVersion', () {
    test('defaults to v1 when unset', () {
      expect(PropertyReader().getConfluenceApiVersion(), 'v1');
    });

    test('reads v2', () {
      PropertyReader.setOverrides({'CONFLUENCE_API_VERSION': 'v2'});
      expect(PropertyReader().getConfluenceApiVersion(), 'v2');
    });

    test('normalizes case and surrounding whitespace', () {
      PropertyReader.setOverrides({'CONFLUENCE_API_VERSION': ' V2 '});
      expect(PropertyReader().getConfluenceApiVersion(), 'v2');
    });
  });
}

/// [ConfluenceHttpClient]: v2 URL building and the isApiV2 flag.
void httpClientV2Tests() {
  group('ConfluenceHttpClient v2', () {
    test('builds /wiki/api/v2 URLs', () {
      final f = mockConfluenceV2((o) => '{}');
      expect(f.client, isNotNull);
      final http = mockHttpV2();
      expect(http.buildUrlV2('pages/123'),
          'https://confluence.example.com/wiki/api/v2/pages/123');
    });

    test('isApiV2 reflects the configured version', () {
      expect(mockHttpV2(apiVersion: 'v2').isApiV2, isTrue);
      expect(mockHttpV2(apiVersion: 'v1').isApiV2, isFalse);
    });

    test('isApiV2 is case-insensitive', () {
      expect(mockHttpV2(apiVersion: 'V2').isApiV2, isTrue);
    });

    test('defaults to v1 when the flag is unset', () {
      expect(mockHttpV2(apiVersion: null).isApiV2, isFalse);
    });
  });
}

/// Builds a bare v2-mode [ConfluenceHttpClient] (URL building only, no I/O).
ConfluenceHttpClient mockHttpV2({String? apiVersion}) {
  PropertyReader.setOverrides({
    ..._testConfig,
    if (apiVersion != null) 'CONFLUENCE_API_VERSION': apiVersion,
  });
  final http = ConfluenceHttpClient(PropertyReader(), dio: Dio());
  PropertyReader.clearOverrides();
  return http;
}

/// `confluence_get_page_by_id` under v2 — GET `/wiki/api/v2/pages/{id}`.
void getPageByIdV2Tests() {
  group('ConfluenceClient.getPageById (v2)', () {
    test('uses the v2 pages endpoint with body-format=storage', () async {
      final f = mockConfluenceV2((o) => jsonEncode({
            'id': '123',
            'title': 'Test Page',
            'body': {
              'storage': {'value': '<p>Hi</p>', 'representation': 'storage'}
            },
          }));

      final page = await f.client.getPageById('123');

      expect(page['title'], 'Test Page');
      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/wiki/api/v2/pages/123'));
      expect(call.uri.query, contains('body-format=storage'));
    });

    test('v1 keeps the legacy /rest/api/content endpoint', () async {
      final f =
          mockConfluenceV2((o) => jsonEncode({'id': '123'}), apiVersion: 'v1');

      await f.client.getPageById('123');

      expect(f.adapter.calls.single.uri.path,
          endsWith('/wiki/rest/api/content/123'));
    });
  });
}

/// `confluence_get_content_children` under v2 — GET `/wiki/api/v2/pages`.
void getContentChildrenV2Tests() {
  group('ConfluenceClient.getContentChildren (v2)', () {
    test('uses the v2 pages endpoint with parent-id', () async {
      final f = mockConfluenceV2((o) => jsonEncode({
            'results': [
              {'id': 'c1', 'title': 'Child'}
            ]
          }));

      final children = await f.client.getContentChildren('999');

      expect(children, hasLength(1));
      expect(children.single['title'], 'Child');
      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/wiki/api/v2/pages'));
      expect(call.uri.query, contains('parent-id=999'));
    });

    test('v1 keeps the legacy child/page endpoint', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'results': []}),
          apiVersion: 'v1');

      await f.client.getContentChildren('999');

      expect(f.adapter.calls.single.uri.path,
          endsWith('/wiki/rest/api/content/999/child/page'));
    });
  });
}

/// `confluence_test` — health-check fallback to space listing.
void testConnectionV2Tests() {
  group('ConfluenceClient.testConnection fallback', () {
    test('falls back to space listing when user/current fails', () async {
      final f = mockConfluenceV2((o) {
        if (o.uri.path.endsWith('/user/current')) {
          throw DioException(
            requestOptions: o,
            response: Response(
              requestOptions: o,
              statusCode: 401,
              data: 'scope does not match',
            ),
          );
        }
        return jsonEncode({
          'results': [
            {'key': 'PROJ'}
          ]
        });
      });

      final result = await f.client.testConnection();

      expect(result['success'], isTrue);
      expect(result['user'], 'scoped-token');
      expect(result['spacesVisible'], 1);
      expect(f.adapter.calls.last.uri.path, endsWith('/rest/api/space'));
    });

    test('succeeds via user/current when the token allows it', () async {
      final f = mockConfluence((o) => jsonEncode({
            'displayName': 'Jane',
            'email': 'j@x.com',
          }));

      final result = await f.client.testConnection();

      expect(result['success'], isTrue);
      expect(result['user'], 'Jane');
    });

    test('fails when both profile and spaces fail', () async {
      final f = mockConfluenceV2((o) => throw DioException(
            requestOptions: o,
            response: Response(requestOptions: o, statusCode: 401),
          ));

      final result = await f.client.testConnection();

      expect(result['success'], isFalse);
    });
  });
}
