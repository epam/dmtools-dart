import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Batch 3: releases, commit lookup, issue mutations, and label management —
/// [GithubClient] methods plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  listReleasesTests();
  getReleaseTests();
  createReleaseTests();
  deleteBranchTests();
  getCommitTests();
  listCommitsTests();
  createIssueTests();
  closeIssueTests();
  addLabelsTests();
  removeLabelTests();
  executorReleaseTests();
  executorBranchCommitTests();
  executorIssueTests();
}

/// `github_list_releases` — GET `/repos/{owner}/{repo}/releases`.
void listReleasesTests() {
  group('GithubClient.listReleases', () {
    test('GETs the release list', () async {
      final f = mockGithub(
        (o) => routeByPath({'/releases': _releaseListBody}, o),
      );
      final releases = await f.client.listReleases('epm', 'dm.ai');
      expect(releases.map((r) => r['tag_name']).toList(), ['v1.0.0', 'v0.9.0']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/releases'));
    });
  });
}

/// `github_get_release` — GET `/repos/{owner}/{repo}/releases/tags/{tag}`.
void getReleaseTests() {
  group('GithubClient.getRelease', () {
    test('GETs the release by tag', () async {
      final f = mockGithub(
        (o) => routeByPath({'/tags/v1.0.0': _releaseBody}, o),
      );
      final release = await f.client.getRelease('epm', 'dm.ai', 'v1.0.0');
      expect(release['tag_name'], 'v1.0.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/releases/tags/v1.0.0'),
      );
    });
  });
}

/// `github_create_release` — POST `/repos/{owner}/{repo}/releases`.
void createReleaseTests() {
  group('GithubClient.createRelease', () {
    test('POSTs tag_name only when no body is given', () async {
      final f = mockGithub((o) => routeByPath({'/releases': _releaseBody}, o));
      final result = await f.client.createRelease('epm', 'dm.ai', 'v1.0.0');
      expect(result['tag_name'], 'v1.0.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/releases'));
      expect(jsonDecode(call.data as String), {'tag_name': 'v1.0.0'});
    });

    test('includes the description body when provided', () async {
      final f = mockGithub((o) => routeByPath({'/releases': _releaseBody}, o));
      await f.client.createRelease('epm', 'dm.ai', 'v1.0.0', 'Ship it');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'tag_name': 'v1.0.0',
        'body': 'Ship it',
      });
    });
  });
}

/// `github_delete_branch` — DELETE `/repos/{owner}/{repo}/git/refs/heads/{b}`.
void deleteBranchTests() {
  group('GithubClient.deleteBranch', () {
    test('DELETEs the ref and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/heads/feature': ''}, o));
      expect(await f.client.deleteBranch('epm', 'dm.ai', 'feature'), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/git/refs/heads/feature'),
      );
    });

    test('decodes a non-empty response body', () async {
      final f = mockGithub(
        (o) => routeByPath({'/heads/feature': _refBody}, o),
      );
      expect(await f.client.deleteBranch('epm', 'dm.ai', 'feature'),
          jsonDecode(_refBody));
    });
  });
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

/// `github_create_issue` — POST `/repos/{owner}/{repo}/issues`.
void createIssueTests() {
  group('GithubClient.createIssue', () {
    test('POSTs title only when no body is given', () async {
      final f = mockGithub((o) => routeByPath({'/issues': _issueBody}, o));
      final result = await f.client.createIssue('epm', 'dm.ai', 'Bug');
      expect(result['number'], 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues'));
      expect(jsonDecode(call.data as String), {'title': 'Bug'});
    });

    test('includes the description body when provided', () async {
      final f = mockGithub((o) => routeByPath({'/issues': _issueBody}, o));
      await f.client.createIssue('epm', 'dm.ai', 'Bug', 'Steps to repro');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'title': 'Bug',
        'body': 'Steps to repro',
      });
    });
  });
}

/// `github_close_issue` — PATCH `/repos/{owner}/{repo}/issues/{number}`.
void closeIssueTests() {
  group('GithubClient.closeIssue', () {
    test('PATCHes state closed', () async {
      final f = mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
      await f.client.closeIssue('epm', 'dm.ai', 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7'));
      expect(jsonDecode(call.data as String), {'state': 'closed'});
    });
  });
}

/// `github_add_labels` — POST `/repos/{owner}/{repo}/issues/{number}/labels`.
void addLabelsTests() {
  group('GithubClient.addLabels', () {
    test('POSTs the label set', () async {
      final f = mockGithub(
        (o) => routeByPath({'/labels': _labelListBody}, o),
      );
      final result = await f.client.addLabels(
        'epm',
        'dm.ai',
        7,
        ['bug', 'p2'],
      );
      expect(result.map((l) => l['name']).toList(), ['bug', 'p2']);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels'));
      expect(jsonDecode(call.data as String), {
        'labels': ['bug', 'p2']
      });
    });
  });
}

/// `github_remove_label` — DELETE
/// `/repos/{owner}/{repo}/issues/{number}/labels/{label}`.
void removeLabelTests() {
  group('GithubClient.removeLabel', () {
    test('DELETEs the label and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/labels/bug': ''}, o));
      expect(await f.client.removeLabel('epm', 'dm.ai', 7, 'bug'), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels/bug'));
    });

    test('decodes a non-empty response body', () async {
      final f = mockGithub(
        (o) => routeByPath({'/labels/bug': _labelBody}, o),
      );
      expect(await f.client.removeLabel('epm', 'dm.ai', 7, 'bug'),
          jsonDecode(_labelBody));
    });
  });
}

/// Executor routing for the release tools.
void executorReleaseTests() {
  group('GithubToolExecutor.execute (releases)', () {
    test('routes github_list_releases', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client)
          .execute('github_list_releases', _repoArgs);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/releases'),
      );
    });

    test('routes github_get_release with tag', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute(
        'github_get_release',
        {..._repoArgs, 'tag': 'v1.0.0'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/releases/tags/v1.0.0'),
      );
    });

    test('routes github_create_release with tag_name and body', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute('github_create_release', {
        ..._repoArgs,
        'tag_name': 'v1.0.0',
        'body': 'Ship it',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {
        'tag_name': 'v1.0.0',
        'body': 'Ship it',
      });
    });
  });
}

/// Executor routing for the branch-delete and commit tools.
void executorBranchCommitTests() {
  group('GithubToolExecutor.execute (branch and commits)', () {
    test('routes github_delete_branch', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute(
        'github_delete_branch',
        {..._repoArgs, 'branch': 'feature'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/git/refs/heads/feature'),
      );
    });

    test('routes github_get_commit with sha', () async {
      final f = mockGithub(_batch3Router);
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
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute(
        'github_list_commits',
        {..._repoArgs, 'sha': 'dev'},
      );
      expect(f.adapter.calls.single.queryParameters['sha'], 'dev');
    });
  });
}

/// Executor routing for the issue mutation and label tools.
void executorIssueTests() {
  group('GithubToolExecutor.execute (issues and labels)', () {
    test('routes github_create_issue', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute(
        'github_create_issue',
        {..._repoArgs, 'title': 'Bug'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {'title': 'Bug'});
    });

    test('routes github_close_issue with a coerced number', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client)
          .execute('github_close_issue', _issueArgs('7'));
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7'));
      expect(jsonDecode(call.data as String), {'state': 'closed'});
    });

    test('routes github_add_labels with a cast label list', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute('github_add_labels', {
        ..._issueArgs(7),
        'labels': ['bug', 'p2'],
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {
        'labels': ['bug', 'p2']
      });
    });

    test('routes github_remove_label with a coerced number', () async {
      final f = mockGithub(_batch3Router);
      await GithubToolExecutor(f.client).execute(
        'github_remove_label',
        {..._issueArgs('7'), 'label': 'bug'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels/bug'));
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Issue tool arguments with a [number] value.
Map<String, dynamic> _issueArgs(Object number) =>
    {..._repoArgs, 'number': number};

/// Serves `[]` for array endpoints, `''` for deletes, `{}` otherwise.
String _batch3Router(RequestOptions o) {
  // POST /issues/{n}/labels returns the resulting label array.
  if (o.path.endsWith('/labels')) return '[]';
  final listEndpoint =
      o.path.endsWith('/releases') || o.path.endsWith('/commits');
  if (o.method == 'GET' && listEndpoint) return '[]';
  if (o.method == 'DELETE') return '';
  return '{}';
}

/// Canned release-list body.
const _releaseListBody = '[{"tag_name":"v1.0.0"},{"tag_name":"v0.9.0"}]';

/// Canned release body.
const _releaseBody = '{"tag_name":"v1.0.0","name":"v1.0.0"}';

/// Canned git-ref body.
const _refBody = '{"ref":"refs/heads/feature"}';

/// Canned commit body.
const _commitBody = '{"sha":"abc123"}';

/// Canned commit-list body.
const _commitListBody = '[{"sha":"abc123"},{"sha":"def456"}]';

/// Canned issue body.
const _issueBody = '{"number":7,"title":"Bug"}';

/// Canned label-list body.
const _labelListBody = '[{"name":"bug"},{"name":"p2"}]';

/// Canned single-label body.
const _labelBody = '{"name":"bug"}';
