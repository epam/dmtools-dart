import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'xray_test_support.dart';

/// Tests for the [xrayTools] catalog and [XrayToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  toolCatalogParamTests();
  executorDispatchTests();
  executionStepPlanDispatchTests();
  runUpdateDispatchTests();
  portedReadParamTests();
  portedWriteParamTests();
  portedJiraDispatchTests();
  portedReadDispatchTests();
  portedStepWriteDispatchTests();
  portedPreconditionWriteDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    xrayTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, and integration.
void toolCatalogShapeTests() {
  group('xrayTools catalog', () {
    final tools = xrayTools();

    test('registers the seventeen tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'jira_xray_test',
        'jira_xray_get_tests',
        'jira_xray_get_test_executions',
        'jira_xray_get_test_steps',
        'jira_xray_get_test_runs',
        'jira_xray_get_test_plan',
        'jira_xray_create_test_execution',
        'jira_xray_update_test_execution',
        'jira_xray_create_precondition',
        'jira_xray_search_tickets',
        'jira_xray_get_test_details',
        'jira_xray_get_preconditions',
        'jira_xray_get_precondition_details',
        'jira_xray_add_test_step',
        'jira_xray_add_test_steps',
        'jira_xray_add_precondition_to_test',
        'jira_xray_add_preconditions_to_test',
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

/// Catalog params for the ported precondition, search, and GraphQL read
/// tools.
void portedReadParamTests() {
  test('jira_xray_create_precondition takes project, summary, and options', () {
    final tool = toolNamed('jira_xray_create_precondition');
    expect(tool.category, 'xray_management');
    expect(
      tool.params.map((p) => p.name),
      ['project', 'summary', 'description', 'steps'],
    );
    expect(tool.params.take(2).every((p) => p.required), isTrue);
    expect(tool.params.skip(2).every((p) => p.required), isFalse);
  });

  test('jira_xray_search_tickets takes a JQL query and optional fields', () {
    final tool = toolNamed('jira_xray_search_tickets');
    expect(tool.category, 'search');
    expect(tool.params.map((p) => p.name), ['searchQueryJQL', 'fields']);
    expect(tool.params[0].required, isTrue);
    expect(tool.params[1].required, isFalse);
    expect(tool.params[1].type, 'array');
  });

  test('jira_xray_get_test_details requires a testKey', () {
    final tool = toolNamed('jira_xray_get_test_details');
    expect(tool.category, 'test_retrieval');
    expect(tool.params.map((p) => p.name), ['testKey']);
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_get_preconditions requires a testKey', () {
    final tool = toolNamed('jira_xray_get_preconditions');
    expect(tool.category, 'test_retrieval');
    expect(tool.params.map((p) => p.name), ['testKey']);
    expect(tool.params.single.required, isTrue);
  });

  test('jira_xray_get_precondition_details requires a preconditionKey', () {
    final tool = toolNamed('jira_xray_get_precondition_details');
    expect(tool.category, 'test_retrieval');
    expect(tool.params.map((p) => p.name), ['preconditionKey']);
    expect(tool.params.single.required, isTrue);
  });
}

/// Catalog params for the ported GraphQL write tools.
void portedWriteParamTests() {
  test('jira_xray_add_test_step takes issueId, action, and options', () {
    final tool = toolNamed('jira_xray_add_test_step');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name),
        ['issueId', 'action', 'data', 'result']);
    expect(tool.params.take(2).every((p) => p.required), isTrue);
    expect(tool.params.skip(2).every((p) => p.required), isFalse);
  });

  test('jira_xray_add_test_steps requires issueId and a steps array', () {
    final tool = toolNamed('jira_xray_add_test_steps');
    expect(tool.category, 'test_management');
    expect(tool.params.map((p) => p.name), ['issueId', 'steps']);
    expect(tool.params[1].type, 'array');
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('jira_xray_add_precondition_to_test requires both issue IDs', () {
    final tool = toolNamed('jira_xray_add_precondition_to_test');
    expect(tool.category, 'test_management');
    expect(
      tool.params.map((p) => p.name),
      ['testIssueId', 'preconditionIssueId'],
    );
    expect(tool.params.every((p) => p.required), isTrue);
  });

  test('jira_xray_add_preconditions_to_test requires an ID array', () {
    final tool = toolNamed('jira_xray_add_preconditions_to_test');
    expect(tool.category, 'test_management');
    expect(
      tool.params.map((p) => p.name),
      ['testIssueId', 'preconditionIssueIds'],
    );
    expect(tool.params[1].type, 'array');
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

/// Executor dispatch tests for the execution, step, and plan read tools.
void executionStepPlanDispatchTests() {
  group('XrayToolExecutor.execute (executions, steps, plans)', () {
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

/// Executor dispatch tests for the execution update and run read tools.
void runUpdateDispatchTests() {
  group('XrayToolExecutor.execute (execution updates and test runs)', () {
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

/// Executor dispatch tests for the ported Jira-backed tools.
void portedJiraDispatchTests() {
  group('XrayToolExecutor.execute (ported Jira-backed tools)', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_create_precondition with parsed steps', () async {
      await executor.execute('jira_xray_create_precondition', {
        'project': 'TP',
        'summary': 'System is ready',
        'description': 'All components initialized',
        'steps': '[{"action":"boot","data":"cfg","result":"started"}]',
      });
      expect(spy.calls, [
        'createPrecondition:TP:System is ready:All components initialized:'
            '[{action: boot, data: cfg, result: started}]',
      ]);
    });

    test('tolerates unparseable create_precondition steps', () async {
      await executor.execute('jira_xray_create_precondition', {
        'project': 'TP',
        'summary': 'System is ready',
        'steps': 'not json',
      });
      expect(spy.calls, ['createPrecondition:TP:System is ready:null:null']);
    });

    test('routes jira_xray_search_tickets with a fields list', () async {
      await executor.execute('jira_xray_search_tickets', {
        'searchQueryJQL': 'project = TP AND issueType = Test',
        'fields': ['summary', 'status'],
      });
      expect(spy.calls, [
        'searchTickets:project = TP AND issueType = Test:[summary, status]',
      ]);
    });
  });
}

/// Executor dispatch tests for the ported GraphQL read tools.
void portedReadDispatchTests() {
  group('XrayToolExecutor.execute (ported GraphQL reads)', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_get_test_details with a testKey', () async {
      await executor
          .execute('jira_xray_get_test_details', {'testKey': 'TP-909'});
      expect(spy.calls, ['getTestDetails:TP-909']);
    });

    test('routes jira_xray_get_preconditions with a testKey', () async {
      await executor
          .execute('jira_xray_get_preconditions', {'testKey': 'TP-909'});
      expect(spy.calls, [
        'getPreconditions:TP-909',
        'getTestDetails:TP-909',
      ]);
    });

    test('routes jira_xray_get_precondition_details with a key', () async {
      await executor.execute(
        'jira_xray_get_precondition_details',
        {'preconditionKey': 'TP-910'},
      );
      expect(spy.calls, ['getPreconditionDetails:TP-910']);
    });
  });
}

/// Executor dispatch tests for the ported test-step write tools.
void portedStepWriteDispatchTests() {
  group('XrayToolExecutor.execute (ported step writes)', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_add_test_step with optional data and result',
        () async {
      await executor.execute('jira_xray_add_test_step', {
        'issueId': '12345',
        'action': 'Enter username',
        'data': 'test_user',
        'result': 'Username accepted',
      });
      expect(
        spy.calls,
        ['addTestStep:12345:Enter username:test_user:Username accepted'],
      );
    });

    test('routes jira_xray_add_test_steps with a steps array', () async {
      await executor.execute('jira_xray_add_test_steps', {
        'issueId': '12345',
        'steps': [
          {'action': 'a1'},
          {'action': 'a2'},
        ],
      });
      expect(spy.calls, [
        'addTestSteps:12345:[{action: a1}, {action: a2}]',
        'addTestStep:12345:a1:null:null',
        'addTestStep:12345:a2:null:null',
      ]);
    });
  });
}

/// Executor dispatch tests for the ported precondition write tools.
void portedPreconditionWriteDispatchTests() {
  group('XrayToolExecutor.execute (ported precondition writes)', () {
    late _SpyXrayClient spy;
    late XrayToolExecutor executor;

    setUp(() {
      spy = _SpyXrayClient(mockXrayHttp((o) => '{}').http);
      executor = XrayToolExecutor(spy);
    });

    test('routes jira_xray_add_precondition_to_test with both IDs', () async {
      await executor.execute('jira_xray_add_precondition_to_test', {
        'testIssueId': '12345',
        'preconditionIssueId': '12346',
      });
      expect(spy.calls, ['addPreconditionToTest:12345:12346']);
    });

    test('routes jira_xray_add_preconditions_to_test with an ID array',
        () async {
      await executor.execute('jira_xray_add_preconditions_to_test', {
        'testIssueId': '12345',
        'preconditionIssueIds': ['12346', '12347'],
      });
      expect(
        spy.calls,
        [
          'addPreconditionsToTest:12345:[12346, 12347]',
          'addPreconditionToTest:12345:12346',
          'addPreconditionToTest:12345:12347',
        ],
      );
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

  @override
  Future<Map<String, dynamic>?> getTestDetails(String testKey) {
    calls.add('getTestDetails:$testKey');
    return super.getTestDetails(testKey);
  }

  @override
  Future<List<Map<String, dynamic>>> getPreconditions(String testKey) {
    calls.add('getPreconditions:$testKey');
    return super.getPreconditions(testKey);
  }

  @override
  Future<Map<String, dynamic>?> getPreconditionDetails(String key) {
    calls.add('getPreconditionDetails:$key');
    return super.getPreconditionDetails(key);
  }

  @override
  Future<Map<String, dynamic>?> addTestStep(
    String issueId,
    String action, [
    String? data,
    String? result,
  ]) {
    calls.add('addTestStep:$issueId:$action:$data:$result');
    return super.addTestStep(issueId, action, data, result);
  }

  @override
  Future<List<Map<String, dynamic>>> addTestSteps(
    String issueId,
    List<Map<String, dynamic>> steps,
  ) {
    calls.add('addTestSteps:$issueId:$steps');
    return super.addTestSteps(issueId, steps);
  }

  @override
  Future<Map<String, dynamic>?> addPreconditionToTest(
    String testIssueId,
    String preconditionIssueId,
  ) {
    calls.add('addPreconditionToTest:$testIssueId:$preconditionIssueId');
    return super.addPreconditionToTest(testIssueId, preconditionIssueId);
  }

  @override
  Future<List<Map<String, dynamic>>> addPreconditionsToTest(
    String testIssueId,
    List<String> preconditionIssueIds,
  ) {
    calls.add('addPreconditionsToTest:$testIssueId:$preconditionIssueIds');
    return super.addPreconditionsToTest(testIssueId, preconditionIssueIds);
  }

  @override
  Future<String> createPrecondition(
    String project,
    String summary, {
    String? description,
    List<Map<String, dynamic>>? steps,
  }) {
    calls.add('createPrecondition:$project:$summary:$description:$steps');
    // no super call: the Jira transport is not wired in this spy fixture.
    return Future.value('TP-1301');
  }

  @override
  Future<List<Map<String, dynamic>>> searchTickets(
    String searchQueryJQL, [
    List<String>? fields,
  ]) {
    calls.add('searchTickets:$searchQueryJQL:$fields');
    // no super call: the Jira transport is not wired in this spy fixture.
    return Future.value(const []);
  }
}
