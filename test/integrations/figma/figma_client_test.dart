import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'figma_test_support.dart';

/// Coverage + behavior tests for [FigmaClient] and [FigmaHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getFileTests();
  getFileNodesTests();
  getImageTests();
}

/// The base path injected by the fixture's config.
const _basePath = 'https://figma.example.com/v1';

/// [FigmaHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('FigmaHttpClient', () {
    test('builds Figma API URLs from the configured base path', () {
      final f = mockFigmaHttp((o) => '{}');
      expect(
        f.http.buildUrl('me'),
        '$_basePath/me',
      );
    });

    test('assembles Authorization and content headers', () {
      final f = mockFigmaHttp((o) => '{}');
      expect(f.http.headers['Authorization'], 'Bearer figma-token-abc');
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get returns the response body', () async {
      final f = mockFigmaHttp((o) => routeByPath({'/me': 'GET-ME'}, o));
      expect(await f.http.get('me'), 'GET-ME');
      f.http.close();
    });

    test('throws StateError when FIGMA_TOKEN is missing', () {
      PropertyReader.clearOverrides();
      expect(() => FigmaHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when FIGMA_TOKEN is empty', () {
      PropertyReader.setOverrides({'FIGMA_TOKEN': ''});
      expect(() => FigmaHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `figma_test` — connectivity check via GET `/me`.
void testConnectionTests() {
  group('FigmaClient.testConnection', () {
    test('returns success with the user handle', () async {
      final f = mockFigma((o) => routeByPath({'/me': _meBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Figma connection successful');
      expect(result['user'], 'designer-1');
      expect(f.adapter.calls.single.path, endsWith('/me'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockFigma((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `figma_get_file` — GET `/files/{key}`.
void getFileTests() {
  group('FigmaClient.getFile', () {
    test('returns the decoded file map', () async {
      final f = mockFigma((o) => routeByPath({'/files/aBc123': _fileBody}, o));
      final file = await f.client.getFile('aBc123');
      expect(file['key'], 'aBc123');
      expect(file['name'], 'Design System');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/files/aBc123'));
    });
  });
}

/// `figma_get_file_nodes` — GET `/files/{key}/nodes?ids={nodeIds}`.
void getFileNodesTests() {
  group('FigmaClient.getFileNodes', () {
    test('returns the decoded nodes map with ids query', () async {
      final f = mockFigma(
        (o) => routeByPath({'/nodes': _nodesBody}, o),
      );
      final nodes = await f.client.getFileNodes('aBc123', '1:2,3:4');
      expect(nodes['nodes'], isNotNull);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/files/aBc123/nodes'));
      expect(call.queryParameters['ids'], '1:2,3:4');
    });
  });
}

/// `figma_get_image` — GET `/images/{key}?ids={nodeId}`.
void getImageTests() {
  group('FigmaClient.getImage', () {
    test('returns the decoded image map with ids query', () async {
      final f = mockFigma(
        (o) => routeByPath({'/images/aBc123': _imageBody}, o),
      );
      final image = await f.client.getImage('aBc123', '1:2');
      expect(image['images'], isA<Map>());
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/images/aBc123'));
      expect(call.queryParameters['ids'], '1:2');
    });
  });
}

/// Canned `/me` response body.
const _meBody = '{"handle":"designer-1","email":"d@example.com"}';

/// Canned `/files/{key}` response body.
const _fileBody = '{"key":"aBc123","name":"Design System"}';

/// Canned `/files/{key}/nodes` response body.
const _nodesBody =
    '{"nodes":{"1:2":{"document":{"id":"1:2"}},"3:4":{"document":{"id":"3:4"}}}}';

/// Canned `/images/{key}` response body.
const _imageBody = '{"images":{"1:2":"https://cdn.example.com/img.png"}}';
