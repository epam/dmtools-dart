import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Tests for [GitlabIssueTrackerTools] (`gitlab_client_issue_tools.dart`)
/// and [GitlabToolExecutor] issue-tracker dispatch.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  _testIssueRefResolution();
  _testIssueTrackerReadAndStateRoutes();
  _testIssueTrackerMetaRoutes();
}

void _testIssueRefResolution() {
  group('resolveGlIssueRef & resolveGlProjectPath', () {
    test('parses composite, gl-N, bare IID, and explicit workspace/repo', () {
      PropertyReader.setOverrides({
        'GITLAB_WORKSPACE': 'defws',
        'GITLAB_REPOSITORY': 'defrp',
      });
      final c1 = resolveGlIssueRef(key: 'org/sub/repo#42');
      expect(c1.projectPath, 'org/sub/repo');
      expect(c1.iid, '42');

      final c2 = resolveGlIssueRef(key: 'gl-17');
      expect(c2.projectPath, 'defws/defrp');
      expect(c2.iid, '17');

      final c3 = resolveGlIssueRef(key: '19');
      expect(c3.projectPath, 'defws/defrp');
      expect(c3.iid, '19');

      final c4 = resolveGlIssueRef(
        workspace: 'expws',
        repository: 'exprp',
        issueNumber: '5',
      );
      expect(c4.projectPath, 'expws/exprp');
      expect(c4.iid, '5');

      expect(resolveGlProjectPath(key: 'grp/proj'), 'grp/proj');
      expect(resolveGlProjectPath(project: 'direct/proj'), 'direct/proj');
      expect(resolveGlProjectPath(), 'defws/defrp');
    });

    test('throws ArgumentError on malformed key or unconfigured project', () {
      PropertyReader.clearOverrides();
      expect(() => parseGlIssueKey('bad-key'), throwsArgumentError);
      expect(() => resolveGlIssueRef(key: 'gl-1'), throwsArgumentError);
      expect(resolveGlProjectPath, throwsArgumentError);
    });
  });
}

void _testIssueTrackerReadAndStateRoutes() {
  test('executes get, search, create, close, reopen, and move_issue_to_status',
      () async {
    final fix = mockGitlab(_issueRouter);
    PropertyReader.setOverrides({
      'GITLAB_BASE_PATH': 'https://gitlab.example.com',
      'GITLAB_TOKEN': 'glpat-123',
      'GITLAB_WORKSPACE': 'ws',
      'GITLAB_REPOSITORY': 'rp',
    });
    final exec = GitlabToolExecutor(fix.client);
    await exec.execute('gitlab_get_issue', {'key': 'ws/rp#3'});
    await exec.execute('gitlab_search_issues', {'query': 'bug'});
    await exec.execute('gitlab_create_issue', {
      'key': 'ws/rp',
      'title': 'New',
      'body': 'Desc',
    });
    await exec.execute('gitlab_close_issue', {'key': 'gl-3'});
    await exec.execute('gitlab_reopen_issue', {'key': 'gl-3'});
    await exec.execute('gitlab_move_issue_to_status', {
      'key': 'gl-3',
      'statusName': 'done',
    });
    await exec.execute('gitlab_move_issue_to_status', {
      'key': 'gl-3',
      'statusName': 'reopened',
    });
    await exec.execute('gitlab_move_issue_to_status', {
      'key': 'gl-3',
      'statusName': 'In Progress',
    });
    expect(fix.adapter.calls, isNotEmpty);
  });
}

void _testIssueTrackerMetaRoutes() {
  test('executes labels, comments, and assign_issue', () async {
    final fix = mockGitlab(_issueRouter);
    PropertyReader.setOverrides({
      'GITLAB_BASE_PATH': 'https://gitlab.example.com',
      'GITLAB_TOKEN': 'glpat-123',
      'GITLAB_WORKSPACE': 'ws',
      'GITLAB_REPOSITORY': 'rp',
    });
    final exec = GitlabToolExecutor(fix.client);
    await exec.execute('gitlab_add_issue_label', {
      'key': 'gl-3',
      'label': 'l1',
    });
    await exec.execute('gitlab_remove_issue_label', {
      'key': 'gl-3',
      'label': 'l1',
    });
    await exec.execute('gitlab_create_issue_comment', {
      'key': 'gl-3',
      'body': 'hi',
    });
    final notes = await exec
        .execute('gitlab_get_issue_comments', {'key': 'gl-3'}) as List;
    expect(notes, hasLength(1));

    await exec.execute('gitlab_assign_issue', {
      'key': 'gl-3',
      'user': 'alice',
    });
    expect(
      () => exec.execute('gitlab_assign_issue', {
        'key': 'gl-3',
        'user': 'ghost',
      }),
      throwsStateError,
    );
  });
}

String _issueRouter(RequestOptions o) {
  if (o.path.endsWith('/users')) {
    final u = o.queryParameters['username'];
    return u == 'ghost'
        ? '[]'
        : jsonEncode([
            {'id': 11, 'username': u}
          ]);
  }
  if (o.method == 'GET' && o.path.endsWith('/notes')) {
    return jsonEncode([
      {'id': 1, 'body': 'note'}
    ]);
  }
  if (o.method == 'GET' && o.path.endsWith('/issues')) {
    return jsonEncode([
      {'iid': 3, 'title': 'bug'}
    ]);
  }
  return jsonEncode({'iid': 3, 'state': 'opened'});
}
