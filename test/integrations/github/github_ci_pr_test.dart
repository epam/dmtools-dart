import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// The Java `GitHub.java` tools the catalog was missing (dm.ai #543 review
/// surface): check runs, commit statuses, repository dispatch, PR comment
/// management, PR activities, filtered PR listing, release assets, and
/// regex commit collection across branches.
void main() {
  tearDown(PropertyReader.clearOverrides);
  checkRunTests();
  commitStatusTests();
  prCommentManagementTests();
  prActivitiesTests();
  listPrsFilteredTests();
  workflowRunTests();
  repositoryDispatchTests();
  releaseAssetTests();
  commitsFromBranchesTests();
  ciExecutorTests();
  ciCatalogTests();
}

/// `github_create_check_run` — POST `repos/{w}/{r}/check-runs`.
void checkRunTests() {
  group('GithubClient.createCheckRun', () {
    test('POSTs name + head_sha only when optional fields are absent',
        () async {
      final f = mockGithub((o) => routeByPath({'/check-runs': _runBody}, o));
      await f.client.createCheckRun('epm', 'dm.ai', 'dmtools / review',
          'abc123');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/check-runs'));
      expect(jsonDecode(call.data as String), {
        'name': 'dmtools / review',
        'head_sha': 'abc123',
      });
    });

    test('defaults the output title to the name and summary to empty',
        () async {
      final f = mockGithub((o) => routeByPath({'/check-runs': _runBody}, o));
      await f.client.createCheckRun('epm', 'dm.ai', 'review', 'abc123',
          status: 'in_progress', summary: 'started', externalId: 'KEY-1');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'name': 'review',
        'head_sha': 'abc123',
        'status': 'in_progress',
        'external_id': 'KEY-1',
        'output': {'title': 'review', 'summary': 'started'},
      });
    });

    test('includes output text only when non-blank', () async {
      final f = mockGithub((o) => routeByPath({'/check-runs': _runBody}, o));
      await f.client.createCheckRun('epm', 'dm.ai', 'review', 'abc123',
          title: 'AI Review', text: '  ');
      final body = jsonDecode(f.adapter.calls.single.data as String)
          as Map<String, dynamic>;
      expect(body['output'], {'title': 'AI Review', 'summary': ''});
    });

    test('updateCheckRun PATCHes status/conclusion/output', () async {
      final f =
          mockGithub((o) => routeByPath({'/check-runs/9': _runBody}, o));
      await f.client.updateCheckRun('epm', 'dm.ai', '9', 'completed',
          conclusion: 'success', title: 'done', summary: 'ok', text: 'all');
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/check-runs/9'));
      expect(jsonDecode(call.data as String), {
        'status': 'completed',
        'conclusion': 'success',
        'output': {'title': 'done', 'summary': 'ok', 'text': 'all'},
      });
    });

    test('updateCheckRun omits a blank conclusion', () async {
      final f =
          mockGithub((o) => routeByPath({'/check-runs/9': _runBody}, o));
      await f.client.updateCheckRun('epm', 'dm.ai', '9', 'in_progress');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'status': 'in_progress',
      });
    });
  });
}

/// `github_create_commit_status` — POST `repos/{w}/{r}/statuses/{sha}`.
void commitStatusTests() {
  group('GithubClient.createCommitStatus', () {
    test('POSTs state plus optional fields', () async {
      final f = mockGithub((o) => routeByPath({'/statuses': '{}'}, o));
      await f.client.createCommitStatus('epm', 'dm.ai', 'abc123', 'pending',
          description: 'working', context: 'dmtools/pr', targetUrl: 'u');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/statuses/abc123'));
      expect(jsonDecode(call.data as String), {
        'state': 'pending',
        'description': 'working',
        'context': 'dmtools/pr',
        'target_url': 'u',
      });
    });

    test('omits blank optional fields', () async {
      final f = mockGithub((o) => routeByPath({'/statuses': '{}'}, o));
      await f.client.createCommitStatus('epm', 'dm.ai', 'abc123', 'success');
      expect(
          jsonDecode(f.adapter.calls.single.data as String), {'state': 'success'});
    });
  });
}

/// `github_update_pr_comment` / `github_delete_pr_comment`.
void prCommentManagementTests() {
  group('PR comment management', () {
    test('update PATCHes issues/comments/{id} with the new body', () async {
      final f =
          mockGithub((o) => routeByPath({'/issues/comments/5': '{}'}, o));
      await f.client
          .updatePullRequestComment('epm', 'dm.ai', '5', '✅ done');
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/comments/5'));
      expect(jsonDecode(call.data as String), {'body': '✅ done'});
    });

    test('delete DELETEs issues/comments/{id}', () async {
      final f =
          mockGithub((o) => routeByPath({'/issues/comments/5': ''}, o));
      await f.client.deletePullRequestComment('epm', 'dm.ai', '5');
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/comments/5'));
    });
  });
}

/// `github_get_pr_activities` — reviews + wrapped inline + issue comments.
void prActivitiesTests() {
  group('GithubClient.pullRequestActivities', () {
    test('aggregates reviews, inline comments, and discussion comments',
        () async {
      var reviewPage = 0;
      var inlinePage = 0;
      var issuePage = 0;
      final f = mockGithub((o) {
        if (o.path.endsWith('/pulls/74/reviews')) {
          return reviewPage++ == 0 ? _reviewsPage1 : '[]';
        }
        if (o.path.endsWith('/pulls/74/comments')) {
          return inlinePage++ == 0 ? _inlinePage : '[]';
        }
        if (o.path.endsWith('/issues/74/comments')) {
          return issuePage++ == 0 ? _discussionPage : '[]';
        }
        return '{}';
      });
      final activities =
          await f.client.pullRequestActivities('epm', 'dm.ai', '74');
      expect(activities, hasLength(4));
      // Reviews first, raw JSON.
      expect(activities[0]['state'], 'APPROVED');
      expect(activities[1]['state'], 'CHANGES_REQUESTED');
      // Comments wrapped as COMMENTED activities.
      expect(activities[2]['action'], 'COMMENTED');
      expect(activities[2]['comment']['body'], 'inline note');
      expect(activities[3]['comment']['body'], 'discussion');
      expect(reviewPage, 1, reason: 'a short page stops the pagination');
    });
  });
}

/// `github_list_prs_filtered` — state normalization + regex filtering.
void listPrsFilteredTests() {
  group('GithubClient.listPullRequestsFiltered', () {
    test('filters by title regex and normalizes opened→open', () async {
      final f = mockGithub(
        (o) => routeByPath({'/pulls': _prsPage}, o),
      );
      final result = await f.client
          .listPullRequestsFiltered('epm', 'dm.ai', 'opened', '^feat');
      expect(result.map((pr) => pr['number']), [1]);
      final call = f.adapter.calls.single;
      expect(call.queryParameters['state'], 'open');
    });

    test('merged keeps only PRs with merged_at', () async {
      final f = mockGithub(
        (o) => routeByPath({'/pulls': _prsPage}, o),
      );
      final result =
          await f.client.listPullRequestsFiltered('epm', 'dm.ai', 'merged', '.');
      expect(result.map((pr) => pr['number']), [2]);
    });

    test('matches a PR with a null title as the empty string', () async {
      final f = mockGithub(
        (o) => routeByPath({'/pulls': '[{"number":3,"title":null}]'}, o),
      );
      final result =
          await f.client.listPullRequestsFiltered('epm', 'dm.ai', 'open', '.*');
      expect(result, hasLength(1));
    });
  });
}

/// `github_get_workflow_run` — GET `actions/runs/{id}`.
void workflowRunTests() {
  group('GithubClient.getWorkflowRun', () {
    test('GETs the run by id', () async {
      final f = mockGithub(
        (o) => routeByPath({'/actions/runs/42': '{"id":42}'}, o),
      );
      final run = await f.client.getWorkflowRun('epm', 'dm.ai', '42');
      expect(run['id'], 42);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/runs/42'),
      );
    });
  });
}

/// `github_repository_dispatch` — POST `repos/{w}/{r}/dispatches`.
void repositoryDispatchTests() {
  group('GithubClient.repositoryDispatch', () {
    test('POSTs event_type and parsed client_payload', () async {
      final f = mockGithub((o) => routeByPath({'/dispatches': ''}, o));
      await f.client.repositoryDispatch(
        'epm',
        'dm.ai',
        'rework',
        '{"key":"value"}',
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/dispatches'));
      expect(jsonDecode(call.data as String), {
        'event_type': 'rework',
        'client_payload': {'key': 'value'},
      });
    });

    test('rejects an unparseable payload (Java eager JSON parse)', () async {
      final f = mockGithub((o) => routeByPath({'/dispatches': ''}, o));
      await expectLater(
        f.client.repositoryDispatch('epm', 'dm.ai', 'rework', '{oops'),
        throwsA(isA<FormatException>()),
      );
      expect(f.adapter.calls, isEmpty);
    });
  });
}

/// `github_list_release_assets` / `github_delete_release_asset`.
void releaseAssetTests() {
  group('release assets', () {
    test('list GETs releases/{id}/assets', () async {
      final f = mockGithub(
        (o) => routeByPath({'/releases/7/assets': _assetsBody}, o),
      );
      final assets = await f.client.listReleaseAssets('epm', 'dm.ai', '7');
      expect(assets.single['name'], 'app.apk');
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/releases/7/assets'),
      );
    });

    test('delete DELETEs releases/assets/{id}', () async {
      final f = mockGithub(
        (o) => routeByPath({'/releases/assets/9': ''}, o),
      );
      await f.client.deleteReleaseAsset('epm', 'dm.ai', '9');
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/repos/epm/dm.ai/releases/assets/9'));
    });
  });
}

/// `github_get_commits_from_branches` — regex branches + dedupe + since.
void commitsFromBranchesTests() {
  group('GithubClient.getCommitsFromBranches', () {
    test('aggregates matching branches and de-duplicates by SHA', () async {
      final f = mockGithub((o) {
        if (o.path.endsWith('/branches')) return _branchesBody;
        if (o.queryParameters['sha'] == 'feature/a') {
          return _commitsBranchA;
        }
        if (o.queryParameters['sha'] == 'feature/b') {
          return _commitsBranchB;
        }
        return '[]';
      });
      final commits = await f.client
          .getCommitsFromBranches('epm', 'dm.ai', '^feature/');
      // c1 appears on both branches; released on master is excluded.
      expect(commits.map((c) => c['sha']), ['c1', 'c2', 'c3']);
    });

    test('appends the since timestamp to the commit query', () async {
      final f = mockGithub((o) {
        if (o.path.endsWith('/branches')) return _branchesBody;
        expect(o.queryParameters['since'], '2024-01-01T00:00:00Z');
        return '[]';
      });
      await f.client
          .getCommitsFromBranches('epm', 'dm.ai', '^feature/', '2024-01-01');
    });
  });
}

/// Executor routing for the new CI/PR tools.
void ciExecutorTests() {
  group('GithubToolExecutor.execute (CI/PR tools)', () {
    test('routes github_create_check_run', () async {
      final f = mockGithub((o) => routeByPath({'/check-runs': _runBody}, o));
      await GithubToolExecutor(f.client).execute('github_create_check_run', {
        'workspace': 'epm',
        'repository': 'dm.ai',
        'name': 'review',
        'headSha': 'abc123',
        'status': 'queued',
      });
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'name': 'review',
        'head_sha': 'abc123',
        'status': 'queued',
      });
    });

    test('routes github_list_prs_filtered', () async {
      final f =
          mockGithub((o) => routeByPath({'/pulls': _prsPage}, o));
      final result = await GithubToolExecutor(f.client)
          .execute('github_list_prs_filtered', {
        'workspace': 'epm',
        'repository': 'dm.ai',
        'state': 'open',
        'titleRegex': '^feat',
      }) as List<dynamic>;
      expect(result.single['number'], 1);
    });

    test('routes github_repository_dispatch', () async {
      final f = mockGithub((o) => routeByPath({'/dispatches': ''}, o));
      await GithubToolExecutor(f.client).execute('github_repository_dispatch',
          {'workspace': 'epm', 'repository': 'dm.ai', 'eventType': 'rework'});
      expect(jsonDecode(f.adapter.calls.single.data as String),
          {'event_type': 'rework'});
    });

    test('routes github_get_commits_from_branches', () async {
      final f = mockGithub((o) {
        if (o.path.endsWith('/branches')) return _branchesBody;
        if (o.queryParameters['sha'] == 'feature/a') return _commitsBranchA;
        return '[]';
      });
      final result = await GithubToolExecutor(f.client)
          .execute('github_get_commits_from_branches', {
        'workspace': 'epm',
        'repository': 'dm.ai',
        'branchNameRegex': '^feature/',
      }) as List<dynamic>;
      expect(result.map((c) => c['sha']), ['c1', 'c2']);
    });
  });
}

/// Catalog metadata for the new tools.
void ciCatalogTests() {
  final registry = createDefaultToolRegistry();
  group('github CI/PR catalog', () {
    test('registers all eleven tools', () {
      for (final name in const [
        'github_create_check_run',
        'github_update_check_run',
        'github_create_commit_status',
        'github_get_workflow_run',
        'github_repository_dispatch',
        'github_update_pr_comment',
        'github_delete_pr_comment',
        'github_get_pr_activities',
        'github_list_prs_filtered',
        'github_list_release_assets',
        'github_delete_release_asset',
        'github_get_commits_from_branches',
      ]) {
        expect(registry.hasTool(name), isTrue, reason: name);
      }
    });

    test('github_get_pr_activities carries the source_code alias', () {
      expect(
        registry.resolveToolAlias(
          'source_code_get_pr_activities',
          defaultSourceCode: 'github',
        ),
        'github_get_pr_activities',
      );
    });
  });
}

/// An adapter variant would be needed for 404s; the RoutingAdapter always
/// answers 200, so the 404-tolerant inline-comment path is exercised in the
/// sync-layer fixture tests.

/// Canned check-run body.
const _runBody = '{"id":9,"status":"queued"}';

/// Canned assets body.
const _assetsBody = '[{"id":8,"name":"app.apk"}]';

/// Two review pages' worth of reviews (first page full).
const _reviewsPage1 =
    '[{"state":"APPROVED","body":"lgtm"},{"state":"CHANGES_REQUESTED","body":"fix"}]';

/// Inline review comments page.
const _inlinePage = '[{"id":5,"body":"inline note"}]';

/// Issue-level discussion comments page.
const _discussionPage = '[{"id":6,"body":"discussion"}]';

/// PR listing page: two PRs, one merged.
const _prsPage =
    '[{"number":1,"title":"feat: add x","merged_at":null},'
    '{"number":2,"title":"chore: y","merged_at":"2026-01-02T00:00:00Z"}]';

/// Branch listing: two feature branches + one non-matching.
const _branchesBody =
    '[{"name":"feature/a"},{"name":"feature/b"},{"name":"master"}]';

/// Branch A commits (c1, c2).
const _commitsBranchA =
    '[{"sha":"c1","message":"a1"},{"sha":"c2","message":"a2"}]';

/// Branch B commits (c1 again, c3).
const _commitsBranchB =
    '[{"sha":"c1","message":"a1"},{"sha":"c3","message":"b1"}]';
