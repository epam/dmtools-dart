import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Batch-3 coverage: getSpaceByKey, updateSpace, movePage, getPageHistory,
/// getPermissions, addPermission — plus the matching tool definitions and
/// executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getSpaceByKeyTests();
  updateSpaceTests();
  movePageTests();
  getPageHistoryTests();
  getPermissionsTests();
  addPermissionTests();
  batch3ToolDefinitionTests();
  batch3ExecutorTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_space_by_key` — GET `space/{spaceKey}`.
void getSpaceByKeyTests() {
  group('ConfluenceClient.getSpaceByKey', () {
    test('returns the space for the given key', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/space/ENG': _spaceByKeyBody}, o),
      );
      final space = await f.client.getSpaceByKey('ENG');
      expect(space['key'], 'ENG');
      expect(f.adapter.calls.single.path, endsWith('/space/ENG'));
    });
  });
}

/// `confluence_update_space` — PUT `space/{spaceKey}`.
void updateSpaceTests() {
  group('ConfluenceClient.updateSpace', () {
    test('PUTs name and description and returns the updated space', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/space/ENG': _spaceUpdatedBody}, o),
      );
      final result = await f.client.updateSpace('ENG', 'New Name', 'New desc');
      expect(result['name'], 'New Name');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/space/ENG'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['name'], 'New Name');
      final desc = sent['description']['plain'] as Map<String, dynamic>;
      expect(desc['value'], 'New desc');
      expect(desc['representation'], 'plain');
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

/// `confluence_get_permissions` — GET `space/{spaceKey}/content/permission`.
void getPermissionsTests() {
  group('ConfluenceClient.getPermissions', () {
    test('returns the permission results', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/permission': _permissionsBody}, o),
      );
      final perms = await f.client.getPermissions('ENG');
      expect(perms, hasLength(1));
      expect(perms[0]['operation']['key'], 'read');
      expect(
        f.adapter.calls.single.path,
        endsWith('/space/ENG/content/permission'),
      );
    });
  });
}

/// `confluence_add_permission` — POST `space/{spaceKey}/permission`.
void addPermissionTests() {
  group('ConfluenceClient.addPermission', () {
    test('POSTs the permission object and returns the response', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/permission': _permissionAddedBody}, o),
      );
      final Map<String, dynamic> perm = {
        'subject': {'type': 'user', 'identifier': 'alice'},
        'operation': {'key': 'read', 'target': 'page'},
      };
      final result = await f.client.addPermission('ENG', perm);
      expect(result['results'], hasLength(1));
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/space/ENG/permission'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['operation']['key'], 'read');
    });
  });
}

/// Tool-definition shape for the batch-3 tools.
void batch3ToolDefinitionTests() {
  group('batch3 tool definitions', () {
    test('confluence_get_space_by_key requires spaceKey', () {
      final tool = toolNamed('confluence_get_space_by_key');
      expect(tool.category, 'space');
      expect(tool.params.single.name, 'spaceKey');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_update_space requires spaceKey, name, description', () {
      final tool = toolNamed('confluence_update_space');
      expect(tool.category, 'space');
      expect(
          tool.params.map((p) => p.name), ['spaceKey', 'name', 'description']);
      expect(tool.params.every((p) => p.required), isTrue);
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

    test('confluence_get_permissions requires spaceKey', () {
      final tool = toolNamed('confluence_get_permissions');
      expect(tool.category, 'permissions');
      expect(tool.params.single.name, 'spaceKey');
    });

    test('confluence_add_permission requires spaceKey and permission', () {
      final tool = toolNamed('confluence_add_permission');
      expect(tool.category, 'permissions');
      expect(tool.params.map((p) => p.name), ['spaceKey', 'permission']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each batch-3 tool name.
void batch3ExecutorTests() {
  group('ConfluenceToolExecutor batch3 dispatch', () {
    test('routes confluence_get_space_by_key', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_space_by_key',
        {'spaceKey': 'ENG'},
      );
      expect(f.client.calls, ['getSpaceByKey:ENG']);
    });

    test('routes confluence_update_space', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_update_space', {
        'spaceKey': 'ENG',
        'name': 'New',
        'description': 'Desc',
      });
      expect(f.client.calls, ['updateSpace:ENG:New:Desc']);
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

    test('routes confluence_get_permissions', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_permissions',
        {'spaceKey': 'ENG'},
      );
      expect(f.client.calls, ['getPermissions:ENG']);
    });

    test('routes confluence_add_permission', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_add_permission', {
        'spaceKey': 'ENG',
        'permission': {
          'operation': {'key': 'read'}
        },
      });
      expect(f.client.calls, ['addPermission:ENG']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _Batch3Spy client}) _makeExecutor() {
  final client = _Batch3Spy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned single-space response body.
final _spaceByKeyBody = jsonEncode({
  'key': 'ENG',
  'name': 'Engineering',
});

/// Canned updated-space response body.
final _spaceUpdatedBody = jsonEncode({
  'key': 'ENG',
  'name': 'New Name',
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

/// Canned permissions response body.
final _permissionsBody = jsonEncode({
  'results': [
    {
      'operation': {'key': 'read', 'target': 'page'},
    },
  ],
});

/// Canned add-permission response body.
final _permissionAddedBody = jsonEncode({
  'results': [
    {
      'operation': {'key': 'read', 'target': 'page'},
    },
  ],
});

/// Spy that records every batch-3 call then delegates to the real client.
class _Batch3Spy extends ConfluenceClient {
  _Batch3Spy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> getSpaceByKey(String spaceKey) {
    calls.add('getSpaceByKey:$spaceKey');
    return super.getSpaceByKey(spaceKey);
  }

  @override
  Future<Map<String, dynamic>> updateSpace(
    String spaceKey,
    String name,
    String description,
  ) {
    calls.add('updateSpace:$spaceKey:$name:$description');
    return super.updateSpace(spaceKey, name, description);
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
  Future<List<Map<String, dynamic>>> getPermissions(String spaceKey) {
    calls.add('getPermissions:$spaceKey');
    return super.getPermissions(spaceKey);
  }

  @override
  Future<Map<String, dynamic>> addPermission(
    String spaceKey,
    Map<String, dynamic> permission,
  ) {
    calls.add('addPermission:$spaceKey');
    return super.addPermission(spaceKey, permission);
  }
}
