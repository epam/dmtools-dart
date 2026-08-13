import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Batch-5 coverage: getGroupMembers, getUserByKey, getWatchers, restorePage —
/// plus the matching tool definitions and executor dispatch.
///
/// Note: `getContentVersions` is intentionally not added — the existing
/// [ConfluenceClient.getPageHistory] (GET `content/{id}/version`) already
/// covers it. The archive payload builder was generalized into the shared
/// `_statusPayload` so restore reuses it with status `current`.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getGroupMembersTests();
  getUserByKeyTests();
  getWatchersTests();
  restorePageTests();
  batch5ToolDefinitionTests();
  batch5ExecutorTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_group_members` — GET `group/{groupname}/member`.
void getGroupMembersTests() {
  group('ConfluenceClient.getGroupMembers', () {
    test('returns the member results', () async {
      final f =
          mockConfluence((o) => routeByPath({'/member': _membersBody}, o));
      final members = await f.client.getGroupMembers('admins');
      expect(members, hasLength(2));
      expect(members[0]['username'], 'alice');
      expect(members[1]['username'], 'bob');
      expect(f.adapter.calls.single.path, endsWith('/group/admins/member'));
    });
  });
}

/// `confluence_get_user_by_key` — GET `user?key={key}`.
void getUserByKeyTests() {
  group('ConfluenceClient.getUserByKey', () {
    test('GETs the user with the key query parameter', () async {
      final f = mockConfluence((o) => routeByPath({'/user': _userBody}, o));
      final user = await f.client.getUserByKey('abc123');
      expect(user['username'], 'alice');
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/user'));
      expect(call.queryParameters['key'], 'abc123');
    });
  });
}

/// `confluence_get_watchers` — GET `content/{contentId}/notification`.
void getWatchersTests() {
  group('ConfluenceClient.getWatchers', () {
    test('returns the watcher results', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/notification': _watchersBody}, o),
      );
      final watchers = await f.client.getWatchers('42');
      expect(watchers, hasLength(1));
      expect(watchers.single['username'], 'alice');
      expect(
        f.adapter.calls.single.path,
        endsWith('/content/42/notification'),
      );
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

/// Tool-definition shape for the batch-5 tools.
void batch5ToolDefinitionTests() {
  group('batch5 tool definitions', () {
    test('confluence_get_group_members requires groupname', () {
      final tool = toolNamed('confluence_get_group_members');
      expect(tool.category, 'groups');
      expect(tool.params.single.name, 'groupname');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_get_user_by_key requires key', () {
      final tool = toolNamed('confluence_get_user_by_key');
      expect(tool.category, 'users');
      expect(tool.params.single.name, 'key');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_get_watchers requires contentId', () {
      final tool = toolNamed('confluence_get_watchers');
      expect(tool.category, 'watchers');
      expect(tool.params.single.name, 'contentId');
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

/// [ConfluenceToolExecutor.execute] routes each batch-5 tool name.
void batch5ExecutorTests() {
  group('ConfluenceToolExecutor batch5 dispatch', () {
    test('routes confluence_get_group_members', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_group_members',
        {'groupname': 'admins'},
      );
      expect(f.client.calls, ['getGroupMembers:admins']);
    });

    test('routes confluence_get_user_by_key', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_user_by_key',
        {'key': 'abc123'},
      );
      expect(f.client.calls, ['getUserByKey:abc123']);
    });

    test('routes confluence_get_watchers', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_watchers',
        {'contentId': '42'},
      );
      expect(f.client.calls, ['getWatchers:42']);
    });

    test('routes confluence_restore_page', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_restore_page', {'id': '42'});
      expect(f.client.calls, ['restorePage:42']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _Batch5Spy client}) _makeExecutor() {
  final client = _Batch5Spy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned group-members response body.
final _membersBody = jsonEncode({
  'results': [
    {'username': 'alice'},
    {'username': 'bob'},
  ],
});

/// Canned user response body.
const _userBody = '{"username":"alice","key":"abc123"}';

/// Canned watchers response body.
final _watchersBody = jsonEncode({
  'results': [
    {'username': 'alice'},
  ],
});

/// Canned restore response body.
const _restoredBody = '{"id":"42","type":"page","status":"current"}';

/// Spy that records every batch-5 call then delegates to the real client.
class _Batch5Spy extends ConfluenceClient {
  _Batch5Spy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupname) {
    calls.add('getGroupMembers:$groupname');
    return super.getGroupMembers(groupname);
  }

  @override
  Future<Map<String, dynamic>> getUserByKey(String key) {
    calls.add('getUserByKey:$key');
    return super.getUserByKey(key);
  }

  @override
  Future<List<Map<String, dynamic>>> getWatchers(String contentId) {
    calls.add('getWatchers:$contentId');
    return super.getWatchers(contentId);
  }

  @override
  Future<Map<String, dynamic>> restorePage(String id) {
    calls.add('restorePage:$id');
    return super.restorePage(id);
  }
}
