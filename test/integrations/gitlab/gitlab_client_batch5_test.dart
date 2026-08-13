import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Batch-5 GitLab tools: MR pipelines, MR block/unblock, and project webhooks
/// — [GitlabClient] methods plus [GitlabToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getMrPipelinesTests();
  blockMrTests();
  unblockMrTests();
  getProjectHooksTests();
  addProjectHookTests();
  mrPipelineExecutorBatch5Tests();
  mrBlockExecutorBatch5Tests();
  projectHookExecutorBatch5Tests();
}

/// Canned MR pipelines body.
const _pipelinesBody =
    '[{"id":1,"status":"success"},{"id":2,"status":"running"}]';

/// Canned MR block/unblock body.
const _mrBody = '{"id":42,"title":"MR","detailed_merge_status":"blocked"}';

/// Canned project-hooks body.
const _hooksBody =
    '[{"id":1,"url":"https://a.example/hook"},{"id":2,"url":"https://b.example/hook"}]';

/// Canned created project-hook body.
const _hookBody = '{"id":3,"url":"https://c.example/hook"}';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_get_mr_pipelines` — GET /merge_requests/{iid}/pipelines.
void getMrPipelinesTests() {
  group('GitlabClient.getMrPipelines', () {
    test('returns the decoded pipelines list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/pipelines': _pipelinesBody}, o),
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

/// `gitlab_block_mr` — POST /merge_requests/{iid}/block.
void blockMrTests() {
  group('GitlabClient.blockMr', () {
    test('POSTs block and returns the MR', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/block': _mrBody}, o),
      );
      final mr = await f.client.blockMr('1', 42);
      expect(mr?['id'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/api/v4/projects/1/merge_requests/42/block'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/block': '[]'}, o),
      );
      expect(await f.client.blockMr('1', 42), isNull);
    });
  });
}

/// `gitlab_unblock_mr` — POST /merge_requests/{iid}/unblock.
void unblockMrTests() {
  group('GitlabClient.unblockMr', () {
    test('POSTs unblock and returns the MR', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/merge_requests/42/unblock': _mrBody}, o),
      );
      final mr = await f.client.unblockMr('1', 42);
      expect(mr?['id'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/api/v4/projects/1/merge_requests/42/unblock'),
      );
    });
  });
}

/// `gitlab_get_project_hooks` — GET /projects/{id}/hooks.
void getProjectHooksTests() {
  group('GitlabClient.getProjectHooks', () {
    test('returns the decoded hooks list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/hooks': _hooksBody}, o),
      );
      final hooks = await f.client.getProjectHooks('1');
      expect(hooks.map((h) => h['id']).toList(), [1, 2]);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/hooks'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/hooks': '{}'}, o));
      expect(await f.client.getProjectHooks('1'), isEmpty);
    });
  });
}

/// `gitlab_add_project_hook` — POST /projects/{id}/hooks.
void addProjectHookTests() {
  group('GitlabClient.addProjectHook', () {
    test('POSTs the hook URL and returns the created hook', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/hooks': _hookBody}, o),
      );
      final hook = await f.client.addProjectHook(
        '1',
        'https://c.example/hook',
      );
      expect(hook?['id'], 3);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/api/v4/projects/1/hooks'),
      );
      expect(
        jsonDecode(call.data as String),
        {'url': 'https://c.example/hook'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/hooks': '[]'}, o));
      expect(await f.client.addProjectHook('1', 'https://x.example'), isNull);
    });
  });
}

/// Executor dispatch for the batch-5 MR-pipelines tool.
void mrPipelineExecutorBatch5Tests() {
  group('GitlabToolExecutor batch-5 (MR pipelines)', () {
    test('gitlab_get_mr_pipelines routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath({'/merge_requests/3/pipelines': _pipelinesBody}, o),
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

/// Executor dispatch for the batch-5 block/unblock tools.
void mrBlockExecutorBatch5Tests() {
  group('GitlabToolExecutor batch-5 (MR block/unblock)', () {
    test('gitlab_block_mr routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath({'/merge_requests/3/block': _mrBody}, o),
      );
      await f.executor.execute('gitlab_block_mr', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/block'),
      );
    });

    test('gitlab_unblock_mr routes project and iid', () async {
      final f = _executor(
        (o) => routeByPath({'/merge_requests/3/unblock': _mrBody}, o),
      );
      await f.executor.execute('gitlab_unblock_mr', {'project': '1', 'iid': 3});
      expect(
        f.adapter.calls.single.path,
        endsWith('/merge_requests/3/unblock'),
      );
    });
  });
}

/// Executor dispatch for the batch-5 project-hook tools.
void projectHookExecutorBatch5Tests() {
  group('GitlabToolExecutor batch-5 (project hooks)', () {
    test('gitlab_get_project_hooks routes project', () async {
      final f = _executor((o) => routeByPath({'/hooks': _hooksBody}, o));
      await f.executor.execute('gitlab_get_project_hooks', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/hooks'),
      );
    });

    test('gitlab_add_project_hook routes project and url', () async {
      final f = _executor((o) => routeByPath({'/hooks': _hookBody}, o));
      await f.executor.execute('gitlab_add_project_hook', {
        'project': '1',
        'url': 'https://c.example/hook',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/projects/1/hooks'));
      expect(
        jsonDecode(call.data as String),
        {'url': 'https://c.example/hook'},
      );
    });
  });
}
