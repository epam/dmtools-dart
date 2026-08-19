import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// GitHub Actions — workflow runs, re-runs, and check runs — [GithubClient]
/// methods plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getWorkflowRunsTests();
  reRunWorkflowTests();
  getCheckRunsTests();
  executorActionsTests();
}

/// `github_get_workflow_runs` — GET `/repos/{owner}/{repo}/actions/runs`.
void getWorkflowRunsTests() {
  group('GithubClient.getWorkflowRuns', () {
    test('GETs the workflow runs object', () async {
      final f = mockGithub((o) => routeByPath({'/actions/runs': _runsBody}, o));
      final runs = await f.client.getWorkflowRuns('epm', 'dm.ai');
      expect(runs['total_count'], 1);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/actions/runs'));
    });
  });
}

/// `github_rerun_workflow` — POST
/// `/repos/{owner}/{repo}/actions/runs/{runId}/rerun`.
void reRunWorkflowTests() {
  group('GithubClient.reRunWorkflow', () {
    test('POSTs the rerun and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/rerun': ''}, o));
      expect(await f.client.reRunWorkflow('epm', 'dm.ai', 99), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/actions/runs/99/rerun'));
    });
  });
}

/// `github_get_check_runs` — GET `/repos/{owner}/{repo}/commits/{ref}/check-runs`.
void getCheckRunsTests() {
  group('GithubClient.getCheckRuns', () {
    test('GETs the check runs for a ref', () async {
      final f = mockGithub(
        (o) => routeByPath({'/check-runs': _checkRunsBody}, o),
      );
      final runs = await f.client.getCheckRuns('epm', 'dm.ai', 'main');
      expect(runs['total_count'], 1);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/commits/main/check-runs'),
      );
    });
  });
}

/// Executor routing for the Actions tools.
void executorActionsTests() {
  group('GithubToolExecutor.execute (actions)', () {
    test('routes github_get_workflow_runs', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client)
          .execute('github_get_workflow_runs', _repoArgs);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/runs'),
      );
    });

    test('routes github_rerun_workflow with a coerced run_id', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_rerun_workflow',
        {..._repoArgs, 'run_id': '99'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/runs/99/rerun'),
      );
    });

    test('routes github_get_check_runs with ref', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_get_check_runs',
        {..._repoArgs, 'ref': 'main'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/commits/main/check-runs'),
      );
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves canned bodies by path, `''` for the rerun endpoint.
String _router(RequestOptions o) {
  if (o.path.endsWith('/rerun')) return '';
  if (o.path.endsWith('/actions/runs')) return _runsBody;
  if (o.path.endsWith('/check-runs')) return _checkRunsBody;
  return _runsBody;
}

/// Canned workflow-runs body.
const _runsBody = '{"total_count":1,"workflow_runs":[{"id":99}]}';

/// Canned check-runs body.
const _checkRunsBody = '{"total_count":1,"check_runs":[{"id":1}]}';
