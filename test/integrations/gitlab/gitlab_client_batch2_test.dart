import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Batch-2 GitLab tools: merge/close MR, MR diff, issues, branches, files,
/// and project members — client method coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  mergeMrTests();
  closeMrTests();
  getMrDiffTests();
  createIssueTests();
  listIssuesTests();
  createBranchTests();
  getFileContentTests();
  getProjectMembersTests();
  mrExecutorBatch2Tests();
  issueExecutorBatch2Tests();
  repoExecutorBatch2Tests();
}

/// Canned merge-request body (post state transition).
const _mrBody = '{"iid":42,"state":"merged"}';

/// Canned merge-request changes body.
const _mrDiffBody =
    '{"iid":42,"changes":[{"old_path":"a.dart","new_path":"a.dart"}]}';

/// Canned issue body.
const _issueBody = '{"iid":7,"title":"Bug"}';

/// Canned issue-list body.
const _issueListBody = '[{"iid":1,"title":"I1"},{"iid":2,"title":"I2"}]';

/// Canned branch body.
const _branchBody = '{"name":"feature","ref":"main"}';

/// Canned file body (base64 content omitted for brevity).
const _fileBody = '{"file_name":"main.dart","ref":"main"}';

/// Canned project-member list body.
const _membersBody = '[{"id":1,"username":"alice"},{"id":2,"username":"bob"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_merge_mr` — PUT state_event=merge.
void mergeMrTests() {
  group('GitlabClient.mergeMr', () {
    test('PUTs state_event=merge and returns the MR', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42': _mrBody}, o),
      );
      final mr = await f.client.mergeMr('group/proj', 42);
      expect(mr?['iid'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/api/v4/projects/group%2Fproj/merge_requests/42'),
      );
      expect(jsonDecode(call.data as String), {'state_event': 'merge'});
    });
  });
}

/// `gitlab_close_mr` — PUT state_event=close.
void closeMrTests() {
  group('GitlabClient.closeMr', () {
    test('PUTs state_event=close and returns the MR', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42': _mrBody}, o),
      );
      final mr = await f.client.closeMr('1', 42);
      expect(mr?['iid'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(jsonDecode(call.data as String), {'state_event': 'close'});
    });
  });
}

/// `gitlab_get_mr_diff` — GET /merge_requests/{iid}/changes.
void getMrDiffTests() {
  group('GitlabClient.getMrDiff', () {
    test('GETs the changes endpoint', () async {
      final f = mockGitlab((o) => routeByPath({'/changes': _mrDiffBody}, o));
      final diff = await f.client.getMrDiff('1', 42);
      expect(diff?['changes'], isNotNull);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/merge_requests/42/changes'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/changes': '[]'}, o));
      expect(await f.client.getMrDiff('1', 42), isNull);
    });
  });
}

/// `gitlab_create_issue` — POST /issues.
void createIssueTests() {
  group('GitlabClient.createIssue', () {
    test('POSTs title only when description omitted', () async {
      final f = mockGitlab((o) => routeByPath({'/issues': _issueBody}, o));
      final issue = await f.client.createIssue('1', 'Bug');
      expect(issue?['title'], 'Bug');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {'title': 'Bug'});
    });

    test('includes description when provided', () async {
      final f = mockGitlab((o) => routeByPath({'/issues': _issueBody}, o));
      await f.client.createIssue('1', 'Bug', 'details here');
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'title': 'Bug', 'description': 'details here'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/issues': '[]'}, o));
      expect(await f.client.createIssue('1', 'Bug'), isNull);
    });
  });
}

/// `gitlab_list_issues` — GET /issues?state=...&per_page=20.
void listIssuesTests() {
  group('GitlabClient.listIssues', () {
    test('returns the decoded list with default state', () async {
      final f = mockGitlab((o) => routeByPath({'/issues': _issueListBody}, o));
      final issues = await f.client.listIssues('1');
      expect(issues.map((i) => i['iid']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/api/v4/projects/1/issues'));
      expect(call.queryParameters['state'], 'opened');
      expect(call.queryParameters['per_page'], 20);
    });

    test('passes a custom state filter', () async {
      final f = mockGitlab((o) => routeByPath({'/issues': '[]'}, o));
      await f.client.listIssues('1', 'closed');
      expect(f.adapter.calls.single.queryParameters['state'], 'closed');
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/issues': '{}'}, o));
      expect(await f.client.listIssues('1'), isEmpty);
    });
  });
}

/// `gitlab_create_branch` — POST /repository/branches.
void createBranchTests() {
  group('GitlabClient.createBranch', () {
    test('POSTs branch and ref to the branches endpoint', () async {
      final f = mockGitlab((o) => routeByPath({'/branches': _branchBody}, o));
      final branch = await f.client.createBranch('1', 'feature', 'main');
      expect(branch?['name'], 'feature');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/repository/branches'));
      expect(
        jsonDecode(call.data as String),
        {'branch': 'feature', 'ref': 'main'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/branches': '[]'}, o));
      expect(await f.client.createBranch('1', 'f', 'main'), isNull);
    });
  });
}

/// `gitlab_get_file_content` — GET /repository/files/{encodedPath}.
void getFileContentTests() {
  group('GitlabClient.getFileContent', () {
    test('GETs the URL-encoded file path', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      final file = await f.client.getFileContent('1', 'src/main.dart');
      expect(file?['file_name'], 'main.dart');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/repository/files/src%2Fmain.dart'),
      );
    });

    test('sends ref as a query parameter when provided', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      await f.client.getFileContent('1', 'src/main.dart', 'develop');
      expect(f.adapter.calls.single.queryParameters['ref'], 'develop');
    });

    test('omits the ref query parameter when not provided', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      await f.client.getFileContent('1', 'src/main.dart');
      expect(
        f.adapter.calls.single.queryParameters.containsKey('ref'),
        isFalse,
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': '[]'}, o),
      );
      expect(await f.client.getFileContent('1', 'src/main.dart'), isNull);
    });
  });
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

/// Executor dispatch for the batch-2 merge-request tools.
void mrExecutorBatch2Tests() {
  group('GitlabToolExecutor batch-2 (MR)', () {
    test('gitlab_merge_mr routes project and iid', () async {
      final f =
          _executor((o) => routeByPath({'/merge_requests/3': _mrBody}, o));
      await f.executor.execute('gitlab_merge_mr', {'project': '1', 'iid': 3});
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(jsonDecode(call.data as String), {'state_event': 'merge'});
    });

    test('gitlab_close_mr routes project and iid', () async {
      final f =
          _executor((o) => routeByPath({'/merge_requests/3': _mrBody}, o));
      await f.executor.execute('gitlab_close_mr', {'project': '1', 'iid': 3});
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'state_event': 'close'},
      );
    });

    test('gitlab_get_mr_diff routes project and iid', () async {
      final f = _executor((o) => routeByPath({'/changes': _mrDiffBody}, o));
      await f.executor
          .execute('gitlab_get_mr_diff', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/changes'),
      );
    });
  });
}

/// Executor dispatch for the batch-2 issue tools.
void issueExecutorBatch2Tests() {
  group('GitlabToolExecutor batch-2 (issues)', () {
    test('gitlab_create_issue routes title and optional description', () async {
      final f = _executor((o) => routeByPath({'/issues': _issueBody}, o));
      await f.executor.execute('gitlab_create_issue', {
        'project': '1',
        'title': 'Bug',
        'description': 'd',
      });
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'title': 'Bug', 'description': 'd'},
      );
    });

    test('gitlab_list_issues routes project and default state', () async {
      final f = _executor((o) => routeByPath({'/issues': _issueListBody}, o));
      await f.executor.execute('gitlab_list_issues', {'project': '1'});
      expect(f.adapter.calls.single.queryParameters['state'], 'opened');
    });
  });
}

/// Executor dispatch for the batch-2 repository and member tools.
void repoExecutorBatch2Tests() {
  group('GitlabToolExecutor batch-2 (repo/members)', () {
    test('gitlab_create_branch routes branch and ref', () async {
      final f = _executor((o) => routeByPath({'/branches': _branchBody}, o));
      await f.executor.execute('gitlab_create_branch', {
        'project': '1',
        'branch': 'feat',
        'ref': 'main',
      });
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'branch': 'feat', 'ref': 'main'},
      );
    });

    test('gitlab_get_file_content routes file_path', () async {
      final f = _executor(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      await f.executor.execute('gitlab_get_file_content', {
        'project': '1',
        'file_path': 'src/main.dart',
      });
      expect(
        f.adapter.calls.single.path,
        endsWith('/repository/files/src%2Fmain.dart'),
      );
    });

    test('gitlab_get_project_members routes project', () async {
      final f = _executor((o) => routeByPath({'/members': _membersBody}, o));
      await f.executor.execute('gitlab_get_project_members', {'project': '1'});
      expect(f.adapter.calls.single.path, endsWith('/projects/1/members'));
    });
  });
}
