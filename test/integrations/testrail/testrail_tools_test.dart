import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'testrail_test_support.dart';

/// Tests for the [testrailTools] catalog and [TestRailToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  toolCatalogParamTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    testrailTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, and integration.
void toolCatalogShapeTests() {
  group('testrailTools catalog', () {
    final tools = testrailTools();

    test('registers the four tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'testrail_test',
        'testrail_get_case',
        'testrail_get_cases',
        'testrail_add_result',
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
}
