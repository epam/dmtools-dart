import 'dart:convert';

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
    _testStructureEchoTools();
    _testContentEchoTools();
  }
}

Map<String, String> _config(int port) => {
      'FIGMA_TOKEN': 'figma-token',
      'FIGMA_BASE_PATH': 'http://127.0.0.1:$port/v1',
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
