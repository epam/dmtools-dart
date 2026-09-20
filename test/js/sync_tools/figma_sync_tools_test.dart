import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/figma_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

/// Tests for [FigmaSyncTools] — the Figma section of the sync tool bridge
/// (Java `FigmaClient` @MCPTool parity).
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _testRoutingAndConfig();
  _testOauthRouting();
  if (hasPython3()) {
    _testMeEchoTools();
    _testStructureEchoTools();
    _testListingEchoTools();
    _testContentEchoTools();
    _testLayersEchoTools();
    _testSvgEchoTools();
    _testDownloadEchoTools();
  }
}

Map<String, String> _config(int port) => {
      'FIGMA_TOKEN': 'figma-token',
      'FIGMA_BASE_PATH': 'http://127.0.0.1:$port/v1',
    };

/// Config whose base path carries a fixture marker the echo server
/// routes on (`/figsvg`, `/figdl`, `/figlayers`).
Map<String, String> _markerConfig(int port, String marker) => {
      'FIGMA_TOKEN': 'figma-token',
      'FIGMA_BASE_PATH': 'http://127.0.0.1:$port/$marker/v1',
    };

void _testRoutingAndConfig() {
  group('FigmaSyncTools routing and config', () {
    late FigmaSyncTools tools;

    setUp(() {
      PropertyReader.setOverrides({'FIGMA_TOKEN': ''});
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('unsupported tool returns error JSON', () {
      expect(
        jsonDecode(tools.dispatch('figma_mystery', {})),
        {'error': 'Unsupported Figma tool: figma_mystery'},
      );
    });

    test('handlers map exposes the full Java tool catalog', () {
      expect(tools.handlers.keys, [
        'figma_oauth2_get_auth_url',
        'figma_oauth2_exchange_code',
        'figma_test',
        'figma_me',
        'figma_get_screen_source',
        'figma_download_node_image',
        'figma_download_image_of_file',
        'figma_get_file_structure',
        'figma_get_icons',
        'figma_get_image_fills',
        'figma_render_nodes',
        'figma_download_image_as_file',
        'figma_get_svg_content',
        'figma_get_node_details',
        'figma_get_text_content',
        'figma_get_styles',
        'figma_get_layers',
        'figma_get_layers_batch',
        'figma_get_node_children',
        'figma_list_team_projects',
        'figma_list_project_files',
        'figma_get_file_comments',
      ]);
    });

    test('figma not configured returns error JSON', () {
      expect(
        jsonDecode(tools.dispatch('figma_me', {})),
        {'error': 'Figma not configured'},
      );
    });
  });
}

void _testOauthRouting() {
  group('FigmaSyncTools OAuth routing', () {
    late FigmaSyncTools tools;

    setUp(() {
      PropertyReader.setOverrides({'FIGMA_TOKEN': ''});
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('oauth2_get_auth_url reports a missing client id', () {
      expect(
        jsonDecode(tools.dispatch('figma_oauth2_get_auth_url', {})),
        {'error': 'FIGMA_CLIENT_ID is not configured'},
      );
    });

    test('oauth2_exchange_code requires client credentials', () {
      expect(
        jsonDecode(
          tools.dispatch('figma_oauth2_exchange_code', {'code': 'c'}),
        ),
        {
          'error': 'FIGMA_CLIENT_ID and FIGMA_CLIENT_SECRET must be configured',
        },
      );
    });

    test('oauth2_exchange_code reports a missing redirect URI', () {
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
      });
      expect(
        jsonDecode(
          tools.dispatch('figma_oauth2_exchange_code', {'code': 'c'}),
        ),
        {
          'error':
              'redirectUri is required (or set FIGMA_REDIRECT_URI in dmtools.env)',
        },
      );
    });

    test('oauth2_get_auth_url builds the URL from env config', () {
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://cb/',
      });
      final result = jsonDecode(
        tools.dispatch('figma_oauth2_get_auth_url', {'state': 'st'}),
      ) as Map<String, dynamic>;
      expect(
        result['authorization_url'],
        'https://www.figma.com/oauth?client_id=cid'
        '&redirect_uri=http%3A%2F%2Fcb%2F'
        '&scope=file_content%3Aread+file_metadata%3Aread'
        '&state=st&response_type=code',
      );
    });
  });
}

void _testStructureEchoTools() {
  group('FigmaSyncTools structure tools over the echo server', () {
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      PropertyReader.setOverrides(_config(server.port));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_test maps the /me response through the Java me() shape', () {
      // The echo body is a JSON object without id/handle.
      final result =
          jsonDecode(tools.dispatch('figma_test', {})) as Map<String, dynamic>;
      expect(result['success'], isFalse);
      expect(result['message'], 'Unexpected response format from Figma API');
    });

    test('figma_get_layers returns JSON null without matching nodes', () {
      expect(
        tools.dispatch('figma_get_layers', {
          'href': 'https://www.figma.com/file/abc123/Design?node-id=1-2',
        }),
        'null',
      );
    });

    test('figma_get_node_children returns JSON null without a document', () {
      expect(
        tools.dispatch('figma_get_node_children', {
          'href': 'https://www.figma.com/file/abc123/Design?node-id=1:2',
        }),
        'null',
      );
    });
  });
}

void _testMeEchoTools() {
  group('FigmaSyncTools me/icons over the echo server', () {
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      PropertyReader.setOverrides(_config(server.port));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_get_styles returns the empty token envelope', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_styles', {
          'href': 'https://www.figma.com/file/abc123/Design',
        }),
      );
      expect(result, {'colorStyles': [], 'textStyles': []});
    });

    test('figma_get_icons parses the file key and deduplicates', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_icons', {
          'href': 'https://www.figma.com/file/abc123/Design',
        }),
      ) as Map<String, dynamic>;
      expect(result['fileId'], 'abc123');
      expect(result['totalIcons'], 0);
    });
  });
}

void _testContentEchoTools() {
  group('FigmaSyncTools content tools over the echo server', () {
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      PropertyReader.setOverrides(_config(server.port));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_render_nodes merges batches', () {
      // The echo body carries no images map.
      final result = jsonDecode(
        tools.dispatch('figma_render_nodes', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeIds': '1:1,2:2',
        }),
      );
      expect(result, {});
    });

    test('figma_get_image_fills returns the raw body', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_image_fills', {
          'href': 'https://www.figma.com/file/abc123/Design',
        }),
      ) as Map<String, dynamic>;
      expect(result['method'], 'GET');
      expect(result['path'], '/v1/files/abc123/images');
    });

    test('figma_get_file_structure hits the node endpoint for node URLs', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_file_structure', {
          'href': 'https://www.figma.com/file/abc123/Design?node-id=1-2',
        }),
      ) as Map<String, dynamic>;
      expect(result['method'], 'GET');
      expect(result['path'], '/v1/files/abc123/nodes?ids=1-2');
    });
  });
}

void _testListingEchoTools() {
  group('FigmaSyncTools listing tools over the echo server', () {
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      PropertyReader.setOverrides(_config(server.port));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_list_team_projects accepts a team URL', () {
      final result = jsonDecode(
        tools.dispatch('figma_list_team_projects', {
          'teamIdOrUrl':
              'https://www.figma.com/files/1/team/1633438210497791577',
        }),
      );
      // The echo response carries no projects array.
      expect(result, []);
    });

    test('figma_list_project_files accepts a raw id', () {
      final result = jsonDecode(
        tools.dispatch('figma_list_project_files', {'projectIdOrUrl': '77'}),
      );
      expect(result, []);
    });

    test('figma_get_file_comments treats a raw key as the file key', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_file_comments', {'href': 'rawkey'}),
      );
      expect(result, []);
    });
  });
}

void _testLayersEchoTools() {
  group('FigmaSyncTools layers tools over the echo server', () {
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      PropertyReader.setOverrides(_markerConfig(server.port, 'figlayers'));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_get_layers_batch maps dashed ids and skips null documents', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_layers_batch', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeIds': ' 1-2 , 3-4 , 7-7 ',
        }),
      ) as Map<String, dynamic>;
      // 7:7 carries a null document on the fixture: only 1:2 and 3:4 map.
      expect(result.keys, ['1:2', '3:4']);
      final layer = result['1:2'] as Map<String, dynamic>;
      expect(layer['parentNodeId'], '1:2');
      final children = layer['children'] as List<dynamic>;
      expect(children, hasLength(1));
      final child = children.first as Map<String, dynamic>;
      expect(child['id'], '1:2:1');
      expect(child['name'], 'Child');
      expect(child['type'], 'RECTANGLE');
      expect(child['width'], 3);
      expect(child['height'], 4);
      expect(child['x'], 1);
      expect(child['y'], 2);
      expect(child['visible'], isFalse);
    });

    test('figma_get_layers_batch caps the request at 10 node ids', () {
      final nodeIds = [for (var i = 1; i <= 12; i++) '1-$i'].join(',');
      final result = jsonDecode(
        tools.dispatch('figma_get_layers_batch', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeIds': nodeIds,
        }),
      ) as Map<String, dynamic>;
      expect(result.keys, hasLength(10));
      expect(result.containsKey('1:10'), isTrue);
      expect(result.containsKey('1:11'), isFalse);
    });
  });
}

void _testSvgEchoTools() {
  group('FigmaSyncTools svg tool over the echo server', () {
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      PropertyReader.setOverrides(_markerConfig(server.port, 'figsvg'));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_get_svg_content returns the SVG body of the node', () {
      final result = jsonDecode(
        tools.dispatch('figma_get_svg_content', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '1:2',
        }),
      );
      expect(result, '<svg xmlns="http://www.w3.org/2000/svg"></svg>');
    });

    test('figma_get_svg_content returns JSON null without an image URL', () {
      expect(
        tools.dispatch('figma_get_svg_content', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '3:3',
        }),
        'null',
      );
    });

    test('figma_get_svg_content returns JSON null on a failed fetch', () {
      expect(
        tools.dispatch('figma_get_svg_content', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '2:2',
        }),
        'null',
      );
    });
  });
}

void _testDownloadEchoTools() {
  group('FigmaSyncTools download tools over the echo server', () {
    final cacheDir = Directory(
      '${Directory.systemTemp.path}/dmtools_figma_cache',
    );
    final expectedPngBytes = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      ...'figdl-fixture-bytes'.codeUnits,
    ];
    late EchoServer server;
    late FigmaSyncTools tools;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    setUp(() {
      // Clear the md5 cache so the curl download branch runs every time.
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
      PropertyReader.setOverrides(_markerConfig(server.port, 'figdl'));
      tools = FigmaSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('figma_download_image_as_file downloads into the md5 cache', () {
      final result = jsonDecode(
        tools.dispatch('figma_download_image_as_file', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '1:2',
          'format': 'png',
        }),
      ) as String;
      final file = File(result);
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), expectedPngBytes);
    });

    test('figma_download_image_as_file reuses the cached file', () {
      final args = <String, dynamic>{
        'href': 'https://www.figma.com/file/abc123/Design',
        'nodeId': '1:2',
        'format': 'png',
      };
      final first = jsonDecode(tools.dispatch(
        'figma_download_image_as_file',
        args,
      )) as String;
      final second = jsonDecode(tools.dispatch(
        'figma_download_image_as_file',
        args,
      )) as String;
      expect(second, first);
      expect(File(second).existsSync(), isTrue);
    });

    test(
        'figma_download_image_as_file returns JSON null when the '
        'download fails', () {
      expect(
        tools.dispatch('figma_download_image_as_file', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '2:2',
          'format': 'png',
        }),
        'null',
      );
    });

    test('figma_download_node_image renders and downloads the node', () {
      final result = jsonDecode(
        tools.dispatch('figma_download_node_image', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '1:2',
        }),
      ) as String;
      expect(File(result).existsSync(), isTrue);
    });

    test(
        'figma_download_node_image returns JSON null without an image '
        'URL', () {
      expect(
        tools.dispatch('figma_download_node_image', {
          'href': 'https://www.figma.com/file/abc123/Design',
          'nodeId': '3:3',
        }),
        'null',
      );
    });
  });
}
