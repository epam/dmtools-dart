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
  spaceIdFromKeyV2Tests();
  createPageV2Tests();
  updatePageV2Tests();
  contentByTitleV2Tests();
  getContentAttachmentsV2Tests();
  v1OnlyLimitationTests();
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

/// Canned v2 spaces-lookup response for [spaceKey] resolving to [id].
String spacesBody(String id, String key) => jsonEncode({
      'results': [
        {'id': id, 'key': key}
      ]
    });

/// Canned v2 page response with a storage [value].
String pageBody(String value,
        {String id = '123', String title = 'Test Page'}) =>
    jsonEncode({
      'id': id,
      'title': title,
      'body': {
        'storage': {'value': value, 'representation': 'storage'}
      },
    });

/// `spaceIdFromKey` — v2 spaces lookup resolving a key to the numeric id.
void spaceIdFromKeyV2Tests() {
  group('ConfluenceClient.spaceIdFromKey (v2)', () {
    test('resolves the id from the v2 spaces endpoint', () async {
      final f = mockConfluenceV2((o) => spacesBody('456', 'PROJ'));

      expect(await f.client.spaceIdFromKey('PROJ'), '456');

      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/wiki/api/v2/spaces'));
      expect(call.uri.queryParameters['keys'], 'PROJ');
    });

    test('throws mentioning the key when no space matches', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'results': []}));

      await expectLater(
        f.client.spaceIdFromKey('NOPE'),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('NOPE')),
        ),
      );
    });
  });
}

/// `confluence_create_page` under v2 — POST `/wiki/api/v2/pages`.
void createPageV2Tests() {
  group('ConfluenceClient.createPage (v2)', () {
    test('resolves spaceId then POSTs the v2 pages payload', () async {
      final f = mockConfluenceV2((o) {
        if (o.uri.path.endsWith('/spaces')) return spacesBody('456', 'PROJ');
        return pageBody('<p>Hi</p>', id: 'new-1', title: 'New Page');
      });

      final page = await f.client
          .createPage('PROJ', 'New Page', '<p>Hi</p>', parentId: '999');

      expect(page['id'], 'new-1');
      expect(f.adapter.calls, hasLength(2));
      final lookup = f.adapter.calls.first;
      expect(lookup.uri.path, endsWith('/wiki/api/v2/spaces'));
      expect(lookup.uri.queryParameters['keys'], 'PROJ');
      final post = f.adapter.calls.last;
      expect(post.method, 'POST');
      expect(post.uri.path, endsWith('/wiki/api/v2/pages'));
      final sent = jsonDecode(post.data as String) as Map<String, dynamic>;
      expect(sent['spaceId'], '456');
      expect(sent['status'], 'current');
      expect(sent['title'], 'New Page');
      expect(sent['parentId'], '999');
      expect(sent['body']['representation'], 'storage');
      expect(sent['body']['value'], '<p>Hi</p>');
      // v2 payload carries no v1 fields
      expect(sent.containsKey('type'), isFalse);
      expect(sent.containsKey('ancestors'), isFalse);
      expect(sent.containsKey('space'), isFalse);
    });

    test('v1 keeps the legacy content post without the spaces resolver',
        () async {
      final f =
          mockConfluenceV2((o) => pageBody('<p>Hi</p>'), apiVersion: 'v1');

      await f.client.createPage('PROJ', 'New Page', '<p>Hi</p>');

      expect(f.adapter.calls.single.uri.path, endsWith('/rest/api/content'));
    });
  });
}

/// `confluence_update_page` under v2 — GET then PUT `/wiki/api/v2/pages/{id}`.
void updatePageV2Tests() {
  group('ConfluenceClient.updatePage (v2)', () {
    test('reads the version via v2, then PUTs the incremented payload',
        () async {
      final f = mockConfluenceV2((o) {
        if (o.method == 'GET') {
          return jsonEncode({
            'id': '123',
            'title': 'Old Title',
            'version': {'number': 3},
          });
        }
        return pageBody('<p>updated</p>', title: 'New Title');
      });

      final page = await f.client.updatePage(
        '123',
        'New Title',
        '999',
        '<p>updated</p>',
        'PROJ',
        'my comment',
      );

      expect(page['title'], 'New Title');
      expect(f.adapter.calls, hasLength(2));
      final get = f.adapter.calls.first;
      expect(get.method, 'GET');
      expect(get.uri.path, endsWith('/wiki/api/v2/pages/123'));
      final put = f.adapter.calls.last;
      expect(put.method, 'PUT');
      expect(put.uri.path, endsWith('/wiki/api/v2/pages/123'));
      final sent = jsonDecode(put.data as String) as Map<String, dynamic>;
      expect(sent['id'], '123');
      expect(sent['status'], 'current');
      expect(sent['title'], 'New Title');
      expect(sent['version']['number'], 4);
      expect(sent['version']['message'], 'my comment');
      expect(sent['body']['representation'], 'storage');
      expect(sent['body']['value'], '<p>updated</p>');
      // v2 updates carry no ancestors/space
      expect(sent.containsKey('ancestors'), isFalse);
      expect(sent.containsKey('space'), isFalse);
    });

    test('v1 keeps the legacy version expand + content put', () async {
      final f = mockConfluenceV2((o) {
        if (o.method == 'GET') {
          return jsonEncode({
            'id': '123',
            'version': {'number': 3},
          });
        }
        return pageBody('<p>updated</p>');
      }, apiVersion: 'v1');

      await f.client.updatePage(
        '123',
        'New Title',
        '999',
        '<p>updated</p>',
        'PROJ',
        'my comment',
      );

      expect(f.adapter.calls.first.uri.path, endsWith('/rest/api/content/123'));
      expect(f.adapter.calls.first.queryParameters['expand'], 'version');
      expect(f.adapter.calls.last.uri.path, endsWith('/rest/api/content/123'));
    });
  });
}

/// Title lookup (`confluence_content_by_title_and_space`) under v2 —
/// GET `/wiki/api/v2/pages?title=&spaceId=&body-format=storage`.
void contentByTitleV2Tests() {
  group('ConfluenceClient.contentByTitleAndSpace (v2)', () {
    test('resolves spaceId then queries v2 pages by title', () async {
      final f = mockConfluenceV2((o) {
        if (o.uri.path.endsWith('/spaces')) return spacesBody('456', 'PROJ');
        return jsonEncode({
          'results': [
            {
              'id': '123',
              'title': 'My Page',
              'body': {
                'storage': {
                  'value': '<p>found</p>',
                  'representation': 'storage'
                }
              },
            }
          ]
        });
      });

      final result = await f.client.contentByTitleAndSpace('My Page', 'PROJ');

      expect(result['results'], hasLength(1));
      expect(f.adapter.calls, hasLength(2));
      final lookup = f.adapter.calls.first;
      expect(lookup.uri.path, endsWith('/wiki/api/v2/spaces'));
      final pages = f.adapter.calls.last;
      expect(pages.uri.path, endsWith('/wiki/api/v2/pages'));
      expect(pages.uri.queryParameters['title'], 'My Page');
      expect(pages.uri.queryParameters['spaceId'], '456');
      expect(pages.uri.queryParameters['body-format'], 'storage');
    });

    test('format=md converts the v2 storage body in place', () async {
      final f = mockConfluenceV2((o) => jsonEncode({
            'results': [
              {
                'id': '123',
                'title': 'My Page',
                'body': {
                  'storage': {
                    'value': '<p>found</p>',
                    'representation': 'storage'
                  }
                },
              }
            ]
          }));

      final result =
          await f.client.contentByTitleAndSpace('My Page', 'PROJ', 'md');

      final storage =
          (result['results'].first['body'] as Map)['storage'] as Map;
      expect(storage['representation'], 'markdown');
      expect(storage['value'], 'found');
    });

    test('omits spaceId when space is empty', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'results': []}));

      await f.client.contentByTitleAndSpace('My Page', '');

      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/wiki/api/v2/pages'));
      expect(call.uri.queryParameters['title'], 'My Page');
      expect(call.uri.queryParameters.containsKey('spaceId'), isFalse);
      expect(call.uri.queryParameters['body-format'], 'storage');
    });

    test('v1 keeps the legacy spaceKey query', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'results': []}),
          apiVersion: 'v1');

      await f.client.contentByTitleAndSpace('My Page', 'PROJ');

      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/rest/api/content'));
      expect(call.uri.queryParameters['title'], 'My Page');
      expect(call.uri.queryParameters['spaceKey'], 'PROJ');
    });
  });
}

/// `confluence_get_content_attachments` under v2 —
/// GET `/wiki/api/v2/pages/{id}/attachments`.
void getContentAttachmentsV2Tests() {
  group('ConfluenceClient.getContentAttachments (v2)', () {
    test('uses the v2 page attachments endpoint', () async {
      final f = mockConfluenceV2((o) => jsonEncode({
            'results': [
              {'id': 'att1', 'title': 'file.png'}
            ]
          }));

      final attachments = await f.client.getContentAttachments('123');

      expect(attachments, hasLength(1));
      expect(attachments.single['id'], 'att1');
      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/wiki/api/v2/pages/123/attachments'));
    });

    test('v1 keeps the legacy child attachment endpoint', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'results': []}),
          apiVersion: 'v1');

      await f.client.getContentAttachments('123');

      expect(f.adapter.calls.single.uri.path,
          endsWith('/rest/api/content/123/child/attachment'));
    });
  });
}

/// Endpoints kept on the legacy v1 path even under the v2 flag — no public
/// v2 equivalents exist (Java #592 known limitation).
void v1OnlyLimitationTests() {
  group('v1-only endpoints (known limitation)', () {
    test('searchContentByText stays on the v1 CQL path under v2', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'results': []}));

      await f.client.searchContentByText('hello');

      final call = f.adapter.calls.single;
      expect(call.uri.path, endsWith('/rest/api/content/search'));
      expect(call.uri.queryParameters['cql'], contains('hello'));
    });

    test('profile endpoints stay v1 under v2', () async {
      final f = mockConfluenceV2((o) => jsonEncode({'displayName': 'Jane'}));

      await f.client.getCurrentUserProfile();

      expect(
          f.adapter.calls.single.uri.path, endsWith('/rest/api/user/current'));
    });
  });
}
