import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Commits — get by SHA and list — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getCommitTests();
  listCommitsTests();
  executorCommitTests();
}

/// `github_get_commit` — GET `/repos/{owner}/{repo}/commits/{sha}`.
void getCommitTests() {
  group('GithubClient.getCommit', () {
    test('GETs the commit by SHA', () async {
      final f = mockGithub(
        (o) => routeByPath({'/commits/abc123': _commitBody}, o),
      );
      final commit = await f.client.getCommit('epm', 'dm.ai', 'abc123');
      expect(commit['sha'], 'abc123');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/commits/abc123'));
    });
  });
}

/// `github_list_commits` — GET `/repos/{owner}/{repo}/commits`.
void listCommitsTests() {
  group('GithubClient.listCommits', () {
    test('GETs the commit list without a sha query', () async {
      final f =
          mockGithub((o) => routeByPath({'/commits': _commitListBody}, o));
      final commits = await f.client.listCommits('epm', 'dm.ai');
      expect(commits.map((c) => c['sha']).toList(), ['abc123', 'def456']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/commits'));
      expect(call.queryParameters, isEmpty);
    });

    test('forwards a sha query when provided', () async {
      final f =
          mockGithub((o) => routeByPath({'/commits': _commitListBody}, o));
      await f.client.listCommits('epm', 'dm.ai', 'dev');
      expect(f.adapter.calls.single.queryParameters['sha'], 'dev');
    });
  });
}

/// Executor routing for the commit tools.
void executorCommitTests() {
  group('GithubToolExecutor.execute (commits)', () {
    test('routes github_get_commit with sha', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_get_commit',
        {..._repoArgs, 'sha': 'abc123'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/commits/abc123'),
      );
    });

    test('routes github_list_commits with optional sha', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_list_commits',
        {..._repoArgs, 'sha': 'dev'},
      );
      expect(f.adapter.calls.single.queryParameters['sha'], 'dev');
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves `[]` for the commit-list endpoint and `{}` otherwise.
String _router(RequestOptions o) {
  if (o.method == 'GET' && o.path.endsWith('/commits')) return '[]';
  return '{}';
}

/// Canned commit body.
const _commitBody = '{"sha":"abc123"}';

/// Canned commit-list body.
const _commitListBody = '[{"sha":"abc123"},{"sha":"def456"}]';
