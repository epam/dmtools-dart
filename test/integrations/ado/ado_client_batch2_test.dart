import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Batch-2 tests: the eight ADO client/tools added after the initial set
/// (update/get/list work items, WIQL, repos, builds, work-item types).
void main() {
  tearDown(PropertyReader.clearOverrides);
  updateWorkItemTests();
  getWorkItemsTests();
  listWorkItemsTests();
  getWorkItemTypesTests();
  createRepoTests();
  getReposTests();
  getBuildsTests();
  triggerBuildTests();
  batch2CatalogTests();
  batch2ExecutorTests();
  batch2ExecutorRepoBuildTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned updated work item.
const _updatedItem = '{"id":42,"rev":3}';

/// Canned work-item array.
const _itemArray = '[{"id":1},{"id":2}]';

/// Canned repository object.
const _repo = '{"id":5,"name":"my-repo"}';

/// Canned repository array.
const _repoArray = '[{"id":5,"name":"my-repo"}]';

/// Canned build array.
const _buildArray = '[{"id":99,"status":"completed"}]';

/// Canned queued build.
const _queuedBuild = '{"id":99,"status":"queued"}';

/// Canned work-item-type array.
const _typeArray = '[{"name":"Bug"},{"name":"Task"}]';

/// `ado_update_work_item` — PATCH with JSON-Patch field ops.
void updateWorkItemTests() {
  group('AdoClient.updateWorkItem', () {
    test('PATCHes one add-op per field with the json-patch content type',
        () async {
      final f = mockAdo((o) => routeByPath({'/workitems/42': _updatedItem}, o));
      final result = await f.client.updateWorkItem(
        42,
        <String, dynamic>{'System.Title': 'New', 'System.State': 'Active'},
      );
      expect(result['rev'], 3);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/contoso/dmtools/_apis/wit/workitems/42'));
      expect(call.headers['Content-Type'], 'application/json-patch+json');
      final ops = jsonDecode(call.data as String) as List;
      expect(ops, [
        {'op': 'add', 'path': '/fields/System.Title', 'value': 'New'},
        {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
      ]);
    });
  });
}

/// `ado_get_work_items` — GET `wit/workitems?ids=`.
void getWorkItemsTests() {
  group('AdoClient.getWorkItems', () {
    test('GETs the ids query and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/workitems': _itemArray}, o));
      final items = await f.client.getWorkItems([1, 2]);
      expect(items.map((i) => i['id']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.queryParameters['ids'], '1,2');
      expect(call.queryParameters['api-version'], '7.0');
    });
  });
}

/// `ado_list_work_items` — POST `wit/wiql`.
void listWorkItemsTests() {
  group('AdoClient.listWorkItems', () {
    test('POSTs the WIQL query body and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/wiql': _itemArray}, o));
      final items = await f.client.listWorkItems('Select [System.Id]');
      expect(items.map((i) => i['id']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/contoso/dmtools/_apis/wit/wiql'));
      expect(jsonDecode(call.data as String), {'query': 'Select [System.Id]'});
    });
  });
}

/// `ado_get_work_item_types` — GET `wit/workitemtypes`.
void getWorkItemTypesTests() {
  group('AdoClient.getWorkItemTypes', () {
    test('GETs workitemtypes and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/workitemtypes': _typeArray}, o));
      final types = await f.client.getWorkItemTypes(_project);
      expect(types.map((t) => t['name']).toList(), ['Bug', 'Task']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/dmtools/_apis/wit/workitemtypes'));
    });
  });
}

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

/// `ado_get_builds` — GET `build/builds` with an optional definitions filter.
void getBuildsTests() {
  group('AdoClient.getBuilds', () {
    test('GETs builds without a definitions filter by default', () async {
      final f = mockAdo((o) => routeByPath({'/builds': _buildArray}, o));
      final builds = await f.client.getBuilds(_project);
      expect(builds.single['id'], 99);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.queryParameters.containsKey('definitions'), isFalse);
    });

    test('joins the definitions filter into the query parameter', () async {
      final f = mockAdo((o) => routeByPath({'/builds': _buildArray}, o));
      await f.client.getBuilds(_project, [3, 4]);
      expect(f.adapter.calls.single.queryParameters['definitions'], '3,4');
    });
  });
}

/// `ado_trigger_build` — POST `build/builds`.
void triggerBuildTests() {
  group('AdoClient.triggerBuild', () {
    test('POSTs the definition id body and decodes the object', () async {
      final f = mockAdo((o) => routeByPath({'/builds': _queuedBuild}, o));
      final result = await f.client.triggerBuild(7);
      expect(result['status'], 'queued');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/contoso/dmtools/_apis/build/builds'));
      expect(jsonDecode(call.data as String), {
        'definition': {'id': 7},
      });
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the batch-2 tools.
void batch2CatalogTests() {
  group('adoTools catalog (batch 2)', () {
    test('registers all eight batch-2 tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_update_work_item',
        'ado_get_work_items',
        'ado_list_work_items',
        'ado_get_work_item_types',
        'ado_create_repo',
        'ado_get_repos',
        'ado_get_builds',
        'ado_trigger_build',
      ]) {
        expect(names, contains(name));
      }
    });

    test('ado_update_work_item declares id and fields', () {
      final tool = toolNamed('ado_update_work_item');
      expect(tool.params.map((p) => p.name), ['id', 'fields']);
      expect(tool.params.first.type, 'number');
      expect(tool.params.last.type, 'object');
    });

    test('ado_get_work_items declares a required ids array', () {
      final tool = toolNamed('ado_get_work_items');
      expect(tool.params.single.name, 'ids');
      expect(tool.params.single.type, 'array');
    });

    test('ado_list_work_items declares a required wiql string', () {
      final tool = toolNamed('ado_list_work_items');
      expect(tool.params.single.name, 'wiql');
    });

    test('ado_get_builds makes definitions optional', () {
      final tool = toolNamed('ado_get_builds');
      expect(tool.params.map((p) => p.name), ['project', 'definitions']);
      expect(tool.params.last.required, isFalse);
    });

    test('ado_trigger_build declares a numeric definitionId', () {
      final tool = toolNamed('ado_trigger_build');
      expect(tool.params.single.name, 'definitionId');
      expect(tool.params.single.type, 'number');
    });
  });
}

/// [AdoToolExecutor.execute] routing for the batch-2 work-item tools.
void batch2ExecutorTests() {
  late _Batch2Fixture f;

  group('AdoToolExecutor.execute (batch 2: work items)', () {
    setUp(() => f = _batch2Fixture());

    test('routes ado_update_work_item with id and fields', () async {
      await f.executor.execute('ado_update_work_item', {
        'id': 42,
        'fields': <String, dynamic>{'System.Title': 'New'},
      });
      expect(f.spy.calls.single, 'updateWorkItem:42:System.Title=New');
    });

    test('routes ado_get_work_items with an int list', () async {
      await f.executor.execute('ado_get_work_items', {
        'ids': [1, 2]
      });
      expect(f.spy.calls.single, 'getWorkItems:1,2');
    });

    test('routes ado_list_work_items with the wiql query', () async {
      await f.executor.execute('ado_list_work_items', {'wiql': 'Select [Id]'});
      expect(f.spy.calls.single, 'listWorkItems:Select [Id]');
    });

    test('routes ado_get_work_item_types with the project', () async {
      await f.executor.execute('ado_get_work_item_types', {'project': 'p'});
      expect(f.spy.calls.single, 'getWorkItemTypes:p');
    });
  });
}

/// [AdoToolExecutor.execute] routing for the batch-2 repo and build tools.
void batch2ExecutorRepoBuildTests() {
  late _Batch2Fixture f;

  group('AdoToolExecutor.execute (batch 2: repos & builds)', () {
    setUp(() => f = _batch2Fixture());

    test('routes ado_create_repo with project and name', () async {
      await f.executor
          .execute('ado_create_repo', {'project': 'p', 'name': 'r'});
      expect(f.spy.calls.single, 'createRepo:p:r');
    });

    test('routes ado_get_repos with the project', () async {
      await f.executor.execute('ado_get_repos', {'project': 'p'});
      expect(f.spy.calls.single, 'getRepos:p');
    });

    test('routes ado_get_builds with optional definitions', () async {
      await f.executor.execute('ado_get_builds', {
        'project': 'p',
        'definitions': [3],
      });
      expect(f.spy.calls.single, 'getBuilds:p:3');
    });

    test('routes ado_get_builds without definitions', () async {
      await f.executor.execute('ado_get_builds', {'project': 'p'});
      expect(f.spy.calls.single, 'getBuilds:p:');
    });

    test('routes ado_trigger_build with a numeric definitionId', () async {
      await f.executor.execute('ado_trigger_build', {'definitionId': 7});
      expect(f.spy.calls.single, 'triggerBuild:7');
    });

    test('parses a numeric-string definitionId', () async {
      await f.executor.execute('ado_trigger_build', {'definitionId': '7'});
      expect(f.spy.calls.single, 'triggerBuild:7');
    });
  });
}

/// Serves method-aware canned bodies for every batch-2 endpoint.
String _batch2Router(RequestOptions o) {
  // createRepo (POST) returns one repo; getRepos (GET) returns a list.
  if (o.path.endsWith('/repositories')) {
    return o.method == 'POST' ? _repo : _repoArray;
  }
  // triggerBuild (POST) returns one build; getBuilds (GET) returns a list.
  if (o.path.endsWith('/builds')) {
    return o.method == 'POST' ? _queuedBuild : _buildArray;
  }
  return routeByPath({
    '/workitems/42': _updatedItem,
    '/workitems': _itemArray,
    '/wiql': _itemArray,
    '/workitemtypes': _typeArray,
  }, o);
}

/// A spy client plus the executor bound to it.
typedef _Batch2Fixture = ({AdoToolExecutor executor, _Batch2Spy spy});

/// Builds a [_Batch2Spy] over the mocked transport and wraps it.
_Batch2Fixture _batch2Fixture() {
  final spy = _Batch2Spy(mockAdoHttp(_batch2Router).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched batch-2 call then delegates to the real client.
class _Batch2Spy extends AdoClient {
  _Batch2Spy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> updateWorkItem(
    int id,
    Map<String, dynamic> fields,
  ) {
    final summary = fields.entries.map((e) => '${e.key}=${e.value}').join(',');
    calls.add('updateWorkItem:$id:$summary');
    return super.updateWorkItem(id, fields);
  }

  @override
  Future<List<Map<String, dynamic>>> getWorkItems(List<int> ids) {
    calls.add('getWorkItems:${ids.join(',')}');
    return super.getWorkItems(ids);
  }

  @override
  Future<List<Map<String, dynamic>>> listWorkItems(String wiql) {
    calls.add('listWorkItems:$wiql');
    return super.listWorkItems(wiql);
  }

  @override
  Future<List<Map<String, dynamic>>> getWorkItemTypes(String project) {
    calls.add('getWorkItemTypes:$project');
    return super.getWorkItemTypes(project);
  }

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
  Future<List<Map<String, dynamic>>> getBuilds(
    String project, [
    List<int>? definitions,
  ]) {
    final d = definitions?.join(',') ?? '';
    calls.add('getBuilds:$project:$d');
    return super.getBuilds(project, definitions);
  }

  @override
  Future<Map<String, dynamic>> triggerBuild(int definitionId) {
    calls.add('triggerBuild:$definitionId');
    return super.triggerBuild(definitionId);
  }
}
