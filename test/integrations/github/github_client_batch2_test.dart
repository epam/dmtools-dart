import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Batch 2: PR merge/close/reopen, diff, files, reviews, branches, and file
/// contents — [GithubClient] methods plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  mergePrTests();
  prStateTests();
  prDiffTests();
  prFilesTests();
  createReviewTests();
  listBranchesTests();
  createBranchTests();
  getFileContentTests();
  updateFileTests();
  executorPrMutationTests();
  executorPrContentTests();
  executorRepoContentTests();
}

/// `github_merge_pr` — PUT `/repos/{owner}/{repo}/pulls/{number}/merge`.
void mergePrTests() {
  group('GithubClient.mergePr', () {
    test('PUTs the merge endpoint and decodes the result', () async {
      final f = mockGithub((o) => routeByPath({'/merge': _mergeBody}, o));
      final result = await f.client.mergePr('epm', 'dm.ai', 42);
      expect(result['merged'], isTrue);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42/merge'));
    });
  });
}

/// `github_close_pr` / `github_reopen_pr` — PATCH `/repos/.../pulls/{number}`.
void prStateTests() {
  group('GithubClient.closePr', () {
    test('PATCHes state closed', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.closePr('epm', 'dm.ai', 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
      expect(jsonDecode(call.data as String), {'state': 'closed'});
    });
  });

  group('GithubClient.reopenPr', () {
    test('PATCHes state open', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.reopenPr('epm', 'dm.ai', 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(jsonDecode(call.data as String), {'state': 'open'});
    });
  });
}

/// `github_get_pr_diff` — GET the PR with the diff media type.
void prDiffTests() {
  group('GithubClient.getPrDiff', () {
    test('GETs the PR requesting the diff media type', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _diffBody}, o));
      final diff = await f.client.getPrDiff('epm', 'dm.ai', 42);
      expect(diff, _diffBody);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
      expect(call.headers['Accept'], 'application/vnd.github.diff');
    });
  });
}

/// `github_get_pr_files` — GET `/repos/{owner}/{repo}/pulls/{number}/files`.
void prFilesTests() {
  group('GithubClient.getPrFiles', () {
    test('GETs the changed-file list', () async {
      final f = mockGithub((o) => routeByPath({'/files': _fileListBody}, o));
      final files = await f.client.getPrFiles('epm', 'dm.ai', 42);
      expect(files.map((e) => e['filename']).toList(), ['a.txt', 'b.txt']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42/files'));
    });
  });
}

/// `github_create_review` — POST `/repos/.../pulls/{number}/reviews`.
void createReviewTests() {
  group('GithubClient.createReview', () {
    test('POSTs body and event to the reviews endpoint', () async {
      final f = mockGithub((o) => routeByPath({'/reviews': _reviewBody}, o));
      final result = await f.client.createReview(
        'epm',
        'dm.ai',
        42,
        'looks good',
        'APPROVE',
      );
      expect(result['state'], 'APPROVED');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42/reviews'));
      expect(jsonDecode(call.data as String), {
        'body': 'looks good',
        'event': 'APPROVE',
      });
    });
  });
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

/// `github_get_file_content` — GET `/repos/{owner}/{repo}/contents/{path}`.
void getFileContentTests() {
  group('GithubClient.getFileContent', () {
    test('GETs the contents path without a ref query', () async {
      final f = mockGithub(
        (o) => routeByPath({'/contents/README.md': _contentBody}, o),
      );
      final file = await f.client.getFileContent('epm', 'dm.ai', 'README.md');
      expect(file['name'], 'README.md');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/contents/README.md'));
      expect(call.queryParameters, isEmpty);
    });

    test('forwards a ref query when provided', () async {
      final f = mockGithub(
        (o) => routeByPath({'/contents/README.md': _contentBody}, o),
      );
      await f.client.getFileContent('epm', 'dm.ai', 'README.md', 'dev');
      expect(f.adapter.calls.single.queryParameters['ref'], 'dev');
    });
  });
}

/// `github_update_file` — PUT `/repos/{owner}/{repo}/contents/{path}`.
void updateFileTests() {
  group('GithubClient.updateFile', () {
    test('PUTs message, base64 content, and sha', () async {
      final f = mockGithub(
        (o) => routeByPath({'/contents/README.md': _contentBody}, o),
      );
      final result = await f.client.updateFile(
        'epm',
        'dm.ai',
        'README.md',
        'hello',
        'Update readme',
        'sha-1',
      );
      expect(result['name'], 'README.md');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/repos/epm/dm.ai/contents/README.md'));
      expect(jsonDecode(call.data as String), {
        'message': 'Update readme',
        'content': base64Encode(utf8.encode('hello')),
        'sha': 'sha-1',
      });
    });
  });
}

/// Executor routing for merge/close/reopen tools.
void executorPrMutationTests() {
  group('GithubToolExecutor.execute (PR mutations)', () {
    for (final entry in const [
      ('github_merge_pr', 'PUT', '/pulls/42/merge'),
      ('github_close_pr', 'PATCH', '/pulls/42'),
      ('github_reopen_pr', 'PATCH', '/pulls/42'),
    ]) {
      test('routes ${entry.$1} with a coerced number', () async {
        final f = mockGithub(_batch2Router);
        await GithubToolExecutor(f.client).execute(entry.$1, _prArgs('42'));
        final call = f.adapter.calls.single;
        expect(call.method, entry.$2);
        expect(call.path, endsWith(entry.$3));
      });
    }

    test('github_close_pr sends state closed; reopen sends open', () async {
      final close = mockGithub(_batch2Router);
      await GithubToolExecutor(close.client)
          .execute('github_close_pr', _prArgs(42));
      expect(
        jsonDecode(close.adapter.calls.single.data as String),
        {'state': 'closed'},
      );

      final reopen = mockGithub(_batch2Router);
      await GithubToolExecutor(reopen.client)
          .execute('github_reopen_pr', _prArgs(42));
      expect(
        jsonDecode(reopen.adapter.calls.single.data as String),
        {'state': 'open'},
      );
    });
  });
}

/// Executor routing for diff/files/review tools.
void executorPrContentTests() {
  group('GithubToolExecutor.execute (PR content)', () {
    test('routes github_get_pr_diff with the diff media type', () async {
      final f = mockGithub(_batch2Router);
      final diff = await GithubToolExecutor(f.client)
          .execute('github_get_pr_diff', _prArgs(42));
      expect(diff, isA<String>());
      expect(
        f.adapter.calls.single.headers['Accept'],
        'application/vnd.github.diff',
      );
    });

    test('routes github_get_pr_files', () async {
      final f = mockGithub(_batch2Router);
      await GithubToolExecutor(f.client)
          .execute('github_get_pr_files', _prArgs(42));
      expect(f.adapter.calls.single.path, endsWith('/pulls/42/files'));
    });

    test('routes github_create_review with body and event', () async {
      final f = mockGithub(_batch2Router);
      await GithubToolExecutor(f.client).execute('github_create_review', {
        ..._prArgs(42),
        'body': 'ok',
        'event': 'APPROVE',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/pulls/42/reviews'));
      expect(
        jsonDecode(call.data as String),
        {'body': 'ok', 'event': 'APPROVE'},
      );
    });
  });
}

/// Executor routing for branch and file tools.
void executorRepoContentTests() {
  group('GithubToolExecutor.execute (branches and files)', () {
    test('routes github_list_branches', () async {
      final f = mockGithub(_batch2Router);
      await GithubToolExecutor(f.client)
          .execute('github_list_branches', _repoArgs);
      expect(
          f.adapter.calls.single.path, endsWith('/repos/epm/dm.ai/branches'));
    });

    test('routes github_create_branch with from_sha', () async {
      final f = mockGithub(_batch2Router);
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

    test('routes github_get_file_content with optional ref', () async {
      final f = mockGithub(_batch2Router);
      await GithubToolExecutor(f.client).execute(
        'github_get_file_content',
        {..._repoArgs, 'path': 'README.md', 'ref': 'dev'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/contents/README.md'));
      expect(call.queryParameters['ref'], 'dev');
    });

    test('routes github_update_file with base64-encoded content', () async {
      final f = mockGithub(_batch2Router);
      await GithubToolExecutor(f.client).execute('github_update_file', {
        ..._repoArgs,
        'path': 'README.md',
        'content': 'hello',
        'message': 'Update readme',
        'sha': 'sha-1',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(jsonDecode(call.data as String)['content'], 'aGVsbG8=');
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// PR tool arguments with a [number] value.
Map<String, dynamic> _prArgs(Object number) => {..._repoArgs, 'number': number};

/// Serves `[]` for list endpoints and `{}` otherwise.
String _batch2Router(RequestOptions o) {
  final listEndpoint =
      o.path.endsWith('/files') || o.path.endsWith('/branches');
  return listEndpoint && o.method == 'GET' ? '[]' : '{}';
}

/// Canned merge response body.
const _mergeBody = '{"merged":true}';

/// Canned pull-request response body.
const _prBody = '{"number":42,"title":"Fix bug"}';

/// Canned raw diff body.
const _diffBody = 'diff --git a/x b/x';

/// Canned changed-file list body.
const _fileListBody = '[{"filename":"a.txt"},{"filename":"b.txt"}]';

/// Canned review response body.
const _reviewBody = '{"id":5,"state":"APPROVED"}';

/// Canned branch list body.
const _branchListBody = '[{"name":"main"},{"name":"dev"}]';

/// Canned git-ref response body.
const _refBody = '{"ref":"refs/heads/feature"}';

/// Canned file-content response body.
const _contentBody =
    '{"name":"README.md","content":"aGVsbG8=","encoding":"base64"}';
