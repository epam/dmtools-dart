import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Repository tests: the `git/repositories` client methods, tool-catalog
/// shape, and executor routing (create/list, branches, commits, details,
/// file contents).
void main() {
  tearDown(PropertyReader.clearOverrides);
  createRepoTests();
  getReposTests();
  getRepoBranchesTests();
  getCommitsTests();
  getRepoDetailsTests();
  getRepoFileTests();
  repositoryCatalogTests();
  repositoryExecutorTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned repository object.
const _repo = '{"id":5,"name":"my-repo"}';

/// Canned repository array.
const _repoArray = '[{"id":5,"name":"my-repo"}]';

/// Canned branch-stat array.
const _branchArray = '[{"name":"main"}]';

/// Canned commit array.
const _commitArray = '[{"commitId":"abc"}]';

/// Canned repository-details object.
const _repoObj =
    '{"id":"repo-1","name":"my-repo","defaultBranch":"refs/heads/main"}';

/// Canned raw file content.
const _fileContent = 'hello world';

/// `ado_create_repo` — POST `git/repositories`.
void createRepoTests() {
  group('AdoClient.createRepo', () {
    test('POSTs the repo name body and decodes the object', () async {
      final f = mockAdo((o) => routeByPath({'/repositories': _repo}, o));
      final result = await f.client.createRepo(_project, 'my-repo');
      expect(result['name'], 'my-repo');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/contoso/dmtools/_apis/git/repositories'));
      expect(jsonDecode(call.data as String), {'name': 'my-repo'});
    });
  });
}

/// `ado_get_repos` — GET `git/repositories`.
void getReposTests() {
  group('AdoClient.getRepos', () {
    test('GETs repositories and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/repositories': _repoArray}, o));
      final repos = await f.client.getRepos(_project);
      expect(repos.map((r) => r['name']).toList(), ['my-repo']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/dmtools/_apis/git/repositories'));
    });
  });
}

/// `ado_get_repo_branches` — GET `git/repositories/{repoId}/stats/branches`.
void getRepoBranchesTests() {
  group('AdoClient.getRepoBranches', () {
    test('GETs branch stats and decodes the list', () async {
      final f = mockAdo(
        (o) => routeByPath({'/stats/branches': _branchArray}, o),
      );
      final branches = await f.client.getRepoBranches(_project, 'repo-1');
      expect(branches.single['name'], 'main');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith(
            '/contoso/dmtools/_apis/git/repositories/repo-1/stats/branches'),
      );
    });
  });
}

/// `ado_get_commits` — POST commitsbatch with criteria, else GET commits.
void getCommitsTests() {
  group('AdoClient.getCommits', () {
    test('GETs commits when no search criteria are given', () async {
      final f = mockAdo((o) => routeByPath({'/commits': _commitArray}, o));
      final commits = await f.client.getCommits(_project, 'repo-1');
      expect(commits.single['commitId'], 'abc');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/repositories/repo-1/commits'),
      );
    });

    test('POSTs commitsbatch with the criteria as the body', () async {
      final f = mockAdo((o) => routeByPath({'/commitsbatch': _commitArray}, o));
      await f.client.getCommits(
        _project,
        'repo-1',
        <String, dynamic>{'fromDate': '2024-01-01'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith(
          '/contoso/dmtools/_apis/git/repositories/repo-1/commitsbatch',
        ),
      );
      expect(jsonDecode(call.data as String), {'fromDate': '2024-01-01'});
    });
  });
}

/// `ado_get_repo_details` — GET `git/repositories/{repoId}`.
void getRepoDetailsTests() {
  group('AdoClient.getRepoDetails', () {
    test('GETs the repository object project-scoped', () async {
      final f = mockAdo(
        (o) => routeByPath({'/repositories/repo-1': _repoObj}, o),
      );
      final result = await f.client.getRepoDetails(_project, 'repo-1');
      expect(result['name'], 'my-repo');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path,
          endsWith('/contoso/dmtools/_apis/git/repositories/repo-1'));
    });
  });
}

/// `ado_get_repo_file` — GET `git/repositories/{repoId}/items?path=&versionDescriptor`.
void getRepoFileTests() {
  group('AdoClient.getRepoFile', () {
    test('GETs the raw file content on the given branch', () async {
      final f = mockAdo((o) => routeByPath({'/items': _fileContent}, o));
      final content = await f.client.getRepoFile(
        _project,
        'repo-1',
        '/src/main.dart',
        'main',
      );
      expect(content, _fileContent);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/git/repositories/repo-1/items'));
      expect(call.queryParameters['path'], '/src/main.dart');
      expect(call.queryParameters['versionDescriptor.version'], 'main');
      expect(call.queryParameters['versionDescriptor.versionType'], 'branch');
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the repository tools.
void repositoryCatalogTests() {
  group('adoTools catalog (repositories)', () {
    test('registers all six repository tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_create_repo',
        'ado_get_repos',
        'ado_get_repo_branches',
        'ado_get_commits',
        'ado_get_repo_details',
        'ado_get_repo_file',
      ]) {
        expect(names, contains(name));
      }
    });

    test('ado_get_commits makes searchCriteria an optional object', () {
      final tool = toolNamed('ado_get_commits');
      expect(
        tool.params.map((p) => p.name),
        ['project', 'repoId', 'searchCriteria'],
      );
      final criteria = tool.params.last;
      expect(criteria.type, 'object');
      expect(criteria.required, isFalse);
    });

    test('ado_get_repo_details declares project and repoId', () {
      final tool = toolNamed('ado_get_repo_details');
      expect(tool.params.map((p) => p.name), ['project', 'repoId']);
    });

    test('ado_get_repo_file declares four params', () {
      final tool = toolNamed('ado_get_repo_file');
      expect(
        tool.params.map((p) => p.name),
        ['project', 'repoId', 'path', 'branch'],
      );
    });
  });
}

/// Serves method-aware bodies for the bare repositories endpoint
/// (POST creates one repo, GET lists them); deeper paths route by suffix,
/// with repository details (GET `repositories/{repoId}`) as the fallback.
String _repositoryRouter(RequestOptions o) {
  if (o.path.endsWith('/repositories')) {
    return o.method == 'POST' ? _repo : _repoArray;
  }
  return routeByPath({
    '/stats/branches': _branchArray,
    '/commitsbatch': _commitArray,
    '/commits': _commitArray,
    '/items': _fileContent,
  }, o, fallback: _repoObj);
}

/// [AdoToolExecutor.execute] routing for the repository tools.
void repositoryExecutorTests() {
  late _RepositoryFixture f;

  group('AdoToolExecutor.execute (repositories)', () {
    setUp(() => f = _repositoryFixture());

    test('routes ado_create_repo with project and name', () async {
      await f.executor
          .execute('ado_create_repo', {'project': 'p', 'name': 'r'});
      expect(f.spy.calls.single, 'createRepo:p:r');
    });

    test('routes ado_get_repos with the project', () async {
      await f.executor.execute('ado_get_repos', {'project': 'p'});
      expect(f.spy.calls.single, 'getRepos:p');
    });

    test('routes ado_get_repo_branches with project and repoId', () async {
      await f.executor.execute(
        'ado_get_repo_branches',
        {'project': 'p', 'repoId': 'r'},
      );
      expect(f.spy.calls.single, 'getRepoBranches:p:r');
    });

    test('routes ado_get_commits without searchCriteria', () async {
      await f.executor
          .execute('ado_get_commits', {'project': 'p', 'repoId': 'r'});
      expect(f.spy.calls.single, 'getCommits:p:r:null');
    });

    test('routes ado_get_commits with searchCriteria map', () async {
      await f.executor.execute('ado_get_commits', {
        'project': 'p',
        'repoId': 'r',
        'searchCriteria': <String, dynamic>{'fromDate': '2024-01-01'},
      });
      expect(f.spy.calls.single, 'getCommits:p:r:{fromDate: 2024-01-01}');
    });

    test('routes ado_get_repo_details with project and repoId', () async {
      await f.executor.execute(
        'ado_get_repo_details',
        {'project': 'p', 'repoId': 'repo-1'},
      );
      expect(f.spy.calls.single, 'getRepoDetails:p:repo-1');
    });

    test('routes ado_get_repo_file with four params', () async {
      await f.executor.execute('ado_get_repo_file', {
        'project': 'p',
        'repoId': 'repo-1',
        'path': '/a.txt',
        'branch': 'main',
      });
      expect(f.spy.calls.single, 'getRepoFile:p:repo-1:/a.txt:main');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _RepositoryFixture = ({AdoToolExecutor executor, _RepositorySpy spy});

/// Builds a [_RepositorySpy] over the mocked transport and wraps it.
_RepositoryFixture _repositoryFixture() {
  final spy = _RepositorySpy(mockAdoHttp(_repositoryRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched repository call then delegates to the real
/// client.
class _RepositorySpy extends AdoClient {
  _RepositorySpy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> createRepo(String project, String name) {
    calls.add('createRepo:$project:$name');
    return super.createRepo(project, name);
  }

  @override
  Future<List<Map<String, dynamic>>> getRepos(String project) {
    calls.add('getRepos:$project');
    return super.getRepos(project);
  }

  @override
  Future<List<Map<String, dynamic>>> getRepoBranches(
    String project,
    String repoId,
  ) {
    calls.add('getRepoBranches:$project:$repoId');
    return super.getRepoBranches(project, repoId);
  }

  @override
  Future<List<Map<String, dynamic>>> getCommits(
    String project,
    String repoId, [
    Map<String, dynamic>? searchCriteria,
  ]) {
    calls.add('getCommits:$project:$repoId:$searchCriteria');
    return super.getCommits(project, repoId, searchCriteria);
  }

  @override
  Future<Map<String, dynamic>> getRepoDetails(String project, String repoId) {
    calls.add('getRepoDetails:$project:$repoId');
    return super.getRepoDetails(project, repoId);
  }

  @override
  Future<String> getRepoFile(
    String project,
    String repoId,
    String path,
    String branch,
  ) {
    calls.add('getRepoFile:$project:$repoId:$path:$branch');
    return super.getRepoFile(project, repoId, path, branch);
  }
}
