import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Repository lookup and git-tree access — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getRepoTests();
  getTreeTests();
  executorRepositoryTests();
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

/// Executor routing for the repository and git-tree tools.
void executorRepositoryTests() {
  group('GithubToolExecutor.execute (repository)', () {
    test('routes github_get_repo', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute('github_get_repo', _repoArgs);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai'),
      );
    });

    test('routes github_get_tree with ref and recursive query', () async {
      final f = mockGithub(_router);
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

/// Serves the canned git-tree body for the tree endpoint, the repository
/// body otherwise.
String _router(RequestOptions o) {
  if (o.path.endsWith('/git/trees/main')) return _treeBody;
  return _repoBody;
}

/// Canned repository body.
const _repoBody = '{"name":"dm.ai","full_name":"epm/dm.ai"}';

/// Canned git-tree body.
const _treeBody = '{"sha":"abc","truncated":false,"tree":[]}';
