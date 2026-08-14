import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Workflow catalog — list, enable, and disable — [GithubClient] methods
/// plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getWorkflowsTests();
  enableWorkflowTests();
  disableWorkflowTests();
  executorWorkflowCatalogTests();
}

/// `github_get_workflows` — GET `/repos/{owner}/{repo}/actions/workflows`.
void getWorkflowsTests() {
  group('GithubClient.getWorkflows', () {
    test('GETs the workflows catalog', () async {
      final f = mockGithub(
        (o) => routeByPath({'/actions/workflows': _workflowsBody}, o),
      );
      final workflows = await f.client.getWorkflows('epm', 'dm.ai');
      expect(workflows['total_count'], 1);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/actions/workflows'),
      );
    });
  });
}

/// `github_enable_workflow` — PUT `.../actions/workflows/{id}/enable`.
void enableWorkflowTests() {
  group('GithubClient.enableWorkflow', () {
    test('PUTs enable and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/enable': ''}, o));
      expect(await f.client.enableWorkflow('epm', 'dm.ai', 7), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/enable'),
      );
    });
  });
}

/// `github_disable_workflow` — PUT `.../actions/workflows/{id}/disable`.
void disableWorkflowTests() {
  group('GithubClient.disableWorkflow', () {
    test('PUTs disable and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/disable': ''}, o));
      expect(await f.client.disableWorkflow('epm', 'dm.ai', 7), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/disable'),
      );
    });
  });
}

/// Executor routing for the workflow-catalog tools.
void executorWorkflowCatalogTests() {
  group('GithubToolExecutor.execute (workflows)', () {
    test('routes github_get_workflows', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_get_workflows',
        _repoArgs,
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/workflows'),
      );
    });

    test('routes github_enable_workflow with a coerced workflow_id', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_enable_workflow',
        {..._repoArgs, 'workflow_id': '7'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/enable'),
      );
    });

    test('routes github_disable_workflow', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_disable_workflow',
        {..._repoArgs, 'workflow_id': 7},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/disable'),
      );
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves the canned workflows body, `''` for the enable/disable endpoints.
String _router(RequestOptions o) {
  if (o.path.endsWith('/enable') || o.path.endsWith('/disable')) return '';
  return _workflowsBody;
}

/// Canned workflows-catalog body.
const _workflowsBody = '{"total_count":1,"workflows":[{"id":7,"name":"CI"}]}';
