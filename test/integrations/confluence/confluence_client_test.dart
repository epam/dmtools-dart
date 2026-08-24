import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Coverage + behavior tests for [ConfluenceClient] and
/// [ConfluenceHttpClient].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getPageTests();
  createPageTests();
  updatePageTests();
  searchTests();
}

/// The expected `Authorization` value produced by the fixture's Basic config.
String get _expectedBasicAuth =>
    'Basic ${base64Encode(utf8.encode('dev@example.com:tok-123'))}';

/// [ConfluenceHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('ConfluenceHttpClient', () {
    test('builds /wiki/rest/api URLs', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.buildUrl('user/current'),
          'https://confluence.example.com/wiki/rest/api/user/current');
    });

    test('assembles Basic Authorization by default', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.headers['Authorization'], _expectedBasicAuth);
      expect(f.http.headers['Content-Type'], 'application/json');
      expect(f.http.headers['Accept'], 'application/json');
    });

    test('uses Bearer scheme with raw token when authType is Bearer', () {
      final f = mockHttpWithAuth((o) => '{}', authType: 'Bearer');
      expect(f.http.headers['Authorization'], 'Bearer tok-123');
    });

    test('get/post/put return the response bodies', () async {
      final f = mockHttp((o) => routeByPath({
            '/content': 'GET-BODY',
            '/content/123': 'PUT-BODY',
          }, o));
      expect(await f.http.get('content'), 'GET-BODY');
      expect(await f.http.post('content', body: '{}'), 'GET-BODY');
      expect(await f.http.put('content/123', body: '{}'), 'PUT-BODY');
      f.http.close();
    });

    test('throws StateError when CONFLUENCE_BASE_PATH is missing', () {
      PropertyReader.clearOverrides();
      expect(() => ConfluenceHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when auth credentials are missing', () {
      PropertyReader.setOverrides(
          {'CONFLUENCE_BASE_PATH': 'https://confluence.example.com'});
      expect(() => ConfluenceHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `confluence_test` — connectivity check via GET `user/current`.
void testConnectionTests() {
  group('ConfluenceClient.testConnection', () {
    test('returns success with the user profile', () async {
      final f =
          mockConfluence((o) => routeByPath({'/user/current': _userBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Confluence connection successful');
      expect(result['user'], 'Dev User');
      expect(result['email'], 'dev@example.com');
      expect(f.adapter.calls.single.path, endsWith('/user/current'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockConfluence((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `confluence_get_page` — GET `content`.
void getPageTests() {
  group('ConfluenceClient.getPage', () {
    test('returns the first result page', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content': _getPageBody}, o));
      final page = await f.client.getPage('ENG', 'Design Doc');
      expect(page?['id'], '42');
      final qp = f.adapter.calls.single.queryParameters;
      expect(qp['spaceKey'], 'ENG');
      expect(qp['title'], 'Design Doc');
      expect(qp['expand'], 'body.storage');
    });

    test('returns null when no results', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content': '{"results":[]}'}, o));
      expect(await f.client.getPage('ENG', 'Nope'), isNull);
    });
  });
}

/// `confluence_create_page` — POST `content`.
void createPageTests() {
  group('ConfluenceClient.createPage', () {
    test('POSTs the page payload and returns the created page', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content': _createdPage}, o));
      final page = await f.client.createPage(
        'ENG',
        'New Page',
        '<p>hello</p>',
      );
      expect(page['id'], '99');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/content'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['type'], 'page');
      expect(sent['title'], 'New Page');
      expect(sent['space'], {'key': 'ENG'});
      final storage = (sent['body'] as Map<String, dynamic>)['storage']
          as Map<String, dynamic>;
      expect(storage['value'], '<p>hello</p>');
      expect(storage['representation'], 'storage');
    });
  });
}

/// `confluence_update_page` — GET current version, PUT `content/{id}`.
void updatePageTests() {
  group('ConfluenceClient.updatePage', () {
    test('fetches the version, then PUTs the bumped update payload', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/42': _updatedPage}, o),
      );
      final page = await f.client.updatePage(
        '42',
        'Updated Title',
        '7',
        '<p>updated</p>',
        'ENG',
      );
      expect(page['id'], '42');
      expect(f.adapter.calls.length, 2);
      final get = f.adapter.calls.first;
      expect(get.method, 'GET');
      expect(get.path, endsWith('/content/42'));
      expect(get.queryParameters['expand'], 'version');
      final put = f.adapter.calls.last;
      expect(put.method, 'PUT');
      expect(put.path, endsWith('/content/42'));
      final sent = jsonDecode(put.data as String) as Map<String, dynamic>;
      expect(sent['id'], '42');
      expect(sent['title'], 'Updated Title');
      expect(sent['ancestors'], [
        {'id': '7'},
      ]);
      expect(sent['space'], {'key': 'ENG'});
      expect(sent['version'], {'number': 3, 'message': ''});
      final storage = (sent['body'] as Map<String, dynamic>)['storage']
          as Map<String, dynamic>;
      expect(storage['value'], '<p>updated</p>');
    });
  });
}

/// `confluence_search` — GET `content/search`.
void searchTests() {
  group('ConfluenceClient.search', () {
    test('returns the results array for the CQL query', () async {
      final f = mockConfluence(
          (o) => routeByPath({'/content/search': _searchBody}, o));
      final results = await f.client.search('type = page');
      expect(results, hasLength(2));
      expect(results[0]['id'], '1');
      expect(results[1]['id'], '2');
      expect(f.adapter.calls.single.queryParameters['cql'], 'type = page');
    });

    test('returns empty list when no results', () async {
      final f = mockConfluence(
          (o) => routeByPath({'/content/search': '{"results":[]}'}, o));
      expect(await f.client.search('nothing'), isEmpty);
    });
  });
}

/// Canned `user/current` response body.
const _userBody = '{"displayName":"Dev User","email":"dev@example.com"}';

/// Canned `content` (get-by-title) response body.
final _getPageBody = jsonEncode({
  'results': [
    {
      'id': '42',
      'title': 'Design Doc',
      'body': {
        'storage': {'value': '<p>content</p>', 'representation': 'storage'},
      },
    },
  ],
});

/// Canned created page response.
const _createdPage = '{"id":"99","title":"New Page"}';

/// Canned updated page response.
const _updatedPage =
    '{"id":"42","title":"Updated Title","version":{"number":2}}';

/// Canned search response body.
final _searchBody = jsonEncode({
  'results': [
    {'id': '1', 'title': 'A'},
    {'id': '2', 'title': 'B'},
  ],
});
