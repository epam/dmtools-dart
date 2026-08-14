import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Group coverage: `confluence_get_group_members` — client method, tool
/// definition, and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getGroupMembersTests();
  groupToolDefinitionTests();
  groupExecutorDispatchTests();
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

/// Tool-definition shape for the group tools.
void groupToolDefinitionTests() {
  group('confluence tool definitions (groups)', () {
    test('confluence_get_group_members requires groupname', () {
      final tool = toolNamed('confluence_get_group_members');
      expect(tool.category, 'groups');
      expect(tool.params.single.name, 'groupname');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each group tool name.
void groupExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (groups)', () {
    test('routes confluence_get_group_members', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_group_members',
        {'groupname': 'admins'},
      );
      expect(f.client.calls, ['getGroupMembers:admins']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _GroupsSpy client}) _makeExecutor() {
  final client = _GroupsSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned group-members response body.
final _membersBody = jsonEncode({
  'results': [
    {'username': 'alice'},
    {'username': 'bob'},
  ],
});

/// Spy that records every group call then delegates to the real client.
class _GroupsSpy extends ConfluenceClient {
  _GroupsSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupname) {
    calls.add('getGroupMembers:$groupname');
    return super.getGroupMembers(groupname);
  }
}
