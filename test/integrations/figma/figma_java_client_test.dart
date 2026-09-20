/// Tests for the Java-parity Figma client methods (`FigmaClient`):
/// file structure, icons, layers, text content, node details, image
/// rendering/downloads, team/project listings, and comments.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'figma_test_support.dart';

const _href = 'https://www.figma.com/file/abc123/Design?node-id=1-2';
const _hrefNoNode = 'https://www.figma.com/file/abc123/Design';

void main() {
  tearDown(() {
    PropertyReader.clearOverrides();
    final dir = Directory(_cacheDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  meTests();
  fileStructureTests();
  iconsTests();
  layersTests();
  childrenAndBatchTests();
  nodeChildrenGroup();
  textAndDetailsTests();
  stylesTests();
  imageTests();
  renderNodesTests();
  downloadTests();
  downloadFailureTests();
  listingsTests();
}

/// Cache dir used by the download tests (wiped in tearDown).
final _cacheDir = '${Directory.systemTemp.path}/figma_java_client_test_cache';

/// Serves routes by path suffix with JSON bodies.
MockFigmaFixture _routed(Map<String, String> routes) =>
    mockFigma((o) => routeByPath(routes, o));

void meTests() {
  group('FigmaClient.me (Java shape)', () {
    test('returns success with id/handle user map', () async {
      final f = _routed({
        '/me': '{"id":"u1","handle":"designer-1","email":"d@x.io"}',
      });
      final result = await f.client.me();
      expect(result['success'], isTrue);
      expect(result['message'], 'Figma API connection successful');
      expect(result['user'], {
        'id': 'u1',
        'handle': 'designer-1',
        'email': 'd@x.io',
      });
    });

    test('omits email when absent and defaults id/handle', () async {
      final f = _routed({'/me': '{"id":"u1"}'});
      final result = await f.client.me();
      expect(result['user'], {'id': 'u1', 'handle': 'unknown'});
    });

    test('reports unexpected format when no id/handle', () async {
      final f = _routed({'/me': '{"other":true}'});
      final result = await f.client.me();
      expect(result['success'], isFalse);
      expect(result['message'], 'Unexpected response format from Figma API');
    });

    test('reports empty response', () async {
      final f = _routed({'/me': ''});
      final result = await f.client.me();
      expect(result['success'], isFalse);
      expect(result['message'], 'Empty response from Figma API');
    });

    test('reports connection failure with the exception class name', () async {
      final f = mockFigma((o) => throw StateError('boom'));
      final result = await f.client.me();
      expect(result['success'], isFalse);
      expect(result['message'], contains('Figma API connection failed'));
      // The transport wraps the throw in its own exception type (the
      // Java client records e.getClass().getSimpleName() the same way).
      expect(result['error'], 'DioException');
    });

    test('meJson encodes the me map', () async {
      final f = _routed({'/me': '{"id":"u1","handle":"h"}'});
      final json = await f.client.meJson();
      expect(jsonDecode(json)['user'], {'id': 'u1', 'handle': 'h'});
    });
  });
}

void fileStructureTests() {
  group('FigmaClient.getFileStructure', () {
    test('fetches the full file with size-limiting params when no node-id',
        () async {
      final f = _routed({'/files/abc123': '{"name":"Design"}'});
      final result = await f.client.getFileStructure(_hrefNoNode);
      expect(result, {'name': 'Design'});
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/files/abc123'));
      expect(call.queryParameters, {'geometry': 'paths', 'depth': '2'});
    });

    test('fetches the node subtree when the URL carries a node-id', () async {
      final f = _routed({
        '/files/abc123/nodes': '{"nodes":{"1:2":{"document":{"id":"1:2"}}}}',
      });
      final result = await f.client.getFileStructure(_href);
      expect(result, contains('nodes'));
      expect(
        f.adapter.calls.single.queryParameters,
        {'ids': '1-2'},
      );
    });

    test('returns null when the request fails', () async {
      final f = mockFigma((o) => throw StateError('boom'));
      expect(await f.client.getFileStructure(_hrefNoNode), isNull);
    });

    test('unescapes &amp; in hrefs', () async {
      final f = _routed({'/files/abc123': '{}'});
      await f.client
          .getFileStructure('https://www.figma.com/file/abc123/D?a=1&amp;b=2');
      expect(f.adapter.calls.single.path, endsWith('/files/abc123'));
    });
  });
}

void iconsTests() {
  group('FigmaClient.getIcons', () {
    test('deduplicates components by node id', () async {
      final f = _routed({
        '/files/abc123': jsonEncode({
          'document': {
            'id': '0:0',
            'type': 'DOCUMENT',
            'children': [
              {
                'id': '1:1',
                'name': 'Icon',
                'type': 'FRAME',
                'absoluteBoundingBox': {'width': 24, 'height': 24},
                'children': [
                  {
                    'id': '2:2',
                    'name': 'glyph',
                    'type': 'VECTOR',
                    'absoluteBoundingBox': {'width': 24, 'height': 24},
                  },
                ],
              },
              {
                'id': '1:1',
                'name': 'Icon dup',
                'type': 'FRAME',
                'absoluteBoundingBox': {'width': 24, 'height': 24},
              },
            ],
          },
        }),
      });
      final result = await f.client.getIcons(_hrefNoNode);
      expect(result, isNotNull);
      expect(result!['fileId'], 'abc123');
      expect(result['totalIcons'], 2);
    });

    test('returns null when the structure fetch fails', () async {
      final f = mockFigma((o) => throw StateError('boom'));
      expect(await f.client.getIcons(_hrefNoNode), isNull);
    });
  });
}

void layersTests() {
  const nodesBody = '''
    {"nodes":{"1:2":{"document":{"id":"1:2","type":"FRAME","children":[
      {"id":"3:4","name":"Child","type":"TEXT",
       "absoluteBoundingBox":{"x":1,"y":2,"width":10,"height":20}}
    ]}}}}
  ''';

  group('FigmaClient.getLayers', () {
    test('returns first-level layers of the URL node', () async {
      final f = _routed({'/files/abc123/nodes': nodesBody});
      final result = await f.client.getLayers(_href);
      expect(result, isNotNull);
      expect(result!['parentNodeId'], '1-2');
      expect(result['children'], [
        {
          'id': '3:4',
          'name': 'Child',
          'type': 'TEXT',
          'width': 10.0,
          'height': 20.0,
          'x': 1.0,
          'y': 2.0,
          'visible': true,
        },
      ]);
      expect(
        f.adapter.calls.single.queryParameters['ids'],
        '1-2',
      );
    });

    test('returns null when the node has no children', () async {
      final f = _routed({
        '/files/abc123/nodes':
            '{"nodes":{"1:2":{"document":{"id":"1:2","type":"FRAME"}}}}',
      });
      expect(await f.client.getLayers(_href), isNull);
    });

    test('returns null when the href has no node-id (Java parity)', () async {
      final f = mockFigma((o) => throw StateError('must not be called'));
      expect(await f.client.getLayers(_hrefNoNode), isNull);
    });
  });
}

void childrenAndBatchTests() {
  const nodesBody = '''
    {"nodes":{"1:2":{"document":{"id":"1:2","type":"FRAME","children":[
      {"id":"3:4","name":"Child","type":"TEXT",
       "absoluteBoundingBox":{"x":1,"y":2,"width":10,"height":20}}
    ]}}}}
  ''';

  group('FigmaClient.getLayersBatch', () {
    test('maps each found node by colon id', () async {
      final f = _routed({'/files/abc123/nodes': nodesBody});
      final result = await f.client.getLayersBatch(
        _hrefNoNode,
        '1-2, 9:9',
      );
      expect(result.keys, ['1:2']);
      expect(result['1:2']!['parentNodeId'], '1:2');
      expect(
        f.adapter.calls.single.queryParameters['ids'],
        '1-2, 9:9',
      );
    });

    test('returns an empty map on failure', () async {
      final f = mockFigma((o) => throw StateError('boom'));
      final result = await f.client.getLayersBatch(_hrefNoNode, '1:2');
      expect(result, isEmpty);
    });
  });
}

void nodeChildrenGroup() {
  const nodesBody = '''
    {"nodes":{"1:2":{"document":{"id":"1:2","type":"FRAME","children":[
      {"id":"3:4","name":"Child","type":"TEXT",
       "absoluteBoundingBox":{"x":1,"y":2,"width":10,"height":20}}
    ]}}}}
  ''';

  group('FigmaClient.getNodeChildren', () {
    test('requests depth 1 and wraps children', () async {
      // Unencoded colon id: Java looks the node up by the raw query
      // value, so percent-encoded colon URLs would miss (parity).
      const colonHref = 'https://www.figma.com/file/abc123/Design?node-id=1:2';
      final f = _routed({'/files/abc123/nodes': nodesBody});
      final result = await f.client.getNodeChildren(colonHref);
      expect(result, isNotNull);
      expect(result!['parentNodeId'], '1:2');
      expect((result['children'] as List).single['id'], '3:4');
      expect(
        f.adapter.calls.single.queryParameters,
        {'ids': '1:2', 'depth': '1'},
      );
    });

    test('returns null when the node is absent from the response', () {
      final f = _routed({'/files/abc123/nodes': nodesBody});
      // Dashed id does not match the colon-keyed response (Java parity).
      return expectLater(
        f.client.getNodeChildren(_href),
        completion(isNull),
      );
    });
  });
}

void textAndDetailsTests() {
  const textBody = '''
    {"nodes":{"10:1":{"document":{"id":"10:1","type":"TEXT",
      "characters":"Hi","style":{"fontFamily":"Inter","fontSize":14}}},
      "11:1":{"document":{"id":"11:1","type":"FRAME","name":"F"}}}}
  ''';

  group('FigmaClient.getTextContent', () {
    test('extracts TEXT nodes only, capped at 20 ids', () async {
      final f = _routed({'/files/abc123/nodes': textBody});
      final manyIds = [
        for (var i = 0; i < 25; i++) '10:1',
      ].join(',');
      final result = await f.client.getTextContent(_hrefNoNode, manyIds);
      expect(result, isNotNull);
      final textNodes = result!['textNodes'] as Map<String, dynamic>;
      expect(textNodes.keys, ['10:1']);
      final ids = f.adapter.calls.single.queryParameters['ids'] as String;
      expect(ids.split(','), hasLength(20));
    });
  });

  group('FigmaClient.getNodeDetails', () {
    test('returns the first node document, capped at 10 ids', () async {
      final f = _routed({'/files/abc123/nodes': textBody});
      final manyIds = [for (var i = 0; i < 15; i++) '10:1'].join(', ');
      final result = await f.client.getNodeDetails(_hrefNoNode, manyIds);
      expect(result, {
        'id': '10:1',
        'type': 'TEXT',
        'characters': 'Hi',
        'style': {'fontFamily': 'Inter', 'fontSize': 14}
      });
      final ids = f.adapter.calls.single.queryParameters['ids'] as String;
      expect(ids.split(','), hasLength(10));
      expect(ids.startsWith('10:1,10:1'), isTrue);
    });

    test('returns null when no node data is present', () async {
      final f = _routed({'/files/abc123/nodes': '{"nodes":{}}'});
      expect(await f.client.getNodeDetails(_hrefNoNode, '1:2'), isNull);
    });
  });
}

void stylesTests() {
  group('FigmaClient.getDesignStyles (Java figma_get_styles parity)', () {
    test('returns the empty token envelope', () async {
      final f = _routed({'/styles': '{"meta":{"styles":[]}}'});
      final result = await f.client.getDesignStyles(_hrefNoNode);
      expect(result, {'colorStyles': [], 'textStyles': []});
      // Java still issues the request.
      expect(f.adapter.calls.single.path, endsWith('/files/abc123/styles'));
    });
  });
}

void imageTests() {
  group('FigmaClient.getImageFills', () {
    test('returns the raw images response', () async {
      final f = _routed({
        '/files/abc123/images': '{"images":{"1:1":"https://cdn/x.png"}}',
      });
      final result = await f.client.getImageFills(_hrefNoNode);
      expect(jsonDecode(result), {
        'images': {'1:1': 'https://cdn/x.png'}
      });
    });
  });
}

void renderNodesTests() {
  group('FigmaClient.renderNodes', () {
    test('batches 100 ids per request and merges image maps', () async {
      String imagesBody(int from) => jsonEncode({
            'images': {
              for (var i = from; i < from + 100; i++)
                '$i:1': 'https://cdn/$i.png',
            },
          });
      var batch = 0;
      final f = mockFigma((o) {
        batch++;
        return imagesBody((batch - 1) * 100);
      });
      final ids = [for (var i = 0; i < 150; i++) '$i:1'].join(',');
      final result = await f.client.renderNodes(_hrefNoNode, ids);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      // Two batches; the mock returns 100 entries per batch (the second
      // batch pads past the requested 150 ids).
      expect(decoded.length, 200);
      expect(decoded['0:1'], 'https://cdn/0.png');
      expect(decoded['149:1'], 'https://cdn/149.png');
      expect(f.adapter.calls, hasLength(2));
    });

    test('defaults to png format', () async {
      final f = _routed({'/images/abc123': '{"images":{}}'});
      await f.client.renderNodes(_hrefNoNode, '1:1');
      expect(
        f.adapter.calls.single.queryParameters['format'],
        'png',
      );
    });
  });

  group('FigmaClient.getImageOfSource', () {
    test('returns the image URL for the URL node', () async {
      final f = _routed({
        '/images/abc123': '{"images":{"1:2":"https://cdn/s.png"}}',
      });
      final result = await f.client.getImageOfSource(_href);
      expect(result, 'https://cdn/s.png');
    });

    test('returns null when the request fails', () async {
      final f = mockFigma((o) => throw StateError('boom'));
      expect(await f.client.getImageOfSource(_href), isNull);
    });
  });
}

void downloadTests() {
  group('downloads', () {
    test('downloadNodeImage fetches with defaults and caches by md5', () async {
      var fetches = 0;
      final f = mockFigmaHttp((o) {
        fetches++;
        if (o.path.endsWith('/images/abc123')) {
          return '{"images":{"1-2":"https://cdn.example.com/images/x.png"}}';
        }
        return 'PNG-DATA';
      });
      final client = FigmaClient(f.http, cacheDir: _cacheDir);
      final path1 = await client.downloadNodeImage(_href, '1-2');
      expect(path1, isNotNull);
      expect(File(path1!).readAsStringSync(), 'PNG-DATA');
      expect(fetches, 2);
      // Second call re-requests the render URL (Java parity) but serves
      // the image itself from cache — a cache miss would be 4 fetches.
      final path2 = await client.downloadNodeImage(_href, '1-2');
      expect(path2, path1);
      expect(fetches, 3);
    });

    test('downloadNodeImage returns null when the node has no image URL',
        () async {
      final f = mockFigmaHttp((o) => '{"images":{}}');
      final client = FigmaClient(f.http, cacheDir: _cacheDir);
      expect(await client.downloadNodeImage(_href, '9:9'), isNull);
    });

    test('downloadImage writes non-UTF-8 bytes verbatim', () async {
      // A real PNG header plus bytes invalid in UTF-8: any String
      // decode/encode round trip replaces them with U+FFFD (EF BF BD).
      final pngBytes = List<int>.unmodifiable([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0x00, 0xFF, 0xFE, 0xFD, 0x10,
      ]);
      final f = mockFigmaHttpBytes((o) => Uint8List.fromList(pngBytes));
      final client = FigmaClient(f.http, cacheDir: _cacheDir);
      final path = await client
          .downloadImage('https://cdn.example.com/images/bin-v2.png');
      expect(File(path).readAsBytesSync(), pngBytes);
    });
  });
}

void downloadFailureTests() {
  group('download failures', () {
    test('convertUrlToFile returns null when the source is not http', () async {
      final f = mockFigmaHttp((o) => '{"images":{"1:2":null}}');
      final client = FigmaClient(f.http, cacheDir: _cacheDir);
      expect(await client.convertUrlToFile(_href), isNull);
    });

    test('downloadIconFile downloads with the requested format', () async {
      final f = mockFigmaHttp((o) {
        if (o.path.endsWith('/images/abc123')) {
          return '{"images":{"5:6":"https://cdn.example.com/images/i.svg"}}';
        }
        return '<svg/>';
      });
      final client = FigmaClient(f.http, cacheDir: _cacheDir);
      final path = await client.downloadIconFile(_hrefNoNode, '5:6', 'svg');
      expect(File(path!).readAsStringSync(), '<svg/>');
      final call = f.adapter.calls.first;
      expect(call.queryParameters['format'], 'svg');
    });

    test('getSvgContent fetches the SVG text', () async {
      final f = mockFigmaHttp((o) {
        if (o.path.endsWith('/images/abc123')) {
          return '{"images":{"5:6":"https://cdn.example.com/images/i.svg"}}';
        }
        return '<svg></svg>';
      });
      final svg = await FigmaClient(f.http).getSvgContent(_hrefNoNode, '5:6');
      expect(svg, '<svg></svg>');
    });
  });
}

void listingsTests() {
  group('FigmaClient.listTeamProjects', () {
    test('accepts a team URL and returns the projects array', () async {
      final f = _routed({
        '/teams/1633438210497791577/projects':
            '{"projects":[{"id":"1","name":"P"}]}',
      });
      final result = await f.client.listTeamProjects(
        'https://www.figma.com/files/1008118788610687562/team/1633438210497791577',
      );
      expect(result, [
        {'id': '1', 'name': 'P'},
      ]);
    });

    test('accepts a raw team id', () async {
      final f = _routed({'/teams/42/projects': '{"projects":[]}'});
      expect(await f.client.listTeamProjects('42'), isEmpty);
    });
  });

  group('FigmaClient.listProjectFiles', () {
    test('accepts a project URL and returns the files array', () async {
      final f = _routed({
        '/projects/123456789/files':
            '{"files":[{"key":"k","name":"F","thumbnail_url":"t"}]}',
      });
      final result = await f.client
          .listProjectFiles('https://www.figma.com/files/project/123456789');
      expect(result, [
        {'key': 'k', 'name': 'F', 'thumbnail_url': 't'},
      ]);
    });
  });

  group('FigmaClient.getFileComments', () {
    test('parses the file key from a URL', () async {
      final f = _routed({
        '/files/abc123/comments': '{"comments":[{"id":"c1","message":"m"}]}',
      });
      final result = await f.client.getFileComments(_hrefNoNode);
      expect(result, [
        {'id': 'c1', 'message': 'm'},
      ]);
    });

    test('falls back to treating the argument as a raw key', () async {
      final f = _routed({
        '/files/rawkey/comments': '{"comments":[]}',
      });
      final result = await f.client.getFileComments('rawkey');
      expect(result, isEmpty);
    });
  });
}
