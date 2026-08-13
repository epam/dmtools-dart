import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Batch-5 tests: the four ADO client/tools added after batch 4
/// (getProjectDetails, getRepoDetails, getRepoFile, createWorkItemLink).
void main() {
  tearDown(PropertyReader.clearOverrides);
  getProjectDetailsTests();
  getRepoDetailsTests();
  getRepoFileTests();
  createWorkItemLinkTests();
  batch5CatalogTests();
  batch5ExecutorTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned project object.
const _projectObj = '{"id":"proj-1","name":"dmtools","state":"wellFormed"}';

/// Canned repository object.
const _repoObj =
    '{"id":"repo-1","name":"my-repo","defaultBranch":"refs/heads/main"}';

/// Canned raw file content.
const _fileContent = 'hello world';

/// Canned created link object.
const _link = '{"id":1,"rev":2}';

/// `ado_get_project_details` — GET `projects/{projectId}` (org-scoped).
void getProjectDetailsTests() {
  group('AdoClient.getProjectDetails', () {
    test('GETs the project object org-scoped', () async {
      final f =
          mockAdo((o) => routeByPath({'/projects/proj-1': _projectObj}, o));
      final result = await f.client.getProjectDetails('proj-1');
      expect(result['name'], 'dmtools');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/_apis/projects/proj-1'));
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

/// `ado_create_work_item_link` — POST `wit/workitems/{sourceId}/links`.
void createWorkItemLinkTests() {
  group('AdoClient.createWorkItemLink', () {
    test('POSTs a JSON-Patch relation add and decodes the object', () async {
      const linkType = 'System.LinkTypes.Hierarchy-Forward';
      final f = mockAdo((o) => o.method == 'POST' ? _link : '{}');
      final result = await f.client.createWorkItemLink(1, 2, linkType);
      expect(result['id'], 1);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.headers['Content-Type'], 'application/json-patch+json');
      expect(
          call.path, endsWith('/contoso/dmtools/_apis/wit/workitems/1/links'));
      final sent = jsonDecode(call.data as String) as List<dynamic>;
      expect(sent.single['op'], 'add');
      expect(sent.single['path'], '/relations/-');
      final value = sent.single['value'] as Map<String, dynamic>;
      expect(value['rel'], linkType);
      expect(value['url'], endsWith('/_apis/wit/workitems/2'));
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the batch-5 tools.
void batch5CatalogTests() {
  group('adoTools catalog (batch 5)', () {
    test('registers all four batch-5 tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_get_project_details',
        'ado_get_repo_details',
        'ado_get_repo_file',
        'ado_create_work_item_link',
      ]) {
        expect(names, contains(name));
      }
    });

    test('ado_get_project_details declares projectId', () {
      final tool = toolNamed('ado_get_project_details');
      expect(tool.params.single.name, 'projectId');
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

    test('ado_create_work_item_link declares numeric ids and linkType', () {
      final tool = toolNamed('ado_create_work_item_link');
      expect(
        tool.params.map((p) => p.name),
        ['sourceId', 'targetId', 'linkType'],
      );
      expect(tool.params[0].type, 'number');
      expect(tool.params[1].type, 'number');
    });
  });
}

/// Serves `{}` for every request — enough for the spy-backed executor paths.
String _batch5Router(RequestOptions o) => '{}';

/// [AdoToolExecutor.execute] routing for the batch-5 tools.
void batch5ExecutorTests() {
  late _Batch5Fixture f;

  group('AdoToolExecutor.execute (batch 5)', () {
    setUp(() => f = _batch5Fixture());

    test('routes ado_get_project_details with projectId', () async {
      await f.executor.execute(
        'ado_get_project_details',
        {'projectId': 'proj-1'},
      );
      expect(f.spy.calls.single, 'getProjectDetails:proj-1');
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

    test('routes ado_create_work_item_link with numeric ids', () async {
      await f.executor.execute('ado_create_work_item_link', {
        'sourceId': 1,
        'targetId': 2,
        'linkType': 'rel',
      });
      expect(f.spy.calls.single, 'createWorkItemLink:1:2:rel');
    });

    test('parses numeric-string ids on create_work_item_link', () async {
      await f.executor.execute('ado_create_work_item_link', {
        'sourceId': '1',
        'targetId': '2',
        'linkType': 'rel',
      });
      expect(f.spy.calls.single, 'createWorkItemLink:1:2:rel');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _Batch5Fixture = ({AdoToolExecutor executor, _Batch5Spy spy});

/// Builds a [_Batch5Spy] over the mocked transport and wraps it.
_Batch5Fixture _batch5Fixture() {
  final spy = _Batch5Spy(mockAdoHttp(_batch5Router).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched batch-5 call then delegates to the real client.
class _Batch5Spy extends AdoClient {
  _Batch5Spy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> getProjectDetails(String projectId) {
    calls.add('getProjectDetails:$projectId');
    return super.getProjectDetails(projectId);
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

  @override
  Future<Map<String, dynamic>> createWorkItemLink(
    int sourceId,
    int targetId,
    String linkType,
  ) {
    calls.add('createWorkItemLink:$sourceId:$targetId:$linkType');
    return super.createWorkItemLink(sourceId, targetId, linkType);
  }
}
