import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'testrail_test_support.dart';

/// Tests for the [testrailTools] catalog and [TestRailToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  toolCatalogParamTests();
  toolCatalogBatch2ParamTests();
  toolCatalogBatch3ParamTests();
  toolCatalogBatch4ParamTests();
  executorDispatchTests();
  executorBatch2DispatchTests();
  executorBatch3DispatchTests();
  executorBatch4DispatchTests();
  executorBatch5DispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    testrailTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, and integration.
void toolCatalogShapeTests() {
  group('testrailTools catalog', () {
    final tools = testrailTools();

    test('registers the eighteen tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'testrail_test',
        'testrail_get_case',
        'testrail_get_cases',
        'testrail_add_case',
        'testrail_update_case',
        'testrail_delete_case',
        'testrail_add_result',
        'testrail_get_runs',
        'testrail_get_sections',
        'testrail_get_milestones',
        'testrail_get_plans',
        'testrail_add_run',
        'testrail_update_run',
        'testrail_get_case_types',
        'testrail_get_priorities',
        'testrail_get_statuses',
        'testrail_get_references',
        'testrail_get_templates',
      ]);
    });

    test('every tool belongs to the testrail integration', () {
      expect(tools.every((t) => t.integration == 'testrail'), isTrue);
    });
  });
}

/// Catalog params: each tool's parameter names, types, and requiredness.
void toolCatalogParamTests() {
  test('testrail_test takes no parameters', () {
    expect(toolNamed('testrail_test').params, isEmpty);
  });

  test('testrail_get_case requires a numeric id', () {
    final tool = toolNamed('testrail_get_case');
    expect(tool.category, 'test_cases');
    expect(tool.params.map((p) => p.name), ['id']);
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_get_cases requires a numeric suiteId', () {
    final tool = toolNamed('testrail_get_cases');
    expect(tool.category, 'test_cases');
    expect(tool.params.map((p) => p.name), ['suiteId']);
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_add_result takes testId, statusId, and comment', () {
    final tool = toolNamed('testrail_add_result');
    expect(tool.category, 'test_results');
    expect(tool.params.map((p) => p.name), ['testId', 'statusId', 'comment']);
    expect(tool.params[0].type, 'number');
    expect(tool.params[1].type, 'number');
    expect(tool.params[2].type, 'string');
    expect(tool.params.every((p) => p.required), isTrue);
  });
}

/// Batch-2 catalog params: runs, sections, and case write tools.
void toolCatalogBatch2ParamTests() {
  test('testrail_add_case requires a numeric sectionId and title', () {
    final tool = toolNamed('testrail_add_case');
    expect(tool.category, 'test_cases');
    expect(tool.params.map((p) => p.name), ['sectionId', 'title']);
    expect(tool.params[0].type, 'number');
    expect(tool.params[1].type, 'string');
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('testrail_update_case requires a numeric id and object fields', () {
    final tool = toolNamed('testrail_update_case');
    expect(tool.category, 'test_cases');
    expect(tool.params.map((p) => p.name), ['id', 'fields']);
    expect(tool.params[0].type, 'number');
    expect(tool.params[1].type, 'object');
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('testrail_delete_case requires a numeric id', () {
    final tool = toolNamed('testrail_delete_case');
    expect(tool.category, 'test_cases');
    expect(tool.params.single.name, 'id');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_get_runs requires a numeric projectId', () {
    final tool = toolNamed('testrail_get_runs');
    expect(tool.category, 'test_runs');
    expect(tool.params.single.name, 'projectId');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_get_sections requires a numeric suiteId', () {
    final tool = toolNamed('testrail_get_sections');
    expect(tool.category, 'sections');
    expect(tool.params.single.name, 'suiteId');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });
}

/// [TestRailToolExecutor.execute] routes each tool name to the right call.
void executorDispatchTests() {
  group('TestRailToolExecutor.execute', () {
    late _SpyTestRailClient spy;
    late TestRailToolExecutor executor;

    setUp(() {
      spy = _SpyTestRailClient(mockTestRailHttp((o) => '{}').http);
      executor = TestRailToolExecutor(spy);
    });

    test('routes testrail_test to testConnection', () async {
      await executor.execute('testrail_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes testrail_get_case with a numeric id', () async {
      await executor.execute('testrail_get_case', {'id': 1});
      expect(spy.calls, ['getCase:1']);
    });

    test('accepts string ids from the MCP protocol', () async {
      await executor.execute('testrail_get_case', {'id': '1'});
      expect(spy.calls, ['getCase:1']);
    });

    test('routes testrail_get_cases with suiteId', () async {
      await executor.execute('testrail_get_cases', {'suiteId': 2});
      expect(spy.calls, ['getCases:2']);
    });

    test('routes testrail_add_result with testId, statusId, comment', () async {
      await executor.execute('testrail_add_result', {
        'testId': 3,
        'statusId': 1,
        'comment': 'Passed',
      });
      expect(spy.calls, ['addResult:3:1:Passed']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => executor.execute('testrail_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// Batch-2 dispatch tests for runs, sections, and case write tools.
void executorBatch2DispatchTests() {
  group('TestRailToolExecutor.execute (batch 2)', () {
    late _SpyTestRailClient spy;
    late TestRailToolExecutor executor;

    setUp(() {
      spy = _SpyTestRailClient(mockTestRailHttp((o) => '{}').http);
      executor = TestRailToolExecutor(spy);
    });

    test('routes testrail_get_runs with projectId', () async {
      await executor.execute('testrail_get_runs', {'projectId': 5});
      expect(spy.calls, ['getRuns:5']);
    });

    test('routes testrail_get_sections with suiteId', () async {
      await executor.execute('testrail_get_sections', {'suiteId': 7});
      expect(spy.calls, ['getSections:7']);
    });

    test('routes testrail_add_case with sectionId and title', () async {
      await executor.execute('testrail_add_case', {
        'sectionId': 4,
        'title': 'New case',
      });
      expect(spy.calls, ['addCase:4:New case']);
    });

    test('routes testrail_update_case with id and fields map', () async {
      await executor.execute('testrail_update_case', {
        'id': 9,
        'fields': {'title': 'Updated'},
      });
      expect(spy.calls, ['updateCase:9']);
    });
  });
}

/// Batch-3 catalog params: milestones, plans, and run write tools.
void toolCatalogBatch3ParamTests() {
  test('testrail_get_milestones requires a numeric projectId', () {
    final tool = toolNamed('testrail_get_milestones');
    expect(tool.category, 'milestones');
    expect(tool.params.single.name, 'projectId');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_get_plans requires a numeric projectId', () {
    final tool = toolNamed('testrail_get_plans');
    expect(tool.category, 'test_plans');
    expect(tool.params.single.name, 'projectId');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_add_run requires projectId and name', () {
    final tool = toolNamed('testrail_add_run');
    expect(tool.category, 'test_runs');
    expect(tool.params.map((p) => p.name), ['projectId', 'name']);
    expect(tool.params[0].type, 'number');
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('testrail_update_run requires runId and name', () {
    final tool = toolNamed('testrail_update_run');
    expect(tool.category, 'test_runs');
    expect(tool.params.map((p) => p.name), ['runId', 'name']);
    expect(tool.params[0].type, 'number');
    expect(tool.params.every((p) => p.required), isTrue);
  });
}

/// Batch-3 dispatch tests for milestones, plans, and run write tools.
void executorBatch3DispatchTests() {
  group('TestRailToolExecutor.execute (batch 3)', () {
    late _SpyTestRailClient spy;
    late TestRailToolExecutor executor;

    setUp(() {
      spy = _SpyTestRailClient(mockTestRailHttp((o) => '{}').http);
      executor = TestRailToolExecutor(spy);
    });

    test('routes testrail_get_milestones with projectId', () async {
      await executor.execute('testrail_get_milestones', {'projectId': 5});
      expect(spy.calls, ['getMilestones:5']);
    });

    test('routes testrail_get_plans with projectId', () async {
      await executor.execute('testrail_get_plans', {'projectId': 5});
      expect(spy.calls, ['getPlans:5']);
    });

    test('routes testrail_add_run with projectId and name', () async {
      await executor.execute('testrail_add_run', {
        'projectId': 5,
        'name': 'Sprint 42',
      });
      expect(spy.calls, ['addRun:5:Sprint 42']);
    });

    test('routes testrail_update_run with runId and name', () async {
      await executor.execute('testrail_update_run', {
        'runId': 500,
        'name': 'Sprint 43',
      });
      expect(spy.calls, ['updateRun:500:Sprint 43']);
    });
  });
}

/// Batch-4 catalog params: case types, priorities, statuses.
void toolCatalogBatch4ParamTests() {
  test('testrail_get_case_types requires a numeric projectId', () {
    final tool = toolNamed('testrail_get_case_types');
    expect(tool.category, 'metadata');
    expect(tool.params.single.name, 'projectId');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_get_priorities takes no parameters', () {
    final tool = toolNamed('testrail_get_priorities');
    expect(tool.category, 'metadata');
    expect(tool.params, isEmpty);
  });

  test('testrail_get_statuses takes no parameters', () {
    final tool = toolNamed('testrail_get_statuses');
    expect(tool.category, 'metadata');
    expect(tool.params, isEmpty);
  });

  test('testrail_get_references requires a numeric projectId', () {
    final tool = toolNamed('testrail_get_references');
    expect(tool.category, 'metadata');
    expect(tool.params.single.name, 'projectId');
    expect(tool.params.single.type, 'number');
    expect(tool.params.single.required, isTrue);
  });

  test('testrail_get_templates takes no parameters', () {
    final tool = toolNamed('testrail_get_templates');
    expect(tool.category, 'metadata');
    expect(tool.params, isEmpty);
  });
}

/// Batch-4 dispatch tests for case types, priorities, and statuses.
void executorBatch4DispatchTests() {
  group('TestRailToolExecutor.execute (batch 4)', () {
    late _SpyTestRailClient spy;
    late TestRailToolExecutor executor;

    setUp(() {
      spy = _SpyTestRailClient(mockTestRailHttp((o) => '{}').http);
      executor = TestRailToolExecutor(spy);
    });

    test('routes testrail_get_case_types with projectId', () async {
      await executor.execute('testrail_get_case_types', {'projectId': 5});
      expect(spy.calls, ['getCaseTypes:5']);
    });

    test('routes testrail_get_priorities', () async {
      await executor.execute('testrail_get_priorities', {});
      expect(spy.calls, ['getPriorities']);
    });

    test('routes testrail_get_statuses', () async {
      await executor.execute('testrail_get_statuses', {});
      expect(spy.calls, ['getStatuses']);
    });
  });
}

/// Batch-5 dispatch tests for the delete-case, references, templates tools.
void executorBatch5DispatchTests() {
  group('TestRailToolExecutor.execute (batch 5)', () {
    late _SpyTestRailClient spy;
    late TestRailToolExecutor executor;

    setUp(() {
      spy = _SpyTestRailClient(mockTestRailHttp((o) => '{}').http);
      executor = TestRailToolExecutor(spy);
    });

    test('routes testrail_delete_case with id', () async {
      await executor.execute('testrail_delete_case', {'id': 9});
      expect(spy.calls, ['deleteCase:9']);
    });

    test('accepts string ids for delete_case from the MCP protocol', () async {
      await executor.execute('testrail_delete_case', {'id': '9'});
      expect(spy.calls, ['deleteCase:9']);
    });

    test('routes testrail_get_references with projectId', () async {
      await executor.execute('testrail_get_references', {'projectId': 5});
      expect(spy.calls, ['getReferences:5']);
    });

    test('routes testrail_get_templates', () async {
      await executor.execute('testrail_get_templates', {});
      expect(spy.calls, ['getTemplates']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyTestRailClient extends TestRailClient {
  _SpyTestRailClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>?> getCase(int id) {
    calls.add('getCase:$id');
    return super.getCase(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getCases(int suiteId) {
    calls.add('getCases:$suiteId');
    return super.getCases(suiteId);
  }

  @override
  Future<Map<String, dynamic>> addResult(
    int testId,
    int statusId,
    String comment,
  ) {
    calls.add('addResult:$testId:$statusId:$comment');
    return super.addResult(testId, statusId, comment);
  }

  @override
  Future<List<Map<String, dynamic>>> getRuns(int projectId) {
    calls.add('getRuns:$projectId');
    return super.getRuns(projectId);
  }

  @override
  Future<List<Map<String, dynamic>>> getSections(int suiteId) {
    calls.add('getSections:$suiteId');
    return super.getSections(suiteId);
  }

  @override
  Future<Map<String, dynamic>> addCase(int sectionId, String title) {
    calls.add('addCase:$sectionId:$title');
    return super.addCase(sectionId, title);
  }

  @override
  Future<Map<String, dynamic>> updateCase(
    int id,
    Map<String, dynamic> fields,
  ) {
    calls.add('updateCase:$id');
    return super.updateCase(id, fields);
  }

  @override
  Future<List<Map<String, dynamic>>> getMilestones(int projectId) {
    calls.add('getMilestones:$projectId');
    return super.getMilestones(projectId);
  }

  @override
  Future<List<Map<String, dynamic>>> getPlans(int projectId) {
    calls.add('getPlans:$projectId');
    return super.getPlans(projectId);
  }

  @override
  Future<Map<String, dynamic>> addRun(int projectId, String name) {
    calls.add('addRun:$projectId:$name');
    return super.addRun(projectId, name);
  }

  @override
  Future<Map<String, dynamic>> updateRun(int runId, String name) {
    calls.add('updateRun:$runId:$name');
    return super.updateRun(runId, name);
  }

  @override
  Future<List<Map<String, dynamic>>> getCaseTypes(int projectId) {
    calls.add('getCaseTypes:$projectId');
    return super.getCaseTypes(projectId);
  }

  @override
  Future<List<Map<String, dynamic>>> getPriorities() {
    calls.add('getPriorities');
    return super.getPriorities();
  }

  @override
  Future<List<Map<String, dynamic>>> getStatuses() {
    calls.add('getStatuses');
    return super.getStatuses();
  }

  @override
  Future<Map<String, dynamic>> deleteCase(int id) {
    calls.add('deleteCase:$id');
    return super.deleteCase(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getReferences(int projectId) {
    calls.add('getReferences:$projectId');
    return super.getReferences(projectId);
  }

  @override
  Future<List<Map<String, dynamic>>> getTemplates() {
    calls.add('getTemplates');
    return super.getTemplates();
  }
}
