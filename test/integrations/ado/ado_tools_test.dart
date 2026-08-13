import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Tests for the [adoTools] catalog and [AdoToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogTests();
  executorRoutingTests();
  executorEdgeCaseTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Serves `[]` for the PR-list GET (expects a JSON array), `{}` otherwise.
String _spyRouter(RequestOptions o) {
  if (o.method == 'GET' && o.path.endsWith('/pullrequests')) return '[]';
  return '{}';
}

/// Catalog shape: tool count, order, integration, and params.
void catalogTests() {
  group('adoTools catalog', () {
    final tools = adoTools();

    test('registers all tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'ado_test',
        'ado_get_work_item',
        'ado_create_work_item',
        'ado_update_work_item',
        'ado_get_work_item_revisions',
        'ado_get_work_items',
        'ado_list_work_items',
        'ado_get_work_item_types',
        'ado_get_teams',
        'ado_get_team_members',
        'ado_get_project_properties',
        'ado_list_prs',
        'ado_get_pr',
        'ado_get_pull_request_reviewers',
        'ado_add_pull_request_reviewer',
        'ado_create_repo',
        'ado_get_repos',
        'ado_get_repo_branches',
        'ado_get_commits',
        'ado_get_builds',
        'ado_trigger_build',
      ]);
    });

    test('every tool belongs to the ado integration', () {
      expect(tools.every((t) => t.integration == 'ado'), isTrue);
    });

    test('ado_get_work_item declares a required numeric id', () {
      final tool = toolNamed('ado_get_work_item');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
      expect(tool.params.single.type, 'number');
    });

    test('ado_create_work_item declares required type and title', () {
      final tool = toolNamed('ado_create_work_item');
      expect(tool.params.map((p) => p.name), ['type', 'title']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('ado_list_prs makes status optional', () {
      final tool = toolNamed('ado_list_prs');
      expect(tool.params.single.name, 'status');
      expect(tool.params.single.required, isFalse);
    });

    test('ado_get_pr declares a required numeric id', () {
      final tool = toolNamed('ado_get_pr');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.type, 'number');
    });
  });
}

/// [AdoToolExecutor.execute] routes tool names to client calls.
void executorRoutingTests() {
  late _ExecutorFixture f;

  group('AdoToolExecutor.execute', () {
    setUp(() => f = _executorFixture());

    test('routes ado_test to testConnection', () async {
      await f.executor.execute('ado_test', {});
      expect(f.spy.calls, ['testConnection']);
    });

    test('routes ado_get_work_item with id', () async {
      await f.executor.execute('ado_get_work_item', {'id': 42});
      expect(f.spy.calls, ['getWorkItem:42']);
    });

    test('routes ado_create_work_item with type and title', () async {
      await f.executor.execute('ado_create_work_item', {
        'type': 'Bug',
        'title': 'Fix bug',
      });
      expect(f.spy.calls, ['createWorkItem:Bug:Fix bug']);
    });

    test('routes ado_list_prs with an explicit status', () async {
      await f.executor.execute('ado_list_prs', {'status': 'abandoned'});
      expect(f.spy.calls, ['listPrs:abandoned']);
    });

    test('routes ado_get_pr with id', () async {
      await f.executor.execute('ado_get_pr', {'id': 7});
      expect(f.spy.calls, ['getPr:7']);
    });
  });
}

/// [AdoToolExecutor.execute] argument-coercion and error cases.
void executorEdgeCaseTests() {
  late _ExecutorFixture f;

  group('AdoToolExecutor.execute (edge cases)', () {
    setUp(() => f = _executorFixture());

    test('parses id from a numeric string', () async {
      await f.executor.execute('ado_get_pr', {'id': '7'});
      expect(f.spy.calls, ['getPr:7']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => f.executor.execute('ado_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _ExecutorFixture = ({AdoToolExecutor executor, _SpyAdoClient spy});

/// Builds a [_SpyAdoClient] over the mocked transport and wraps it.
_ExecutorFixture _executorFixture() {
  final spy = _SpyAdoClient(mockAdoHttp(_spyRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyAdoClient extends AdoClient {
  _SpyAdoClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>> getWorkItem(int id) {
    calls.add('getWorkItem:$id');
    return super.getWorkItem(id);
  }

  @override
  Future<Map<String, dynamic>> createWorkItem(String type, String title) {
    calls.add('createWorkItem:$type:$title');
    return super.createWorkItem(type, title);
  }

  @override
  Future<List<Map<String, dynamic>>> listPrs([String? status]) {
    calls.add('listPrs:$status');
    return super.listPrs(status);
  }

  @override
  Future<Map<String, dynamic>> getPr(int id) {
    calls.add('getPr:$id');
    return super.getPr(id);
  }
}
