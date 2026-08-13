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
  getCommentsTests();
  postCommentTests();
  getComponentsTests();
  getComponentSetsTests();
  getStylesTests();
  exportImageTests();
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

/// `figma_get_comments` — GET `/files/{key}/comments`.
void getCommentsTests() {
  group('FigmaClient.getComments', () {
    test('returns the decoded comments map', () async {
      final f = mockFigma(
        (o) => routeByPath({'/comments': _commentsBody}, o),
      );
      final comments = await f.client.getComments('aBc123');
      expect(comments['comments'], isA<List>());
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/files/aBc123/comments'));
    });
  });
}

/// `figma_post_comment` — POST `/files/{key}/comments`.
void postCommentTests() {
  group('FigmaClient.postComment', () {
    test('posts the message and returns the created comment', () async {
      final f = mockFigma(
        (o) => routeByPath({'/comments': _commentCreatedBody}, o),
      );
      final result = await f.client.postComment('aBc123', 'Nice work!');
      expect(result['id'], 'c1');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/files/aBc123/comments'));
      expect(call.data, '{"message":"Nice work!"}');
    });
  });
}

/// `figma_get_components` — GET `/files/{key}/components`.
void getComponentsTests() {
  group('FigmaClient.getComponents', () {
    test('returns the decoded components map', () async {
      final f = mockFigma(
        (o) => routeByPath({'/components': _componentsBody}, o),
      );
      final components = await f.client.getComponents('aBc123');
      expect(components['meta'], isA<Map>());
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/files/aBc123/components'));
    });
  });
}

/// `figma_get_component_sets` — GET `/files/{key}/component_sets`.
void getComponentSetsTests() {
  group('FigmaClient.getComponentSets', () {
    test('returns the decoded component-sets map', () async {
      final f = mockFigma(
        (o) => routeByPath({'/component_sets': _componentSetsBody}, o),
      );
      final sets = await f.client.getComponentSets('aBc123');
      expect(sets['meta'], isA<Map>());
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/files/aBc123/component_sets'));
    });
  });
}

/// `figma_get_styles` — GET `/files/{key}/styles`.
void getStylesTests() {
  group('FigmaClient.getStyles', () {
    test('returns the decoded styles map', () async {
      final f = mockFigma(
        (o) => routeByPath({'/styles': _stylesBody}, o),
      );
      final styles = await f.client.getStyles('aBc123');
      expect(styles['meta'], isA<Map>());
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/files/aBc123/styles'));
    });
  });
}

/// `figma_export_image` — GET `/images/{key}` with optional format/scale.
void exportImageTests() {
  group('FigmaClient.exportImage', () {
    test('sends format and scale when provided', () async {
      final f = mockFigma(
        (o) => routeByPath({'/images/aBc123': _imageBody}, o),
      );
      final image = await f.client.exportImage(
        'aBc123',
        format: 'svg',
        scale: 2,
      );
      expect(image['images'], isA<Map>());
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/images/aBc123'));
      expect(call.queryParameters['format'], 'svg');
      expect(call.queryParameters['scale'], 2);
    });

    test('omits format and scale when not provided', () async {
      final f = mockFigma(
        (o) => routeByPath({'/images/aBc123': _imageBody}, o),
      );
      await f.client.exportImage('aBc123');
      final call = f.adapter.calls.single;
      expect(call.queryParameters['format'], isNull);
      expect(call.queryParameters['scale'], isNull);
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

/// Canned `/files/{key}/comments` response body.
const _commentsBody = '{"comments":[{"id":"c1","message":"hello"}]}';

/// Canned POST `/files/{key}/comments` response body.
const _commentCreatedBody = '{"id":"c1","message":"Nice work!"}';

/// Canned `/files/{key}/components` response body.
const _componentsBody =
    '{"meta":{"components":[{"key":"btn","name":"Button"}]}}';

/// Canned `/files/{key}/component_sets` response body.
const _componentSetsBody =
    '{"meta":{"component_sets":[{"key":"btn-set","name":"Button/Set"}]}}';

/// Canned `/files/{key}/styles` response body.
const _stylesBody = '{"meta":{"styles":[{"key":"red","name":"Red"}]}}';
