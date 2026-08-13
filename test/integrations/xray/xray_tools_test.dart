import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'xray_test_support.dart';

/// Tests for the [xrayTools] catalog and [XrayToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  toolCatalogParamTests();
  executorDispatchTests();
  batch2ExecutorDispatchTests();
  batch3ExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    xrayTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, and integration.
void toolCatalogShapeTests() {
  group('xrayTools catalog', () {
    final tools = xrayTools();

    test('registers the eight tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'jira_xray_test',
        'jira_xray_get_tests',
        'jira_xray_get_test_executions',
        'jira_xray_get_test_steps',
        'jira_xray_get_test_runs',
        'jira_xray_get_test_plan',
        'jira_xray_create_test_execution',
        'jira_xray_update_test_execution',
      ]);
    });

    test('every tool belongs to the jira_xray integration', () {
      expect(tools.every((t) => t.integration == 'jira_xray'), isTrue);
    });
  });
}

/// Catalog params: each tool's parameter names, types, and requiredness.
void toolCatalogParamTests() {
  test('jira_xray_test takes no parameters', () {
    expect(toolNamed('jira_xray_test').params, isEmpty);
  });

  test('jira_xray_get_tests requires a testKeys array', () {
    final tool = toolNamed('jira_xray_get_tests');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['testKeys']);
    expect(tool.params.single.type, 'array');
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_create_test_execution takes projectKey and testExecJson', () {
    final tool = toolNamed('jira_xray_create_test_execution');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['projectKey', 'testExecJson']);
    expect(tool.params[0].type, 'string');
    expect(tool.params[1].type, 'object');
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('jira_xray_get_test_executions requires a testKey', () {
    final tool = toolNamed('jira_xray_get_test_executions');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['testKey']);
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_get_test_steps requires a testKey', () {
    final tool = toolNamed('jira_xray_get_test_steps');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['testKey']);
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_get_test_plan requires a testPlanKey', () {
    final tool = toolNamed('jira_xray_get_test_plan');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['testPlanKey']);
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_get_test_runs requires a testKey', () {
    final tool = toolNamed('jira_xray_get_test_runs');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['testKey']);
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_update_test_execution requires executionId and status', () {
    final tool = toolNamed('jira_xray_update_test_execution');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['executionId', 'status']);
    expect(tool.params[0].type, 'string');
    expect(tool.params[1].type, 'string');
    expect(tool.params.every((p) => p.required), isTrue);
  });
}

/// [XrayToolExecutor.execute] routes each tool name to the right call.
void executorDispatchTests() {
  group('XrayToolExecutor.execute', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_test to testConnection', () async {
      await executor.execute('jira_xray_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes jira_xray_get_tests with a list', () async {
      await executor.execute('jira_xray_get_tests', {
        'testKeys': ['PROJ-1', 'PROJ-2'],
      });
      expect(spy.calls, ['getTests:PROJ-1,PROJ-2']);
    });

    test('accepts comma-separated testKeys string', () async {
      await executor.execute('jira_xray_get_tests', {
        'testKeys': 'PROJ-1,PROJ-2',
      });
      expect(spy.calls, ['getTests:PROJ-1,PROJ-2']);
    });

    test('routes jira_xray_create_test_execution', () async {
      await executor.execute('jira_xray_create_test_execution', {
        'projectKey': 'PROJ',
        'testExecJson': {
          'info': {'summary': 'Run'}
        },
      });
      expect(spy.calls, ['createTestExecution:PROJ:{info: {summary: Run}}']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => executor.execute('jira_xray_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// Batch-2 executor dispatch tests for the new Xray read tools.
void batch2ExecutorDispatchTests() {
  group('XrayToolExecutor.execute batch-2', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_get_test_executions with a testKey', () async {
      await executor
          .execute('jira_xray_get_test_executions', {'testKey': 'PROJ-1'});
      expect(spy.calls, ['getTestExecutions:PROJ-1']);
    });

    test('routes jira_xray_get_test_steps with a testKey', () async {
      await executor.execute('jira_xray_get_test_steps', {'testKey': 'PROJ-1'});
      expect(spy.calls, ['getTestSteps:PROJ-1']);
    });

    test('routes jira_xray_get_test_plan with a testPlanKey', () async {
      await executor
          .execute('jira_xray_get_test_plan', {'testPlanKey': 'PROJ-100'});
      expect(spy.calls, ['getTestPlan:PROJ-100']);
    });
  });
}

/// Batch-3 executor dispatch tests for the new Xray write/read tools.
void batch3ExecutorDispatchTests() {
  group('XrayToolExecutor.execute batch-3', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_update_test_execution', () async {
      await executor.execute('jira_xray_update_test_execution', {
        'executionId': '100',
        'status': 'PASS',
      });
      expect(spy.calls, ['updateTestExecution:100:PASS']);
    });

    test('routes jira_xray_get_test_runs with a testKey', () async {
      await executor.execute('jira_xray_get_test_runs', {'testKey': 'PROJ-1'});
      expect(spy.calls, ['getTestRuns:PROJ-1']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyXrayClient extends XrayClient {
  _SpyXrayClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<List<Map<String, dynamic>>> getTests(List<String> testKeys) {
    calls.add('getTests:${testKeys.join(',')}');
    return super.getTests(testKeys);
  }

  @override
  Future<Map<String, dynamic>> createTestExecution(
    String projectKey,
    Map<String, dynamic> testExecJson,
  ) {
    calls.add('createTestExecution:$projectKey:$testExecJson');
    return super.createTestExecution(projectKey, testExecJson);
  }

  @override
  Future<List<Map<String, dynamic>>> getTestExecutions(String testKey) {
    calls.add('getTestExecutions:$testKey');
    return super.getTestExecutions(testKey);
  }

  @override
  Future<List<Map<String, dynamic>>> getTestSteps(String testKey) {
    calls.add('getTestSteps:$testKey');
    return super.getTestSteps(testKey);
  }

  @override
  Future<Map<String, dynamic>> getTestPlan(String testPlanKey) {
    calls.add('getTestPlan:$testPlanKey');
    return super.getTestPlan(testPlanKey);
  }

  @override
  Future<Map<String, dynamic>> updateTestExecution(
    String executionId,
    String status,
  ) {
    calls.add('updateTestExecution:$executionId:$status');
    return super.updateTestExecution(executionId, status);
  }

  @override
  Future<List<Map<String, dynamic>>> getTestRuns(String testKey) {
    calls.add('getTestRuns:$testKey');
    return super.getTestRuns(testKey);
  }
}
