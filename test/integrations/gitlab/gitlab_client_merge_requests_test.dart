import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab merge-request tools: state transitions (merge/close), approvals,
/// notes, discussions and resolve, diff, and MR pipelines — client method
/// coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  mergeMrTests();
  closeMrTests();
  getMrDiffTests();
  approveMrTests();
  unapproveMrTests();
  getMrNotesTests();
  getMrApprovalsTests();
  getMrDiscussionsTests();
  triggerMrDiscussionResolveTests();
  getMrPipelinesTests();
  mrStateExecutorDispatchTests();
  mrDiffExecutorDispatchTests();
  mrApprovalExecutorDispatchTests();
  mrReadExecutorDispatchTests();
  mrDiscussionResolveExecutorDispatchTests();
  mrPipelineExecutorDispatchTests();
}

/// Canned merged merge-request body (post state transition).
const _mergedMrBody = '{"iid":42,"state":"merged"}';

/// Canned merge-request changes body.
const _mrDiffBody =
    '{"iid":42,"changes":[{"old_path":"a.dart","new_path":"a.dart"}]}';

/// Canned approved merge-request body.
const _mrApprovedBody = '{"iid":42,"merge_status":"can_be_merged"}';

/// Canned MR notes list body.
const _notesBody = '[{"id":1,"body":"note one"},{"id":2,"body":"note two"}]';

/// Canned MR approvals body.
const _approvalsBody = '{"id":42,"approvals_required":2,"approved":true}';

/// Canned MR discussions body.
const _discussionsBody = '[{"id":"d1","notes":[]},{"id":"d2","notes":[]}]';

/// Canned resolved-discussion body.
const _discussionBody = '{"id":"d1","notes":[{"resolved":true}]}';

/// Canned MR pipelines body.
const _mrPipelinesBody =
    '[{"id":1,"status":"success"},{"id":2,"status":"running"}]';

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
    test('PUTs the dedicated merge endpoint and returns the MR', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/merge': _mergedMrBody}, o),
      );
      final mr = await f.client.mergeMr('group/proj', 42);
      expect(mr?['iid'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/api/v4/projects/group%2Fproj/merge_requests/42/merge'),
      );
    });
  });
}

/// `gitlab_close_mr` — PUT state_event=close.
void closeMrTests() {
  group('GitlabClient.closeMr', () {
    test('PUTs state_event=close and returns the MR', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42': _mergedMrBody}, o),
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

/// `gitlab_approve_mr` — POST /merge_requests/{iid}/approve.
void approveMrTests() {
  group('GitlabClient.approveMr', () {
    test('POSTs to the approve endpoint', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/approve': _mrApprovedBody}, o),
      );
      final mr = await f.client.approveMr('group/proj', 42);
      expect(mr?['iid'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/api/v4/projects/group%2Fproj/merge_requests/42/approve'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/approve': '[]'}, o),
      );
      expect(await f.client.approveMr('1', 42), isNull);
    });
  });
}

/// `gitlab_unapprove_mr` — POST /merge_requests/{iid}/unapprove.
void unapproveMrTests() {
  group('GitlabClient.unapproveMr', () {
    test('POSTs to the unapprove endpoint', () async {
      final f = mockGitlab(
        (o) => routeByPath(
          {'/merge_requests/42/unapprove': _mrApprovedBody},
          o,
        ),
      );
      final mr = await f.client.unapproveMr('1', 42);
      expect(mr?['iid'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/api/v4/projects/1/merge_requests/42/unapprove'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/unapprove': '[]'}, o),
      );
      expect(await f.client.unapproveMr('1', 42), isNull);
    });
  });
}

/// `gitlab_get_mr_notes` — GET /merge_requests/{iid}/notes.
void getMrNotesTests() {
  group('GitlabClient.getMrNotes', () {
    test('returns the decoded notes list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/notes': _notesBody}, o),
      );
      final notes = await f.client.getMrNotes('1', 42);
      expect(notes.map((n) => n['id']).toList(), [1, 2]);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/merge_requests/42/notes'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/notes': '{}'}, o),
      );
      expect(await f.client.getMrNotes('1', 42), isEmpty);
    });
  });
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

/// `gitlab_get_mr_pipelines` — GET /merge_requests/{iid}/pipelines.
void getMrPipelinesTests() {
  group('GitlabClient.getMrPipelines', () {
    test('returns the decoded pipelines list', () async {
      final f = mockGitlab(
        (o) =>
            routeByPath({'/merge_requests/42/pipelines': _mrPipelinesBody}, o),
      );
      final pipelines = await f.client.getMrPipelines('1', 42);
      expect(pipelines.map((p) => p['id']).toList(), [1, 2]);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/merge_requests/42/pipelines'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/pipelines': '{}'}, o),
      );
      expect(await f.client.getMrPipelines('1', 42), isEmpty);
    });
  });
}

/// [GitlabToolExecutor.execute] routes the MR state-transition tools.
void mrStateExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (merge requests)', () {
    test('gitlab_merge_mr routes project and iid', () async {
      final f = _executor(
          (o) => routeByPath({'/merge_requests/3/merge': _mergedMrBody}, o));
      await f.executor.execute('gitlab_merge_mr', {'project': '1', 'iid': 3});
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/merge_requests/3/merge'));
    });

    test('gitlab_close_mr routes project and iid', () async {
      final f = _executor(
          (o) => routeByPath({'/merge_requests/3': _mergedMrBody}, o));
      await f.executor.execute('gitlab_close_mr', {'project': '1', 'iid': 3});
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'state_event': 'close'},
      );
    });
  });
}

/// [GitlabToolExecutor.execute] routes the MR diff tool.
void mrDiffExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (merge requests)', () {
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

/// [GitlabToolExecutor.execute] routes the MR approval tools.
void mrApprovalExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (merge requests)', () {
    test('gitlab_approve_mr routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath({'/merge_requests/3/approve': _mrApprovedBody}, o),
      );
      await f.executor.execute('gitlab_approve_mr', {'project': '1', 'iid': 3});
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/merge_requests/3/approve'));
    });

    test('gitlab_unapprove_mr routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath({'/merge_requests/3/unapprove': _mrApprovedBody}, o),
      );
      await f.executor
          .execute('gitlab_unapprove_mr', {'project': '1', 'iid': 3});
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/merge_requests/3/unapprove'));
    });
  });
}

/// [GitlabToolExecutor.execute] routes the MR read tools.
void mrReadExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (merge requests)', () {
    test('gitlab_get_mr_notes routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath({'/merge_requests/3/notes': _notesBody}, o),
      );
      await f.executor
          .execute('gitlab_get_mr_notes', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/notes'),
      );
    });

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

/// [GitlabToolExecutor.execute] routes the MR discussion-resolve tool.
void mrDiscussionResolveExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (merge requests)', () {
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

/// [GitlabToolExecutor.execute] routes the MR pipelines tool.
void mrPipelineExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (merge requests)', () {
    test('gitlab_get_mr_pipelines routes project and iid', () async {
      final f = _executor(
        (o) =>
            routeByPath({'/merge_requests/3/pipelines': _mrPipelinesBody}, o),
      );
      await f.executor
          .execute('gitlab_get_mr_pipelines', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/pipelines'),
      );
    });
  });
}
