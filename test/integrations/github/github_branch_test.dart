import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Branch management — list, create, and delete — [GithubClient] methods
/// plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  listBranchesTests();
  createBranchTests();
  deleteBranchTests();
  executorBranchTests();
}

/// `github_list_branches` — GET `/repos/{owner}/{repo}/branches`.
void listBranchesTests() {
  group('GithubClient.listBranches', () {
    test('GETs the branch list', () async {
      final f = mockGithub(
        (o) => routeByPath({'/branches': _branchListBody}, o),
      );
      final branches = await f.client.listBranches('epm', 'dm.ai');
      expect(branches.map((b) => b['name']).toList(), ['main', 'dev']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/branches'));
    });
  });
}

/// `github_create_branch` — POST `/repos/{owner}/{repo}/git/refs`.
void createBranchTests() {
  group('GithubClient.createBranch', () {
    test('POSTs a fully-qualified ref with the source SHA', () async {
      final f = mockGithub((o) => routeByPath({'/git/refs': _refBody}, o));
      final result =
          await f.client.createBranch('epm', 'dm.ai', 'feature', 'abc123');
      expect(result['ref'], 'refs/heads/feature');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/git/refs'));
      expect(jsonDecode(call.data as String), {
        'ref': 'refs/heads/feature',
        'sha': 'abc123',
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

/// Executor routing for the branch tools.
void executorBranchTests() {
  group('GithubToolExecutor.execute (branches)', () {
    test('routes github_list_branches', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client)
          .execute('github_list_branches', _repoArgs);
      expect(
          f.adapter.calls.single.path, endsWith('/repos/epm/dm.ai/branches'));
    });

    test('routes github_create_branch with from_sha', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute('github_create_branch', {
        ..._repoArgs,
        'branch': 'feature',
        'from_sha': 'abc123',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/git/refs'));
      expect(
        jsonDecode(call.data as String),
        {'ref': 'refs/heads/feature', 'sha': 'abc123'},
      );
    });

    test('routes github_delete_branch', () async {
      final f = mockGithub(_router);
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
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves `[]` for the branch list, `''` for deletes, `{}` otherwise.
String _router(RequestOptions o) {
  if (o.path.endsWith('/branches')) return '[]';
  if (o.method == 'DELETE') return '';
  return '{}';
}

/// Canned branch list body.
const _branchListBody = '[{"name":"main"},{"name":"dev"}]';

/// Canned git-ref response body.
const _refBody = '{"ref":"refs/heads/feature"}';
