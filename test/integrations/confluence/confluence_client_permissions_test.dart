import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Space-permission coverage: list and add space permissions — plus the
/// matching tool definitions and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPermissionsTests();
  addPermissionTests();
  permissionToolDefinitionTests();
  permissionExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

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

/// Tool-definition shape for the permission tools.
void permissionToolDefinitionTests() {
  group('confluence tool definitions (permissions)', () {
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

/// [ConfluenceToolExecutor.execute] routes each permission tool name.
void permissionExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (permissions)', () {
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
({ConfluenceToolExecutor executor, _PermissionsSpy client}) _makeExecutor() {
  final client = _PermissionsSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

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

/// Spy that records every permission call then delegates to the real client.
class _PermissionsSpy extends ConfluenceClient {
  _PermissionsSpy(super.http);

  final List<String> calls = [];

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
