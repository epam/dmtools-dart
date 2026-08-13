import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Batch 4: repository lookup, PR update, reviewer requests, review dismissal,
/// GitHub Actions, check runs, and git tree — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getRepoTests();
  updatePullRequestTests();
  requestReviewersTests();
  dismissReviewTests();
  getWorkflowRunsTests();
  reRunWorkflowTests();
  getCheckRunsTests();
  getTreeTests();
  executorBatch4RepoTests();
  executorBatch4ReviewTests();
  executorBatch4ActionsTests();
}

/// `github_get_repo` — GET `/repos/{owner}/{repo}`.
void getRepoTests() {
  group('GithubClient.getRepo', () {
    test('GETs the repository', () async {
      final f =
          mockGithub((o) => routeByPath({'/repos/epm/dm.ai': _repoBody}, o));
      final repo = await f.client.getRepo('epm', 'dm.ai');
      expect(repo['name'], 'dm.ai');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai'));
      expect(call.queryParameters, isEmpty);
    });
  });
}

/// `github_update_pr` — PATCH `/repos/{owner}/{repo}/pulls/{number}`.
void updatePullRequestTests() {
  group('GithubClient.updatePullRequest', () {
    test('PATCHes title and body when both are given', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.updatePullRequest('epm', 'dm.ai', 42, 'New', 'Desc');
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
      expect(jsonDecode(call.data as String), {
        'title': 'New',
        'body': 'Desc',
      });
    });

    test('sends only the title when the body is omitted', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.updatePullRequest('epm', 'dm.ai', 42, 'New');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'title': 'New',
      });
    });

    test('sends only the body when the title is omitted', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.updatePullRequest('epm', 'dm.ai', 42, null, 'Desc');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'body': 'Desc',
      });
    });
  });
}

/// `github_request_reviewers` — POST
/// `/repos/{owner}/{repo}/pulls/{number}/requested_reviewers`.
void requestReviewersTests() {
  group('GithubClient.requestReviewers', () {
    test('POSTs the reviewer set', () async {
      final f = mockGithub(
        (o) => routeByPath({'/requested_reviewers': _prBody}, o),
      );
      await f.client.requestReviewers('epm', 'dm.ai', 42, ['alice', 'bob']);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/requested_reviewers'),
      );
      expect(jsonDecode(call.data as String), {
        'reviewers': ['alice', 'bob'],
      });
    });
  });
}

/// `github_dismiss_review` — PUT
/// `/repos/{owner}/{repo}/pulls/{number}/reviews/{reviewId}/dismissals`.
void dismissReviewTests() {
  group('GithubClient.dismissReview', () {
    test('PUTs the dismissal message', () async {
      final f = mockGithub(
        (o) => routeByPath({'/dismissals': _reviewBody}, o),
      );
      await f.client.dismissReview('epm', 'dm.ai', 42, 9, 'Stale');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/reviews/9/dismissals'),
      );
      expect(jsonDecode(call.data as String), {'message': 'Stale'});
    });
  });
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

/// `github_get_tree` — GET `/repos/{owner}/{repo}/git/trees/{ref}?recursive=1`.
void getTreeTests() {
  group('GithubClient.getTree', () {
    test('GETs the recursive tree', () async {
      final f = mockGithub(
        (o) => routeByPath({'/git/trees/main': _treeBody}, o),
      );
      final tree = await f.client.getTree('epm', 'dm.ai', 'main');
      expect(tree['truncated'], false);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/git/trees/main'));
      expect(call.queryParameters['recursive'], '1');
    });
  });
}

/// Executor routing for the batch-4 repository and PR-update tools.
void executorBatch4RepoTests() {
  group('GithubToolExecutor.execute (batch 4: repo and PR update)', () {
    test('routes github_get_repo', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client).execute('github_get_repo', _repoArgs);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai'),
      );
    });

    test('routes github_update_pr with title and body', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client).execute(
        'github_update_pr',
        {..._prArgs(42), 'title': 'New', 'body': 'Desc'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
      expect(jsonDecode(call.data as String), {
        'title': 'New',
        'body': 'Desc',
      });
    });

    test('routes github_update_pr without optional fields', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client)
          .execute('github_update_pr', _prArgs(42));
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        isEmpty,
      );
    });
  });
}

/// Executor routing for the batch-4 reviewer and review-dismissal tools.
void executorBatch4ReviewTests() {
  group('GithubToolExecutor.execute (batch 4: reviews)', () {
    test('routes github_request_reviewers with a cast list', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client).execute(
        'github_request_reviewers',
        {
          ..._prArgs(42),
          'reviewers': ['alice'],
        },
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/requested_reviewers'),
      );
    });

    test('routes github_dismiss_review with a coerced review_id', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client).execute(
        'github_dismiss_review',
        {..._prArgs(42), 'review_id': '9', 'message': 'Stale'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/reviews/9/dismissals'),
      );
      expect(jsonDecode(call.data as String), {'message': 'Stale'});
    });
  });
}

/// Executor routing for the batch-4 Actions and git-tree tools.
void executorBatch4ActionsTests() {
  group('GithubToolExecutor.execute (batch 4: actions and tree)', () {
    test('routes github_get_workflow_runs', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client)
          .execute('github_get_workflow_runs', _repoArgs);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/runs'),
      );
    });

    test('routes github_rerun_workflow with a coerced run_id', () async {
      final f = mockGithub(_batch4Router);
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
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client).execute(
        'github_get_check_runs',
        {..._repoArgs, 'ref': 'main'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/commits/main/check-runs'),
      );
    });

    test('routes github_get_tree with ref and recursive query', () async {
      final f = mockGithub(_batch4Router);
      await GithubToolExecutor(f.client).execute(
        'github_get_tree',
        {..._repoArgs, 'ref': 'main'},
      );
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/repos/epm/dm.ai/git/trees/main'));
      expect(call.queryParameters['recursive'], '1');
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// PR tool arguments with a [number] value.
Map<String, dynamic> _prArgs(Object number) => {..._repoArgs, 'number': number};

/// Serves canned bodies by path/method, `''` for the rerun endpoint.
String _batch4Router(RequestOptions o) {
  if (o.path.endsWith('/dismissals')) return _reviewBody;
  if (o.path.endsWith('/requested_reviewers')) return _prBody;
  if (o.path.endsWith('/rerun')) return '';
  if (o.path.endsWith('/actions/runs')) return _runsBody;
  if (o.path.endsWith('/check-runs')) return _checkRunsBody;
  if (o.path.endsWith('/git/trees/main')) return _treeBody;
  if (o.method == 'PATCH') return _prBody;
  return _repoBody;
}

/// Canned repository body.
const _repoBody = '{"name":"dm.ai","full_name":"epm/dm.ai"}';

/// Canned pull-request body.
const _prBody = '{"number":42,"title":"PR"}';

/// Canned review body.
const _reviewBody = '{"id":9,"state":"DISMISSED"}';

/// Canned workflow-runs body.
const _runsBody = '{"total_count":1,"workflow_runs":[{"id":99}]}';

/// Canned check-runs body.
const _checkRunsBody = '{"total_count":1,"check_runs":[{"id":1}]}';

/// Canned git-tree body.
const _treeBody = '{"sha":"abc","truncated":false,"tree":[]}';
