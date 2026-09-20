import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'figma_test_support.dart';

/// Tests for the [figmaTools] catalog and [FigmaToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogTests();
  catalogParamTests();
  executorRoutingTests();
  javaCatalogRoutingTests();
  oauthExecutorTests();
  commentComponentStyleExportRoutingTests();
  libraryVariableRoutingTests();
  nodeStyleRoutingTests();
  executorEdgeCaseTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    figmaTools().firstWhere((t) => t.name == name);

/// Serves `{}` for every request.
String _spyRouter(RequestOptions o) => '{}';

/// Catalog shape: tool count, order, and integration ownership.
void catalogTests() {
  group('figmaTools catalog', () {
    final tools = figmaTools();

    test('registers the Java catalog first, then the legacy REST tools', () {
      expect(tools.map((t) => t.name), [
        // Java auth + user tools.
        'figma_oauth2_get_auth_url',
        'figma_oauth2_exchange_code',
        'figma_test',
        'figma_me',
        // Java content-access tools.
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
        'figma_get_node_children',
        'figma_list_team_projects',
        'figma_list_project_files',
        'figma_get_file_comments',
        // Java structure-analysis tools.
        'figma_get_layers',
        'figma_get_layers_batch',
        // Legacy Dart REST-shaped tools.
        'figma_get_file',
        'figma_get_file_nodes',
        'figma_get_node',
        'figma_get_image',
        'figma_export_image',
        'figma_get_comments',
        'figma_post_comment',
        'figma_get_components',
        'figma_get_file_components',
        'figma_get_component_sets',
        'figma_get_style',
        'figma_get_variable_collections',
        'figma_get_library_components',
      ]);
    });

    test('every tool belongs to the figma integration', () {
      expect(tools.every((t) => t.integration == 'figma'), isTrue);
    });
  });
}

/// Legacy tools whose params are all required, checked data-driven.
const _requiredParamTools = <(String, List<String>)>[
  ('figma_get_file', ['key']),
  ('figma_get_file_nodes', ['key', 'node_ids']),
  ('figma_get_node', ['key', 'node_id']),
  ('figma_get_image', ['key', 'node_id']),
  ('figma_get_comments', ['key']),
  ('figma_post_comment', ['key', 'message']),
  ('figma_get_components', ['key']),
  ('figma_get_file_components', ['key']),
  ('figma_get_component_sets', ['key']),
  ('figma_get_style', ['key']),
  ('figma_get_variable_collections', ['key']),
  ('figma_get_library_components', ['library_key']),
];

/// Param-shape checks for every tool.
void catalogParamTests() {
  group('legacy param shapes (all required)', () {
    for (final (name, params) in _requiredParamTools) {
      test('$name declares ${params.join(', ')}', () {
        final tool = toolNamed(name);
        expect(tool.params.map((p) => p.name), params);
        expect(tool.params.every((p) => p.required), isTrue);
      });
    }
  });

  group('figma_export_image', () {
    final tool = toolNamed('figma_export_image');

    test('declares required key with optional format, scale', () {
      expect(tool.params.map((p) => p.name), ['key', 'format', 'scale']);
      expect(tool.params.first.required, isTrue);
      expect(tool.params[1].required, isFalse);
      expect(tool.params[2].required, isFalse);
      expect(tool.params[2].type, 'number');
    });
  });

  group('Java catalog param shapes', () {
    const requiredHrefTools = [
      'figma_download_image_of_file',
      'figma_get_file_structure',
      'figma_get_icons',
      'figma_get_image_fills',
      'figma_get_node_children',
      'figma_get_styles',
      'figma_get_file_comments',
      'figma_get_layers',
    ];
    for (final name in requiredHrefTools) {
      test('$name declares a single required href', () {
        final tool = toolNamed(name);
        expect(tool.params.map((p) => p.name), ['href']);
        expect(tool.params.single.required, isTrue);
      });
    }

    test('figma_oauth2_get_auth_url params are all optional', () {
      final tool = toolNamed('figma_oauth2_get_auth_url');
      expect(
        tool.params.map((p) => p.name),
        ['redirectUri', 'state', 'scope'],
      );
      expect(tool.params.every((p) => !p.required), isTrue);
    });

    test('figma_oauth2_exchange_code requires code only', () {
      final tool = toolNamed('figma_oauth2_exchange_code');
      expect(tool.params.map((p) => p.name), ['code', 'redirectUri']);
      expect(tool.params.map((p) => p.required), [true, false]);
    });

    test('figma_test and figma_me take no params', () {
      expect(toolNamed('figma_test').params, isEmpty);
      expect(toolNamed('figma_me').params, isEmpty);
    });

    test('figma_download_node_image has optional format and numeric scale',
        () {
      final tool = toolNamed('figma_download_node_image');
      expect(
        tool.params.map((p) => p.name),
        ['href', 'nodeId', 'format', 'scale'],
      );
      expect(tool.params.map((p) => p.required), [true, true, false, false]);
      expect(tool.params[3].type, 'number');
    });

    test('figma_render_nodes requires nodeIds with optional format', () {
      final tool = toolNamed('figma_render_nodes');
      expect(tool.params.map((p) => p.name), ['href', 'nodeIds', 'format']);
      expect(tool.params.map((p) => p.required), [true, true, false]);
    });

    test('figma_download_image_as_file requires href, nodeId, format', () {
      final tool = toolNamed('figma_download_image_as_file');
      expect(
        tool.params.map((p) => p.name),
        ['href', 'nodeId', 'format'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('figma_get_svg_content requires href and nodeId', () {
      final tool = toolNamed('figma_get_svg_content');
      expect(tool.params.map((p) => p.name), ['href', 'nodeId']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('figma_get_node_details and figma_get_text_content take nodeIds',
        () {
      for (final name in ['figma_get_node_details', 'figma_get_text_content']) {
        final tool = toolNamed(name);
        expect(tool.params.map((p) => p.name), ['href', 'nodeIds']);
        expect(tool.params.every((p) => p.required), isTrue);
      }
    });

    test('figma_get_layers_batch requires href and nodeIds', () {
      final tool = toolNamed('figma_get_layers_batch');
      expect(tool.params.map((p) => p.name), ['href', 'nodeIds']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('figma_list_team_projects takes teamIdOrUrl', () {
      final tool = toolNamed('figma_list_team_projects');
      expect(tool.params.map((p) => p.name), ['teamIdOrUrl']);
    });

    test('figma_list_project_files takes projectIdOrUrl', () {
      final tool = toolNamed('figma_list_project_files');
      expect(tool.params.map((p) => p.name), ['projectIdOrUrl']);
    });

    test('figma_get_screen_source takes url', () {
      final tool = toolNamed('figma_get_screen_source');
      expect(tool.params.map((p) => p.name), ['url']);
    });
  });
}

/// [FigmaToolExecutor.execute] routes original tool names to client calls.
void executorRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute', () {
    setUp(() => f = _executorFixture());

    test('routes figma_test to testConnection', () async {
      await f.executor.execute('figma_test', {});
      expect(f.spy.calls, ['testConnection']);
    });

    test('routes figma_get_file with key', () async {
      await f.executor.execute('figma_get_file', {'key': 'aBc123'});
      expect(f.spy.calls, ['getFile:aBc123']);
    });

    test('routes figma_get_file_nodes with key, node_ids', () async {
      await f.executor.execute('figma_get_file_nodes', {
        'key': 'aBc123',
        'node_ids': '1:2,3:4',
      });
      expect(f.spy.calls, ['getFileNodes:aBc123:1:2,3:4']);
    });

    test('routes figma_get_image with key, node_id', () async {
      await f.executor.execute('figma_get_image', {
        'key': 'aBc123',
        'node_id': '1:2',
      });
      expect(f.spy.calls, ['getImage:aBc123:1:2']);
    });
  });
}

/// Java-catalog executor routing: each new name reaches its client method.
void javaCatalogRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (Java catalog)', () {
    setUp(() => f = _executorFixture());

    test('routes figma_me to meJson', () async {
      await f.executor.execute('figma_me', {});
      expect(f.spy.calls, ['meJson']);
    });

    test('routes figma_get_screen_source with url', () async {
      await f.executor.execute('figma_get_screen_source', {
        'url': 'https://www.figma.com/file/k/F?node-id=1-2',
      });
      expect(f.spy.calls, ['getImageOfSource:https://www.figma.com/file/k/F?node-id=1-2']);
    });

    test('routes figma_get_file_structure with href', () async {
      await f.executor.execute('figma_get_file_structure', {'href': 'h'});
      expect(f.spy.calls, ['getFileStructure:h']);
    });

    test('routes figma_get_icons with href', () async {
      await f.executor.execute('figma_get_icons', {'href': 'h'});
      expect(f.spy.calls, ['getIcons:h']);
    });

    test('routes figma_get_image_fills with href', () async {
      await f.executor.execute('figma_get_image_fills', {'href': 'h'});
      expect(f.spy.calls, ['getImageFills:h']);
    });

    test('routes figma_render_nodes with href, nodeIds, format', () async {
      await f.executor.execute('figma_render_nodes', {
        'href': 'h',
        'nodeIds': '1:2',
        'format': 'svg',
      });
      expect(f.spy.calls, ['renderNodes:h:1:2:svg']);
    });

    test('routes figma_get_node_details with href, nodeIds', () async {
      await f.executor.execute('figma_get_node_details', {
        'href': 'h',
        'nodeIds': '1:2',
      });
      expect(f.spy.calls, ['getNodeDetails:h:1:2']);
    });

    test('routes figma_get_text_content with href, nodeIds', () async {
      await f.executor.execute('figma_get_text_content', {
        'href': 'h',
        'nodeIds': '1:2',
      });
      expect(f.spy.calls, ['getTextContent:h:1:2']);
    });

    test('routes figma_get_styles with href', () async {
      await f.executor.execute('figma_get_styles', {'href': 'h'});
      expect(f.spy.calls, ['getDesignStyles:h']);
    });

    test('routes figma_get_layers with href', () async {
      await f.executor.execute('figma_get_layers', {'href': 'h'});
      expect(f.spy.calls, ['getLayers:h']);
    });

    test('routes figma_get_layers_batch with href, nodeIds', () async {
      await f.executor.execute('figma_get_layers_batch', {
        'href': 'h',
        'nodeIds': '1:2,3:4',
      });
      expect(f.spy.calls, ['getLayersBatch:h:1:2,3:4']);
    });

    test('routes figma_get_node_children with href', () async {
      await f.executor.execute('figma_get_node_children', {'href': 'h'});
      expect(f.spy.calls, ['getNodeChildren:h']);
    });

    test('routes figma_list_team_projects with teamIdOrUrl', () async {
      await f.executor.execute('figma_list_team_projects', {
        'teamIdOrUrl': '42',
      });
      expect(f.spy.calls, ['listTeamProjects:42']);
    });

    test('routes figma_list_project_files with projectIdOrUrl', () async {
      await f.executor.execute('figma_list_project_files', {
        'projectIdOrUrl': '7',
      });
      expect(f.spy.calls, ['listProjectFiles:7']);
    });

    test('routes figma_get_file_comments with href', () async {
      await f.executor.execute('figma_get_file_comments', {'href': 'h'});
      expect(f.spy.calls, ['getFileComments:h']);
    });

    test('routes figma_download_node_image with defaults', () async {
      await f.executor.execute('figma_download_node_image', {
        'href': 'h',
        'nodeId': '1:2',
      });
      expect(f.spy.calls, ['downloadNodeImage:h:1:2:null:null']);
    });

    test('routes figma_download_image_of_file with href', () async {
      await f.executor.execute('figma_download_image_of_file', {'href': 'h'});
      expect(f.spy.calls, ['convertUrlToFile:h']);
    });

    test('routes figma_download_image_as_file with href, nodeId, format',
        () async {
      await f.executor.execute('figma_download_image_as_file', {
        'href': 'h',
        'nodeId': '1:2',
        'format': 'svg',
      });
      expect(f.spy.calls, ['downloadIconFile:h:1:2:svg']);
    });

    test('routes figma_get_svg_content with href, nodeId', () async {
      await f.executor.execute('figma_get_svg_content', {
        'href': 'h',
        'nodeId': '1:2',
      });
      expect(f.spy.calls, ['getSvgContent:h:1:2']);
    });
  });
}

/// OAuth tool executor behavior: config validation and result envelopes.
void oauthExecutorTests() {
  group('FigmaToolExecutor OAuth tools', () {
    test('get_auth_url reports a missing client id', () async {
      final f = _executorFixture();
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {}),
      ) as Map<String, dynamic>;
      expect(result['error'], 'FIGMA_CLIENT_ID is not configured');
    });

    test('get_auth_url reports a missing client secret', () async {
      PropertyReader.setOverrides({'FIGMA_CLIENT_ID': 'cid'});
      final f = _executorFixture();
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {}),
      ) as Map<String, dynamic>;
      expect(result['error'], 'FIGMA_CLIENT_SECRET is not configured');
    });

    test('get_auth_url reports a missing redirect URI', () async {
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
      });
      final f = _executorFixture();
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {}),
      ) as Map<String, dynamic>;
      expect(
        result['error'],
        'redirectUri is required (or set FIGMA_REDIRECT_URI in dmtools.env)',
      );
    });

    test('get_auth_url builds the authorization URL from config', () async {
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://localhost:8080/callback',
      });
      final f = _executorFixture();
      final result = jsonDecode(
        await f.executor.execute('figma_oauth2_get_auth_url', {
          'state': 'xyz',
        }),
      ) as Map<String, dynamic>;
      expect(
        result['authorization_url'],
        'https://www.figma.com/oauth?client_id=cid'
        '&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback'
        '&scope=file_content%3Aread+file_metadata%3Aread'
        '&state=xyz&response_type=code',
      );
      expect(result['state'], 'xyz');
      expect(result['instructions'], isNotNull);
    });

    test('exchange_code reports incomplete config', () async {
      final f = _executorFixture();
      final result = jsonDecode(
        await f.executor
            .execute('figma_oauth2_exchange_code', {'code': 'c'}),
      ) as Map<String, dynamic>;
      expect(
        result['error'],
        'FIGMA_CLIENT_ID and FIGMA_CLIENT_SECRET must be configured',
      );
    });

    test('exchange_code returns tokens and instructions', () async {
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://cb/',
      });
      final spy = _SpyFigmaClient(mockFigmaHttp(_spyRouter).http);
      final executor = FigmaToolExecutor(
        spy,
        PropertyReader(),
        _FakeExchange(),
      );
      final result = jsonDecode(
        await executor.execute('figma_oauth2_exchange_code', {'code': 'c'}),
      ) as Map<String, dynamic>;
      expect(result['access_token'], 'at');
      expect(result['refresh_token'], 'rt');
      expect(result['expires_in'], 3600);
      expect(
        result['instructions'],
        contains('FIGMA_OAUTH_REFRESH_TOKEN=rt'),
      );
    });

    test('exchange_code wraps failures in the Java error text', () async {
      PropertyReader.setOverrides({
        'FIGMA_CLIENT_ID': 'cid',
        'FIGMA_CLIENT_SECRET': 'cs',
        'FIGMA_REDIRECT_URI': 'http://cb/',
      });
      final spy = _SpyFigmaClient(mockFigmaHttp(_spyRouter).http);
      final executor = FigmaToolExecutor(
        spy,
        PropertyReader(),
        _FakeExchange(fail: true),
      );
      final result = jsonDecode(
        await executor.execute('figma_oauth2_exchange_code', {'code': 'c'}),
      ) as Map<String, dynamic>;
      expect(result['error'], startsWith('Token exchange failed:'));
    });
  });
}

/// A canned [FigmaOAuth2Exchange].
class _FakeExchange extends FigmaOAuth2Exchange {
  _FakeExchange({this.fail = false});

  final bool fail;

  @override
  Future<FigmaTokenResponse> exchangeCode({
    required String code,
    required String redirectUri,
    required String clientId,
    required String clientSecret,
  }) async {
    if (fail) {
      throw StateError('Figma OAuth2 token request failed [400]: bad');
    }
    return (accessToken: 'at', refreshToken: 'rt', expiresIn: 3600);
  }
}

/// [FigmaToolExecutor.execute] routes the comment, component, and
/// image-export tools.
void commentComponentStyleExportRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (comments, components, export)', () {
    setUp(() => f = _executorFixture());

    test('routes figma_get_comments with key', () async {
      await f.executor.execute('figma_get_comments', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComments:aBc123']);
    });

    test('routes figma_post_comment with key, message', () async {
      await f.executor.execute('figma_post_comment', {
        'key': 'aBc123',
        'message': 'Nice work!',
      });
      expect(f.spy.calls, ['postComment:aBc123:Nice work!']);
    });

    test('routes figma_get_components with key', () async {
      await f.executor.execute('figma_get_components', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComponents:aBc123']);
    });

    test('routes figma_get_component_sets with key', () async {
      await f.executor.execute('figma_get_component_sets', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComponentSets:aBc123']);
    });

    test('routes figma_export_image with key, format, scale', () async {
      await f.executor.execute('figma_export_image', {
        'key': 'aBc123',
        'format': 'svg',
        'scale': 2,
      });
      expect(f.spy.calls, ['exportImage:aBc123:svg:2.0']);
    });

    test('routes figma_export_image without optional params', () async {
      await f.executor.execute('figma_export_image', {'key': 'aBc123'});
      expect(f.spy.calls, ['exportImage:aBc123:null:null']);
    });
  });
}

/// [FigmaToolExecutor.execute] routes the component-library and
/// variable-collection tools.
void libraryVariableRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (libraries and variables)', () {
    setUp(() => f = _executorFixture());

    test('routes figma_get_file_components as alias to getComponents',
        () async {
      await f.executor.execute('figma_get_file_components', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComponents:aBc123']);
    });

    test('routes figma_get_variable_collections with key', () async {
      await f.executor.execute(
        'figma_get_variable_collections',
        {'key': 'aBc123'},
      );
      expect(f.spy.calls, ['getVariableCollections:aBc123']);
    });

    test('routes figma_get_library_components with library_key', () async {
      await f.executor.execute(
        'figma_get_library_components',
        {'library_key': 'lib1'},
      );
      expect(f.spy.calls, ['getLibraryComponents:lib1']);
    });
  });
}

/// [FigmaToolExecutor.execute] routes the node and style lookup tools.
void nodeStyleRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (node and style lookups)', () {
    setUp(() => f = _executorFixture());

    test('routes figma_get_style with key', () async {
      await f.executor.execute('figma_get_style', {'key': 'aBc123'});
      expect(f.spy.calls, ['getStyle:aBc123']);
    });

    test('routes figma_get_node with key, node_id', () async {
      await f.executor.execute('figma_get_node', {
        'key': 'aBc123',
        'node_id': '1:2',
      });
      expect(f.spy.calls, ['getNode:aBc123:1:2']);
    });
  });
}

/// [FigmaToolExecutor.execute] error cases.
void executorEdgeCaseTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (edge cases)', () {
    setUp(() => f = _executorFixture());

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => f.executor.execute('figma_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _ExecutorFixture = ({FigmaToolExecutor executor, _SpyFigmaClient spy});

/// Builds a [_SpyFigmaClient] over the mocked transport and wraps it.
_ExecutorFixture _executorFixture() {
  final spy = _SpyFigmaClient(mockFigmaHttp(_spyRouter).http);
  return (executor: FigmaToolExecutor(spy), spy: spy);
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyFigmaClient extends FigmaClient {
  _SpyFigmaClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<String> meJson() {
    calls.add('meJson');
    return super.meJson();
  }

  @override
  Future<String?> getImageOfSource(String url) {
    calls.add('getImageOfSource:$url');
    return super.getImageOfSource(url);
  }

  @override
  Future<String?> downloadNodeImage(
    String href,
    String nodeId, {
    String? format,
    int? scale,
  }) {
    calls.add('downloadNodeImage:$href:$nodeId:$format:$scale');
    return super.downloadNodeImage(href, nodeId, format: format, scale: scale);
  }

  @override
  Future<String?> convertUrlToFile(String href) {
    calls.add('convertUrlToFile:$href');
    return super.convertUrlToFile(href);
  }

  @override
  Future<Map<String, dynamic>?> getFileStructure(String href) {
    calls.add('getFileStructure:$href');
    return super.getFileStructure(href);
  }

  @override
  Future<Map<String, dynamic>?> getIcons(String href) {
    calls.add('getIcons:$href');
    return super.getIcons(href);
  }

  @override
  Future<String> getImageFills(String href) {
    calls.add('getImageFills:$href');
    return super.getImageFills(href);
  }

  @override
  Future<String> renderNodes(
    String href,
    String nodeIds, {
    String? format,
  }) {
    calls.add('renderNodes:$href:$nodeIds:$format');
    return super.renderNodes(href, nodeIds, format: format);
  }

  @override
  Future<String?> downloadIconFile(
    String href,
    String nodeId,
    String format,
  ) {
    calls.add('downloadIconFile:$href:$nodeId:$format');
    return super.downloadIconFile(href, nodeId, format);
  }

  @override
  Future<String?> getSvgContent(String href, String nodeId) {
    calls.add('getSvgContent:$href:$nodeId');
    return super.getSvgContent(href, nodeId);
  }

  @override
  Future<Map<String, dynamic>?> getNodeDetails(String href, String nodeIds) {
    calls.add('getNodeDetails:$href:$nodeIds');
    return super.getNodeDetails(href, nodeIds);
  }

  @override
  Future<Map<String, dynamic>?> getTextContent(String href, String nodeIds) {
    calls.add('getTextContent:$href:$nodeIds');
    return super.getTextContent(href, nodeIds);
  }

  @override
  Future<Map<String, dynamic>?> getDesignStyles(String href) {
    calls.add('getDesignStyles:$href');
    return super.getDesignStyles(href);
  }

  @override
  Future<Map<String, dynamic>?> getLayers(String href) {
    calls.add('getLayers:$href');
    return super.getLayers(href);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getLayersBatch(
    String href,
    String nodeIds,
  ) {
    calls.add('getLayersBatch:$href:$nodeIds');
    return super.getLayersBatch(href, nodeIds);
  }

  @override
  Future<Map<String, dynamic>?> getNodeChildren(String href) {
    calls.add('getNodeChildren:$href');
    return super.getNodeChildren(href);
  }

  @override
  Future<List<dynamic>> listTeamProjects(String teamIdOrUrl) {
    calls.add('listTeamProjects:$teamIdOrUrl');
    return super.listTeamProjects(teamIdOrUrl);
  }

  @override
  Future<List<dynamic>> listProjectFiles(String projectIdOrUrl) {
    calls.add('listProjectFiles:$projectIdOrUrl');
    return super.listProjectFiles(projectIdOrUrl);
  }

  @override
  Future<List<dynamic>> getFileComments(String href) {
    calls.add('getFileComments:$href');
    return super.getFileComments(href);
  }

  @override
  Future<Map<String, dynamic>> getFile(String key) {
    calls.add('getFile:$key');
    return super.getFile(key);
  }

  @override
  Future<Map<String, dynamic>> getFileNodes(String key, String nodeIds) {
    calls.add('getFileNodes:$key:$nodeIds');
    return super.getFileNodes(key, nodeIds);
  }

  @override
  Future<Map<String, dynamic>> getImage(String key, String nodeId) {
    calls.add('getImage:$key:$nodeId');
    return super.getImage(key, nodeId);
  }

  @override
  Future<Map<String, dynamic>> getComments(String key) {
    calls.add('getComments:$key');
    return super.getComments(key);
  }

  @override
  Future<Map<String, dynamic>> postComment(String key, String message) {
    calls.add('postComment:$key:$message');
    return super.postComment(key, message);
  }

  @override
  Future<Map<String, dynamic>> getComponents(String key) {
    calls.add('getComponents:$key');
    return super.getComponents(key);
  }

  @override
  Future<Map<String, dynamic>> getComponentSets(String key) {
    calls.add('getComponentSets:$key');
    return super.getComponentSets(key);
  }

  @override
  Future<Map<String, dynamic>> exportImage(
    String key, {
    String? format,
    double? scale,
  }) {
    calls.add('exportImage:$key:$format:$scale');
    return super.exportImage(key, format: format, scale: scale);
  }

  @override
  Future<Map<String, dynamic>> getVariableCollections(String key) {
    calls.add('getVariableCollections:$key');
    return super.getVariableCollections(key);
  }

  @override
  Future<Map<String, dynamic>> getLibraryComponents(String libraryKey) {
    calls.add('getLibraryComponents:$libraryKey');
    return super.getLibraryComponents(libraryKey);
  }

  @override
  Future<Map<String, dynamic>> getStyle(String key) {
    calls.add('getStyle:$key');
    return super.getStyle(key);
  }

  @override
  Future<Map<String, dynamic>> getNode(String key, String nodeId) {
    calls.add('getNode:$key:$nodeId');
    return super.getNode(key, nodeId);
  }
}
