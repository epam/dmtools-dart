import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Batch-4 GitLab tools: MR approvals/discussions, discussion resolve, and
/// project details/variables — client method coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getMrApprovalsTests();
  getMrDiscussionsTests();
  triggerMrDiscussionResolveTests();
  getProjectDetailsTests();
  getProjectVariablesTests();
  mrExecutorBatch4Tests();
  mrDiscussionResolveExecutorBatch4Tests();
  projectExecutorBatch4Tests();
}

/// Canned MR approvals body.
const _approvalsBody = '{"id":42,"approvals_required":2,"approved":true}';

/// Canned MR discussions body.
const _discussionsBody = '[{"id":"d1","notes":[]},{"id":"d2","notes":[]}]';

/// Canned resolved-discussion body.
const _discussionBody = '{"id":"d1","notes":[{"resolved":true}]}';

/// Canned project-details body.
const _projectBody = '{"id":1,"name":"My Project","path_with_namespace":"g/p"}';

/// Canned project-variables body.
const _variablesBody = '[{"key":"VAR","value":"x"},{"key":"CI","value":"1"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_get_mr_approvals` — GET /merge_requests/{iid}/approvals.
void getMrApprovalsTests() {
  group('GitlabClient.getMrApprovals', () {
    test('GETs the approvals endpoint', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/approvals': _approvalsBody}, o),
      );
      final approvals = await f.client.getMrApprovals('group/proj', 42);
      expect(approvals?['approved'], isTrue);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/api/v4/projects/group%2Fproj/merge_requests/42/approvals'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/approvals': '[]'}, o),
      );
      expect(await f.client.getMrApprovals('1', 42), isNull);
    });
  });
}

/// `gitlab_get_mr_discussions` — GET /merge_requests/{iid}/discussions.
void getMrDiscussionsTests() {
  group('GitlabClient.getMrDiscussions', () {
    test('returns the decoded discussions list', () async {
      final f = mockGitlab(
        (o) => routeByPath(
          {'/merge_requests/42/discussions': _discussionsBody},
          o,
        ),
      );
      final discussions = await f.client.getMrDiscussions('1', 42);
      expect(discussions.map((d) => d['id']).toList(), ['d1', 'd2']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/merge_requests/42/discussions'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/discussions': '{}'}, o),
      );
      expect(await f.client.getMrDiscussions('1', 42), isEmpty);
    });
  });
}

/// `gitlab_trigger_mr_discussion_resolve` — PUT discussions/{id} with resolved.
void triggerMrDiscussionResolveTests() {
  group('GitlabClient.triggerMrDiscussionResolve', () {
    test('PUTs resolved=true to the discussion endpoint', () async {
      final f = mockGitlab(
        (o) => routeByPath(
          {'/discussions/d1': _discussionBody},
          o,
        ),
      );
      final result =
          await f.client.triggerMrDiscussionResolve('1', 42, 'd1', true);
      expect(result?['id'], 'd1');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/api/v4/projects/1/merge_requests/42/discussions/d1'),
      );
      expect(jsonDecode(call.data as String), {'resolved': true});
    });

    test('PUTs resolved=false when unresolving', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/discussions/d1': _discussionBody}, o),
      );
      await f.client.triggerMrDiscussionResolve('1', 42, 'd1', false);
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'resolved': false},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/discussions/d1': '[]'}, o),
      );
      expect(
        await f.client.triggerMrDiscussionResolve('1', 42, 'd1', true),
        isNull,
      );
    });
  });
}

/// `gitlab_get_project_details` — GET /projects/{id}.
void getProjectDetailsTests() {
  group('GitlabClient.getProjectDetails', () {
    test('GETs the project by id', () async {
      final f =
          mockGitlab((o) => routeByPath({'/projects/1': _projectBody}, o));
      final project = await f.client.getProjectDetails('1');
      expect(project?['name'], 'My Project');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1'),
      );
    });

    test('URL-encodes a group/project path', () async {
      final f =
          mockGitlab((o) => routeByPath({'/projects/g%2Fp': _projectBody}, o));
      await f.client.getProjectDetails('g/p');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/g%2Fp'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/projects/1': '[]'}, o));
      expect(await f.client.getProjectDetails('1'), isNull);
    });
  });
}

/// `gitlab_get_project_variables` — GET /projects/{id}/variables.
void getProjectVariablesTests() {
  group('GitlabClient.getProjectVariables', () {
    test('returns the decoded variables list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/variables': _variablesBody}, o),
      );
      final vars = await f.client.getProjectVariables('1');
      expect(vars.map((v) => v['key']).toList(), ['VAR', 'CI']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/variables'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/variables': '{}'}, o));
      expect(await f.client.getProjectVariables('1'), isEmpty);
    });
  });
}

/// Executor dispatch for the batch-4 merge-request tools.
/// Executor dispatch for the batch-4 MR approvals and discussions tools.
void mrExecutorBatch4Tests() {
  group('GitlabToolExecutor batch-4 (MR read)', () {
    test('gitlab_get_mr_approvals routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath(
          {'/merge_requests/3/approvals': _approvalsBody},
          o,
        ),
      );
      await f.executor
          .execute('gitlab_get_mr_approvals', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/approvals'),
      );
    });

    test('gitlab_get_mr_discussions routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath(
          {'/merge_requests/3/discussions': _discussionsBody},
          o,
        ),
      );
      await f.executor
          .execute('gitlab_get_mr_discussions', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/discussions'),
      );
    });
  });
}

/// Executor dispatch for the batch-4 discussion-resolve tool.
void mrDiscussionResolveExecutorBatch4Tests() {
  group('GitlabToolExecutor batch-4 (discussion resolve)', () {
    test('gitlab_trigger_mr_discussion_resolve routes all params', () async {
      final f = _executor(
        (o) => routeByPath({'/discussions/d1': _discussionBody}, o),
      );
      await f.executor.execute('gitlab_trigger_mr_discussion_resolve', {
        'project': '1',
        'iid': 3,
        'discussion_id': 'd1',
        'resolved': true,
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/discussions/d1'));
      expect(jsonDecode(call.data as String), {'resolved': true});
    });

    test('accepts a string resolved flag', () async {
      final f = _executor(
        (o) => routeByPath({'/discussions/d1': _discussionBody}, o),
      );
      await f.executor.execute('gitlab_trigger_mr_discussion_resolve', {
        'project': '1',
        'iid': 3,
        'discussion_id': 'd1',
        'resolved': 'false',
      });
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'resolved': false},
      );
    });
  });
}

/// Executor dispatch for the batch-4 project tools.
void projectExecutorBatch4Tests() {
  group('GitlabToolExecutor batch-4 (projects)', () {
    test('gitlab_get_project_details routes project', () async {
      final f = _executor(
        (o) => routeByPath({'/projects/1': _projectBody}, o),
      );
      await f.executor.execute('gitlab_get_project_details', {'project': '1'});
      expect(f.adapter.calls.single.path, endsWith('/projects/1'));
    });

    test('gitlab_get_project_variables routes project', () async {
      final f = _executor(
        (o) => routeByPath({'/variables': _variablesBody}, o),
      );
      await f.executor
          .execute('gitlab_get_project_variables', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/variables'),
      );
    });
  });
}
