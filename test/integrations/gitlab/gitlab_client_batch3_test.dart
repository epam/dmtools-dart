import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Batch-3 GitLab tools: MR approvals/notes, pipelines, tags, branches, and
/// group members — client method coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  approveMrTests();
  unapproveMrTests();
  getMrNotesTests();
  getPipelinesTests();
  triggerPipelineTests();
  getPipelineTests();
  createTagTests();
  getTagsTests();
  getBranchesTests();
  getGroupMembersTests();
  mrExecutorBatch3Tests();
  pipelineExecutorBatch3Tests();
  repoExecutorBatch3Tests();
  memberExecutorBatch3Tests();
}

/// Canned approved merge-request body.
const _mrApprovedBody = '{"iid":42,"merge_status":"can_be_merged"}';

/// Canned MR notes list body.
const _notesBody = '[{"id":1,"body":"note one"},{"id":2,"body":"note two"}]';

/// Canned pipeline body.
const _pipelineBody = '{"id":7,"ref":"main","status":"success"}';

/// Canned pipeline-list body.
const _pipelinesBody =
    '[{"id":7,"status":"success"},{"id":8,"status":"failed"}]';

/// Canned tag body.
const _tagBody = '{"name":"v1.0","ref":"abc123"}';

/// Canned tag-list body.
const _tagsBody = '[{"name":"v1.0"},{"name":"v1.1"}]';

/// Canned branch-list body.
const _branchesBody = '[{"name":"main"},{"name":"feature"}]';

/// Canned group-member list body.
const _groupMembersBody = '[{"id":1,"username":"carol"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
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

/// `gitlab_get_pipelines` — GET /pipelines.
void getPipelinesTests() {
  group('GitlabClient.getPipelines', () {
    test('returns the decoded pipeline list', () async {
      final f =
          mockGitlab((o) => routeByPath({'/pipelines': _pipelinesBody}, o));
      final pipelines = await f.client.getPipelines('1');
      expect(pipelines.map((p) => p['id']).toList(), [7, 8]);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/pipelines'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/pipelines': '{}'}, o));
      expect(await f.client.getPipelines('1'), isEmpty);
    });
  });
}

/// `gitlab_trigger_pipeline` — POST /pipeline with ref.
void triggerPipelineTests() {
  group('GitlabClient.triggerPipeline', () {
    test('POSTs the ref to the pipeline trigger endpoint', () async {
      final f = mockGitlab((o) => routeByPath({'/pipeline': _pipelineBody}, o));
      final pipeline = await f.client.triggerPipeline('1', 'main');
      expect(pipeline?['id'], 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/pipeline'));
      expect(jsonDecode(call.data as String), {'ref': 'main'});
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/pipeline': '[]'}, o));
      expect(await f.client.triggerPipeline('1', 'main'), isNull);
    });
  });
}

/// `gitlab_get_pipeline` — GET /pipelines/{id}.
void getPipelineTests() {
  group('GitlabClient.getPipeline', () {
    test('GETs the pipeline by id', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/pipelines/7': _pipelineBody}, o),
      );
      final pipeline = await f.client.getPipeline('1', 7);
      expect(pipeline?['status'], 'success');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/pipelines/7'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/pipelines/7': '[]'}, o));
      expect(await f.client.getPipeline('1', 7), isNull);
    });
  });
}

/// `gitlab_create_tag` — POST /repository/tags.
void createTagTests() {
  group('GitlabClient.createTag', () {
    test('POSTs tag_name and ref to the tags endpoint', () async {
      final f =
          mockGitlab((o) => routeByPath({'/repository/tags': _tagBody}, o));
      final tag = await f.client.createTag('1', 'v1.0', 'main');
      expect(tag?['name'], 'v1.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/repository/tags'));
      expect(
        jsonDecode(call.data as String),
        {'tag_name': 'v1.0', 'ref': 'main'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/repository/tags': '[]'}, o));
      expect(await f.client.createTag('1', 'v1.0', 'main'), isNull);
    });
  });
}

/// `gitlab_get_tags` — GET /repository/tags.
void getTagsTests() {
  group('GitlabClient.getTags', () {
    test('returns the decoded tag list', () async {
      final f =
          mockGitlab((o) => routeByPath({'/repository/tags': _tagsBody}, o));
      final tags = await f.client.getTags('1');
      expect(tags.map((t) => t['name']).toList(), ['v1.0', 'v1.1']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/repository/tags'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/repository/tags': '{}'}, o));
      expect(await f.client.getTags('1'), isEmpty);
    });
  });
}

/// `gitlab_get_branches` — GET /repository/branches.
void getBranchesTests() {
  group('GitlabClient.getBranches', () {
    test('returns the decoded branch list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/repository/branches': _branchesBody}, o),
      );
      final branches = await f.client.getBranches('1');
      expect(branches.map((b) => b['name']).toList(), ['main', 'feature']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/repository/branches'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/repository/branches': '{}'}, o),
      );
      expect(await f.client.getBranches('1'), isEmpty);
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

/// Executor dispatch for the batch-3 merge-request tools.
void mrExecutorBatch3Tests() {
  group('GitlabToolExecutor batch-3 (MR)', () {
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
  });
}

/// Executor dispatch for the batch-3 pipeline tools.
void pipelineExecutorBatch3Tests() {
  group('GitlabToolExecutor batch-3 (pipelines)', () {
    test('gitlab_get_pipelines routes project', () async {
      final f =
          _executor((o) => routeByPath({'/pipelines': _pipelinesBody}, o));
      await f.executor.execute('gitlab_get_pipelines', {'project': '1'});
      expect(f.adapter.calls.single.path, endsWith('/projects/1/pipelines'));
    });

    test('gitlab_trigger_pipeline routes project and ref', () async {
      final f = _executor((o) => routeByPath({'/pipeline': _pipelineBody}, o));
      await f.executor.execute(
        'gitlab_trigger_pipeline',
        {'project': '1', 'ref': 'main'},
      );
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'ref': 'main'},
      );
    });

    test('gitlab_get_pipeline routes project and pipeline_id', () async {
      final f = _executor(
        (o) => routeByPath({'/pipelines/7': _pipelineBody}, o),
      );
      await f.executor.execute(
        'gitlab_get_pipeline',
        {'project': '1', 'pipeline_id': 7},
      );
      expect(f.adapter.calls.single.path, endsWith('/projects/1/pipelines/7'));
    });
  });
}

/// Executor dispatch for the batch-3 repository tools.
void repoExecutorBatch3Tests() {
  group('GitlabToolExecutor batch-3 (repo)', () {
    test('gitlab_create_tag routes tag_name and ref', () async {
      final f =
          _executor((o) => routeByPath({'/repository/tags': _tagBody}, o));
      await f.executor.execute('gitlab_create_tag', {
        'project': '1',
        'tag_name': 'v1.0',
        'ref': 'main',
      });
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'tag_name': 'v1.0', 'ref': 'main'},
      );
    });

    test('gitlab_get_tags routes project', () async {
      final f =
          _executor((o) => routeByPath({'/repository/tags': _tagsBody}, o));
      await f.executor.execute('gitlab_get_tags', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/repository/tags'),
      );
    });

    test('gitlab_get_branches routes project', () async {
      final f = _executor(
        (o) => routeByPath({'/repository/branches': _branchesBody}, o),
      );
      await f.executor.execute('gitlab_get_branches', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/repository/branches'),
      );
    });
  });
}

/// Executor dispatch for the batch-3 group-member tool.
void memberExecutorBatch3Tests() {
  group('GitlabToolExecutor batch-3 (members)', () {
    test('gitlab_get_group_members routes group_id', () async {
      final f =
          _executor((o) => routeByPath({'/members': _groupMembersBody}, o));
      await f.executor.execute('gitlab_get_group_members', {'group_id': '5'});
      expect(f.adapter.calls.single.path, endsWith('/groups/5/members'));
    });
  });
}
