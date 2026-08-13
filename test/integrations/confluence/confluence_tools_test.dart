import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Tests for the [confluenceTools] catalog and [ConfluenceToolExecutor]
/// dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('confluenceTools catalog', () {
    final tools = confluenceTools();

    test('registers all tools in declaration order', () {
      expect(tools.map((t) => t.name), _expectedToolOrder);
    });

    test('every tool belongs to the confluence integration', () {
      expect(tools.every((t) => t.integration == 'confluence'), isTrue);
    });
  });

  test('confluence_get_page requires spaceKey and title', () {
    final tool = toolNamed('confluence_get_page');
    expect(tool.params.map((p) => p.name), ['spaceKey', 'title']);
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('confluence_create_page requires spaceKey, title, body', () {
    final tool = toolNamed('confluence_create_page');
    expect(tool.params.map((p) => p.name), ['spaceKey', 'title', 'body']);
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('confluence_update_page requires id, title, body, version(number)', () {
    final tool = toolNamed('confluence_update_page');
    expect(tool.params.map((p) => p.name), ['id', 'title', 'body', 'version']);
    expect(tool.params.every((p) => p.required), isTrue);
    expect(tool.params.last.type, 'number');
  });

  test('confluence_search requires cql', () {
    final tool = toolNamed('confluence_search');
    expect(tool.category, 'search');
    expect(tool.params.single.name, 'cql');
    expect(tool.params.single.required, isTrue);
  });
}

/// [ConfluenceToolExecutor.execute] routes each tool name to the right client
/// call.
void executorDispatchTests() {
  group('ConfluenceToolExecutor.execute', () {
    late _SpyConfluenceClient spy;
    late ConfluenceToolExecutor executor;

    setUp(() {
      spy = _SpyConfluenceClient(mockHttp((o) => '{}').http);
      executor = ConfluenceToolExecutor(spy);
    });

    test('routes confluence_test to testConnection', () async {
      await executor.execute('confluence_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes confluence_get_page with spaceKey and title', () async {
      await executor.execute('confluence_get_page', {
        'spaceKey': 'ENG',
        'title': 'Doc',
      });
      expect(spy.calls, ['getPage:ENG:Doc']);
    });

    test('routes confluence_create_page with spaceKey, title, body', () async {
      await executor.execute('confluence_create_page', {
        'spaceKey': 'ENG',
        'title': 'New',
        'body': '<p>hi</p>',
      });
      expect(spy.calls, ['createPage:ENG:New:<p>hi</p>']);
    });

    test('routes confluence_update_page with id, title, body, version',
        () async {
      await executor.execute('confluence_update_page', {
        'id': '42',
        'title': 'Up',
        'body': '<p>up</p>',
        'version': 3,
      });
      expect(spy.calls, ['updatePage:42:Up:<p>up</p>:3']);
    });

    test('routes confluence_search with cql', () async {
      await executor.execute('confluence_search', {'cql': 'type = page'});
      expect(spy.calls, ['search:type = page']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(() => executor.execute('confluence_no_such', {}),
          throwsArgumentError);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyConfluenceClient extends ConfluenceClient {
  _SpyConfluenceClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>?> getPage(String spaceKey, String title) {
    calls.add('getPage:$spaceKey:$title');
    return super.getPage(spaceKey, title);
  }

  @override
  Future<Map<String, dynamic>> createPage(
    String spaceKey,
    String title,
    String body,
  ) {
    calls.add('createPage:$spaceKey:$title:$body');
    return super.createPage(spaceKey, title, body);
  }

  @override
  Future<Map<String, dynamic>> updatePage(
    String id,
    String title,
    String body,
    int version,
  ) {
    calls.add('updatePage:$id:$title:$body:$version');
    return super.updatePage(id, title, body, version);
  }

  @override
  Future<List<Map<String, dynamic>>> search(String query) {
    calls.add('search:$query');
    return super.search(query);
  }
}

/// The full tool catalog in declaration order.
const _expectedToolOrder = [
  'confluence_test',
  'confluence_get_page',
  'confluence_get_page_by_id',
  'confluence_create_page',
  'confluence_update_page',
  'confluence_delete_page',
  'confluence_search',
  'confluence_get_spaces',
  'confluence_get_space_by_key',
  'confluence_update_space',
  'confluence_get_space_content',
  'confluence_create_space',
  'confluence_add_label',
  'confluence_get_labels',
  'confluence_get_page_attachments',
  'confluence_get_blog_posts',
  'confluence_get_content_children',
  'confluence_move_page',
  'confluence_get_page_history',
  'confluence_archive_page',
  'confluence_get_permissions',
  'confluence_add_permission',
  'confluence_get_page_properties',
  'confluence_set_page_property',
];
