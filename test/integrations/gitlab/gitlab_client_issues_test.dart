import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab issue tools: create and list — client method coverage plus executor
/// dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  createIssueTests();
  listIssuesTests();
  issueExecutorDispatchTests();
}

/// Canned issue body.
const _issueBody = '{"iid":7,"title":"Bug"}';

/// Canned issue-list body.
const _issueListBody = '[{"iid":1,"title":"I1"},{"iid":2,"title":"I2"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
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

/// [GitlabToolExecutor.execute] routes each issue tool name.
void issueExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (issues)', () {
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
