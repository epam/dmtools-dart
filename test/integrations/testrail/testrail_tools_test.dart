import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'testrail_test_support.dart';

/// Tests for the [testrailTools] catalog and [TestRailToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  toolCatalogParamTests();
  toolCatalogBatch2ParamTests();
  executorDispatchTests();
  executorBatch2DispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    testrailTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, and integration.
void toolCatalogShapeTests() {
  group('testrailTools catalog', () {
    final tools = testrailTools();

    test('registers the eight tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'testrail_test',
        'testrail_get_case',
        'testrail_get_cases',
        'testrail_add_case',
        'testrail_update_case',
        'testrail_add_result',
        'testrail_get_runs',
        'testrail_get_sections',
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
}
