import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab member tools: project members and group members — client method
/// coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getProjectMembersTests();
  getGroupMembersTests();
  memberExecutorDispatchTests();
}

/// Canned project-member list body.
const _membersBody = '[{"id":1,"username":"alice"},{"id":2,"username":"bob"}]';

/// Canned group-member list body.
const _groupMembersBody = '[{"id":1,"username":"carol"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_get_project_members` — GET /members.
void getProjectMembersTests() {
  group('GitlabClient.getProjectMembers', () {
    test('returns the decoded member list', () async {
      final f = mockGitlab((o) => routeByPath({'/members': _membersBody}, o));
      final members = await f.client.getProjectMembers('1');
      expect(
        members.map((m) => m['username']).toList(),
        ['alice', 'bob'],
      );
      expect(
          f.adapter.calls.single.path, endsWith('/api/v4/projects/1/members'));
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/members': '{}'}, o));
      expect(await f.client.getProjectMembers('1'), isEmpty);
    });
  });
}

/// `gitlab_get_group_members` — GET /groups/{id}/members.
void getGroupMembersTests() {
  group('GitlabClient.getGroupMembers', () {
    test('returns the decoded group-member list', () async {
      final f =
          mockGitlab((o) => routeByPath({'/members': _groupMembersBody}, o));
      final members = await f.client.getGroupMembers('5');
      expect(members.single['username'], 'carol');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/groups/5/members'),
      );
    });

    test('URL-encodes a group/subgroup path', () async {
      final f =
          mockGitlab((o) => routeByPath({'/members': _groupMembersBody}, o));
      await f.client.getGroupMembers('group/sub');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/groups/group%2Fsub/members'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/members': '{}'}, o));
      expect(await f.client.getGroupMembers('5'), isEmpty);
    });
  });
}

/// [GitlabToolExecutor.execute] routes each member tool name.
void memberExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (members)', () {
    test('gitlab_get_project_members routes project', () async {
      final f = _executor((o) => routeByPath({'/members': _membersBody}, o));
      await f.executor.execute('gitlab_get_project_members', {'project': '1'});
      expect(f.adapter.calls.single.path, endsWith('/projects/1/members'));
    });

    test('gitlab_get_group_members routes group_id', () async {
      final f =
          _executor((o) => routeByPath({'/members': _groupMembersBody}, o));
      await f.executor.execute('gitlab_get_group_members', {'group_id': '5'});
      expect(f.adapter.calls.single.path, endsWith('/groups/5/members'));
    });
  });
}
