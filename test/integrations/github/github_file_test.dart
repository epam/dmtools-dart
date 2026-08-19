import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// File contents — read and update — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getFileContentTests();
  updateFileTests();
  executorFileContentTests();
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

/// Executor routing for the file-content tools.
void executorFileContentTests() {
  group('GithubToolExecutor.execute (file contents)', () {
    test('routes github_get_file_content with optional ref', () async {
      final f = mockGithub(_router);
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
      final f = mockGithub(_router);
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

/// Serves `{}` for every request; the file-content tests inspect requests,
/// not responses.
String _router(RequestOptions o) => '{}';

/// Canned file-content response body.
const _contentBody =
    '{"name":"README.md","content":"aGVsbG8=","encoding":"base64"}';
