import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Page-management coverage: get by id, delete, children, move, history,
/// archive, and restore — plus the matching tool definitions and executor
/// dispatch.
///
/// Note: `getContentVersions` is intentionally not added — the existing
/// [ConfluenceClient.getPageHistory] (GET `content/{id}/version`) already
/// covers it. Archive and restore share the `_statusPayload` builder in the
/// client, differing only in the target status.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPageByIdTests();
  deletePageTests();
  getContentChildrenTests();
  movePageTests();
  getPageHistoryTests();
  archivePageTests();
  restorePageTests();
  pageToolDefinitionTests();
  pageExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_page_by_id` — GET `content/{id}?expand=body.storage,version`.
void getPageByIdTests() {
  group('ConfluenceClient.getPageById', () {
    test('returns the page with body and version expanded', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content/42': _pageByIdBody}, o));
      final page = await f.client.getPageById('42');
      expect(page['id'], '42');
      expect(f.adapter.calls.single.queryParameters['expand'],
          'body.storage,version');
    });
  });
}

/// `confluence_delete_page` — DELETE `content/{id}`.
void deletePageTests() {
  group('ConfluenceClient.deletePage', () {
    test('DELETEs the page', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content/42': _deletedBody}, o));
      final result = await f.client.deletePage('42');
      expect(result, {'removed': true});
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/content/42'));
    });

    test('returns empty map on an empty response body', () async {
      final f = mockConfluence((o) => routeByPath({'/content/42': ''}, o));
      expect(await f.client.deletePage('42'), isEmpty);
    });
  });
}

/// `confluence_get_content_children` — GET `content/{id}/child/page`.
void getContentChildrenTests() {
  group('ConfluenceClient.getContentChildren', () {
    test('returns the child page results', () async {
      final f =
          mockConfluence((o) => routeByPath({'/child/page': _childrenBody}, o));
      final children = await f.client.getContentChildren('42');
      expect(children, hasLength(2));
      expect(children[0]['title'], 'Child A');
      expect(children[1]['title'], 'Child B');
      expect(f.adapter.calls.single.path, endsWith('/content/42/child/page'));
    });
  });
}

/// `confluence_move_page` — PUT `content/{pageId}/move`.
void movePageTests() {
  group('ConfluenceClient.movePage', () {
    test('PUTs the target id and returns the response', () async {
      final f = mockConfluence((o) => routeByPath({'/move': _movedBody}, o));
      final result = await f.client.movePage('42', '99');
      expect(result['moved'], true);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/content/42/move'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['target']['id'], '99');
    });

    test('returns empty map on an empty response body', () async {
      final f = mockConfluence((o) => routeByPath({'/move': ''}, o));
      expect(await f.client.movePage('42', '99'), isEmpty);
    });
  });
}

/// `confluence_get_page_history` — GET `content/{pageId}/version`.
void getPageHistoryTests() {
  group('ConfluenceClient.getPageHistory', () {
    test('returns the version results', () async {
      final f =
          mockConfluence((o) => routeByPath({'/version': _historyBody}, o));
      final history = await f.client.getPageHistory('42');
      expect(history, hasLength(2));
      expect(history[0]['number'], 1);
      expect(history[1]['number'], 2);
      expect(f.adapter.calls.single.path, endsWith('/content/42/version'));
    });
  });
}

/// `confluence_archive_page` — PUT `content/{id}` with status `archived`.
void archivePageTests() {
  group('ConfluenceClient.archivePage', () {
    test('PUTs the archived status and returns the response', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/42': _archivedBody}, o),
      );
      final result = await f.client.archivePage('42');
      expect(result['status'], 'archived');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/content/42'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['status'], 'archived');
      expect(sent['id'], '42');
    });

    test('returns empty map on an empty response body', () async {
      final f = mockConfluence((o) => routeByPath({'/content/42': ''}, o));
      expect(await f.client.archivePage('42'), isEmpty);
    });
  });
}

/// `confluence_restore_page` — PUT `content/{id}` with status `current`.
void restorePageTests() {
  group('ConfluenceClient.restorePage', () {
    test('PUTs the current status and returns the response', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/42': _restoredBody}, o),
      );
      final result = await f.client.restorePage('42');
      expect(result['status'], 'current');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/content/42'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['type'], 'page');
      expect(sent['status'], 'current');
      expect(sent['id'], '42');
    });

    test('returns empty map on an empty response body', () async {
      final f = mockConfluence((o) => routeByPath({'/content/42': ''}, o));
      expect(await f.client.restorePage('42'), isEmpty);
    });
  });
}

/// Tool-definition shape for the page tools.
void pageToolDefinitionTests() {
  group('confluence tool definitions (pages)', () {
    test('confluence_get_page_by_id requires id', () {
      final tool = toolNamed('confluence_get_page_by_id');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_delete_page requires id', () {
      final tool = toolNamed('confluence_delete_page');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_get_content_children requires id', () {
      final tool = toolNamed('confluence_get_content_children');
      expect(tool.category, 'content_hierarchy');
      expect(tool.params.single.name, 'id');
    });

    test('confluence_move_page requires pageId and targetId', () {
      final tool = toolNamed('confluence_move_page');
      expect(tool.category, 'page_management');
      expect(tool.params.map((p) => p.name), ['pageId', 'targetId']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('confluence_get_page_history requires pageId', () {
      final tool = toolNamed('confluence_get_page_history');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'pageId');
    });

    test('confluence_archive_page requires id', () {
      final tool = toolNamed('confluence_archive_page');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_restore_page requires id', () {
      final tool = toolNamed('confluence_restore_page');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each page tool name.
void pageExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (pages)', () {
    test('routes confluence_get_page_by_id', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_get_page_by_id', {'id': '42'});
      expect(f.client.calls, ['getPageById:42']);
    });

    test('routes confluence_delete_page', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_delete_page', {'id': '42'});
      expect(f.client.calls, ['deletePage:42']);
    });

    test('routes confluence_get_content_children', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_content_children',
        {'id': '42'},
      );
      expect(f.client.calls, ['getContentChildren:42']);
    });

    test('routes confluence_move_page', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_move_page',
        {'pageId': '42', 'targetId': '99'},
      );
      expect(f.client.calls, ['movePage:42:99']);
    });

    test('routes confluence_get_page_history', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_page_history',
        {'pageId': '42'},
      );
      expect(f.client.calls, ['getPageHistory:42']);
    });

    test('routes confluence_archive_page', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_archive_page',
        {'id': '42'},
      );
      expect(f.client.calls, ['archivePage:42']);
    });

    test('routes confluence_restore_page', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_restore_page', {'id': '42'});
      expect(f.client.calls, ['restorePage:42']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _PagesSpy client}) _makeExecutor() {
  final client = _PagesSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned page-by-id response body.
final _pageByIdBody = jsonEncode({
  'id': '42',
  'title': 'Design Doc',
  'body': {
    'storage': {'value': '<p>x</p>'}
  },
  'version': {'number': 3},
});

/// Canned delete response body.
const _deletedBody = '{"removed":true}';

/// Canned child-pages response body.
final _childrenBody = jsonEncode({
  'results': [
    {'title': 'Child A', 'id': 'c1'},
    {'title': 'Child B', 'id': 'c2'},
  ],
});

/// Canned move response body.
const _movedBody = '{"moved":true}';

/// Canned version-history response body.
final _historyBody = jsonEncode({
  'results': [
    {'number': 1, 'when': '2024-01-01'},
    {'number': 2, 'when': '2024-01-02'},
  ],
});

/// Canned archive response body.
const _archivedBody = '{"id":"42","status":"archived"}';

/// Canned restore response body.
const _restoredBody = '{"id":"42","type":"page","status":"current"}';

/// Spy that records every page call then delegates to the real client.
class _PagesSpy extends ConfluenceClient {
  _PagesSpy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> getPageById(String id) {
    calls.add('getPageById:$id');
    return super.getPageById(id);
  }

  @override
  Future<Map<String, dynamic>> deletePage(String id) {
    calls.add('deletePage:$id');
    return super.deletePage(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getContentChildren(String id) {
    calls.add('getContentChildren:$id');
    return super.getContentChildren(id);
  }

  @override
  Future<Map<String, dynamic>> movePage(String pageId, String targetId) {
    calls.add('movePage:$pageId:$targetId');
    return super.movePage(pageId, targetId);
  }

  @override
  Future<List<Map<String, dynamic>>> getPageHistory(String pageId) {
    calls.add('getPageHistory:$pageId');
    return super.getPageHistory(pageId);
  }

  @override
  Future<Map<String, dynamic>> archivePage(String id) {
    calls.add('archivePage:$id');
    return super.archivePage(id);
  }

  @override
  Future<Map<String, dynamic>> restorePage(String id) {
    calls.add('restorePage:$id');
    return super.restorePage(id);
  }
}
