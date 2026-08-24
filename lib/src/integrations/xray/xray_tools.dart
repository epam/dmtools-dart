/// MCP tool definitions and dispatcher for the Xray integration.
///
library;

import 'dart:convert';

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'xray_client.dart';

/// Builds an Xray tool definition with the `jira_xray` integration.
ToolDefinition _xrayTool({
  required String name,
  required String description,
  String category = 'test_management',
  List<ToolParam> params = const [],
}) =>
    ToolDefinition(
      name: name,
      description: description,
      integration: 'jira_xray',
      category: category,
      params: params,
    );

/// Returns all Xray MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> xrayTools() => [
      ..._systemTools(),
      ..._testReadTools(),
      ..._testPlanTools(),
      ..._executionTools(),
      ..._preconditionTools(),
      ..._searchTools(),
      ..._graphqlReadTools(),
      ..._testStepWriteTools(),
      ..._preconditionWriteTools(),
    ];

/// Connectivity-check tool: `jira_xray_test`.
List<ToolDefinition> _systemTools() => [
      _xrayTool(
        name: 'jira_xray_test',
        description: 'Test Xray connectivity by authenticating with OAuth2',
        category: 'system',
      ),
    ];

/// Test-read tools: `jira_xray_get_tests`, `jira_xray_get_test_executions`,
/// `jira_xray_get_test_steps`, `jira_xray_get_test_runs`.
List<ToolDefinition> _testReadTools() => [
      _xrayTool(
        name: 'jira_xray_get_tests',
        description: 'Get Xray tests by their issue keys',
        params: [
          ToolParam(
            name: 'testKeys',
            description: 'Comma-separated test keys (e.g. PROJ-1,PROJ-2)',
            type: 'array',
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_get_test_executions',
        description: 'Get the test executions that contain a given test',
        params: [
          ToolParam(
            name: 'testKey',
            description: 'The test issue key (e.g. PROJ-1)',
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_get_test_steps',
        description: 'Get the steps of a given Xray test',
        params: [
          ToolParam(
            name: 'testKey',
            description: 'The test issue key (e.g. PROJ-1)',
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_get_test_runs',
        description: 'Get the test runs for a given Xray test',
        params: [
          ToolParam(
            name: 'testKey',
            description: 'The test issue key (e.g. PROJ-1)',
            required: true,
          ),
        ],
      ),
    ];

/// Test-plan tool: `jira_xray_get_test_plan`.
List<ToolDefinition> _testPlanTools() => [
      _xrayTool(
        name: 'jira_xray_get_test_plan',
        description: 'Get a Xray test plan by its key',
        params: [
          ToolParam(
            name: 'testPlanKey',
            description: 'The test plan issue key (e.g. PROJ-100)',
            required: true,
          ),
        ],
      ),
    ];

/// Test-execution tools: `jira_xray_create_test_execution`,
/// `jira_xray_update_test_execution`.
List<ToolDefinition> _executionTools() => [
      _xrayTool(
        name: 'jira_xray_create_test_execution',
        description:
            'Create a test execution in Xray by importing execution JSON',
        params: [
          ToolParam(
            name: 'projectKey',
            description: 'The project key (e.g. PROJ)',
            required: true,
          ),
          ToolParam(
            name: 'testExecJson',
            description: 'The Xray test execution JSON body',
            type: 'object',
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_update_test_execution',
        description: 'Update the status of an Xray test execution',
        params: [
          ToolParam(
            name: 'executionId',
            description: 'The test execution ID (e.g. 100)',
            required: true,
          ),
          ToolParam(
            name: 'status',
            description: 'The new execution status (e.g. PASS, FAIL)',
            required: true,
          ),
        ],
      ),
    ];

/// Precondition-creation tool: `jira_xray_create_precondition`.
List<ToolDefinition> _preconditionTools() => [
      _xrayTool(
        name: 'jira_xray_create_precondition',
        description: 'Create a Precondition issue in Xray with optional steps '
            '(converted to definition). Returns the created ticket key.',
        category: 'xray_management',
        params: [
          ToolParam(
            name: 'project',
            description: "Project key (e.g., 'TP')",
            required: true,
          ),
          ToolParam(
            name: 'summary',
            description: 'Precondition summary',
            required: true,
          ),
          ToolParam(
            name: 'description',
            description: 'Precondition description',
            required: false,
          ),
          ToolParam(
            name: 'steps',
            description: 'Optional JSON array of steps in format '
                '[{"action": "...", "data": "...", "result": "..."}]. '
                'Will be converted to definition format.',
            required: false,
          ),
        ],
      ),
    ];

/// JQL-search tool: `jira_xray_search_tickets`.
List<ToolDefinition> _searchTools() => [
      _xrayTool(
        name: 'jira_xray_search_tickets',
        description: 'Search for Jira tickets using JQL query and enrich '
            'Test/Precondition issues with X-ray test steps and '
            'preconditions. Returns list of tickets with X-ray data.',
        category: 'search',
        params: [
          ToolParam(
            name: 'searchQueryJQL',
            description:
                "JQL search query (e.g., 'project = TP AND issueType = Test')",
            required: true,
          ),
          ToolParam(
            name: 'fields',
            description: "Array of field names to retrieve (e.g., ['summary', "
                "'description', 'status'])",
            type: 'array',
            required: false,
          ),
        ],
      ),
    ];

/// GraphQL read tools: `jira_xray_get_test_details`,
/// `jira_xray_get_preconditions`, `jira_xray_get_precondition_details`.
List<ToolDefinition> _graphqlReadTools() => [
      _xrayTool(
        name: 'jira_xray_get_test_details',
        description: 'Get test details including steps and preconditions using '
            'X-ray GraphQL API. Returns JSONObject with test details.',
        category: 'test_retrieval',
        params: [
          ToolParam(
            name: 'testKey',
            description: "Jira ticket key (e.g., 'TP-909')",
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_get_preconditions',
        description:
            'Get preconditions for a test issue using X-ray GraphQL API. '
            'Returns JSONArray of precondition objects.',
        category: 'test_retrieval',
        params: [
          ToolParam(
            name: 'testKey',
            description: "Jira ticket key (e.g., 'TP-909')",
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_get_precondition_details',
        description:
            'Get Precondition details including definition using X-ray '
            'GraphQL API. Returns JSONObject with precondition details.',
        category: 'test_retrieval',
        params: [
          ToolParam(
            name: 'preconditionKey',
            description: "Jira ticket key (e.g., 'TP-910')",
            required: true,
          ),
        ],
      ),
    ];

/// Test-step write tools: `jira_xray_add_test_step`,
/// `jira_xray_add_test_steps`.
List<ToolDefinition> _testStepWriteTools() => [
      _xrayTool(
        name: 'jira_xray_add_test_step',
        description:
            'Add a single test step to a test issue using X-ray GraphQL '
            'API. Returns JSONObject with created step details.',
        params: [
          ToolParam(
            name: 'issueId',
            description: "Jira issue ID (e.g., '12345')",
            required: true,
          ),
          ToolParam(
            name: 'action',
            description: "Step action (e.g., 'Enter username')",
            required: true,
          ),
          ToolParam(
            name: 'data',
            description: "Step data (e.g., 'test_user')",
            required: false,
          ),
          ToolParam(
            name: 'result',
            description: "Step expected result (e.g., 'Username accepted')",
            required: false,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_add_test_steps',
        description:
            'Add multiple test steps to a test issue using X-ray GraphQL '
            'API. Returns JSONArray of created step objects.',
        params: [
          ToolParam(
            name: 'issueId',
            description: "Jira issue ID (e.g., '12345')",
            required: true,
          ),
          ToolParam(
            name: 'steps',
            description:
                "JSON array string of step objects, each with 'action', "
                "'data', and 'result' fields (e.g., '[{\"action\":"
                "\"Enter username\",\"data\":\"test_user\",\"result\":"
                "\"Username accepted\"}]')",
            type: 'array',
            required: true,
          ),
        ],
      ),
    ];

/// Precondition write tools: `jira_xray_add_precondition_to_test`,
/// `jira_xray_add_preconditions_to_test`.
List<ToolDefinition> _preconditionWriteTools() => [
      _xrayTool(
        name: 'jira_xray_add_precondition_to_test',
        description:
            'Add a single precondition to a test issue using X-ray GraphQL '
            'API. Returns JSONObject with result.',
        params: [
          ToolParam(
            name: 'testIssueId',
            description: "Jira issue ID of the test (e.g., '12345')",
            required: true,
          ),
          ToolParam(
            name: 'preconditionIssueId',
            description: "Jira issue ID of the precondition (e.g., '12346')",
            required: true,
          ),
        ],
      ),
      _xrayTool(
        name: 'jira_xray_add_preconditions_to_test',
        description:
            'Add multiple preconditions to a test issue using X-ray GraphQL '
            'API. Returns JSONArray of results.',
        params: [
          ToolParam(
            name: 'testIssueId',
            description: "Jira issue ID of the test (e.g., '12345')",
            required: true,
          ),
          ToolParam(
            name: 'preconditionIssueIds',
            description: 'JSON array string of precondition issue IDs (e.g., '
                "'[\"12346\", \"12347\"]')",
            type: 'array',
            required: true,
          ),
        ],
      ),
    ];

/// Parses a list-or-comma-string argument into `List<String>`.
List<String> _parseStringList(dynamic value) {
  if (value is List) return value.cast<String>();
  if (value is String) {
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

/// Parses a `steps` argument (JSON array string or list) into step maps.
///
/// Returns `null` for absent or unparseable values, mirroring the Java
/// tolerance for malformed step input.
List<Map<String, dynamic>>? _parseSteps(dynamic value) {
  dynamic decoded = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  if (decoded is List) {
    return [for (final e in decoded) Map<String, dynamic>.from(e as Map)];
  }
  return null;
}

/// Executes Xray MCP tools by dispatching to [XrayClient].
class XrayToolExecutor {
  final XrayClient _client;

  /// Creates an executor bound to [_client].
  XrayToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Xray tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Xray tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'jira_xray_test': (_) => _client.testConnection(),
    'jira_xray_get_tests': (a) =>
        _client.getTests(_parseStringList(a['testKeys'])),
    'jira_xray_get_test_executions': (a) =>
        _client.getTestExecutions(a['testKey'] as String),
    'jira_xray_get_test_steps': (a) =>
        _client.getTestSteps(a['testKey'] as String),
    'jira_xray_get_test_plan': (a) =>
        _client.getTestPlan(a['testPlanKey'] as String),
    'jira_xray_create_test_execution': (a) => _client.createTestExecution(
          a['projectKey'] as String,
          a['testExecJson'] as Map<String, dynamic>,
        ),
    'jira_xray_update_test_execution': (a) => _client.updateTestExecution(
          a['executionId'] as String,
          a['status'] as String,
        ),
    'jira_xray_get_test_runs': (a) =>
        _client.getTestRuns(a['testKey'] as String),
    'jira_xray_create_precondition': (a) => _client.createPrecondition(
          a['project'] as String,
          a['summary'] as String,
          description: a['description'] as String?,
          steps: _parseSteps(a['steps']),
        ),
    'jira_xray_search_tickets': (a) => _client.searchTickets(
          a['searchQueryJQL'] as String,
          _parseStringList(a['fields']),
        ),
    'jira_xray_get_test_details': (a) =>
        _client.getTestDetails(a['testKey'] as String),
    'jira_xray_get_preconditions': (a) =>
        _client.getPreconditions(a['testKey'] as String),
    'jira_xray_get_precondition_details': (a) =>
        _client.getPreconditionDetails(a['preconditionKey'] as String),
    'jira_xray_add_test_step': (a) => _client.addTestStep(
          a['issueId'] as String,
          a['action'] as String,
          a['data'] as String?,
          a['result'] as String?,
        ),
    'jira_xray_add_test_steps': (a) => _client.addTestSteps(
          a['issueId'] as String,
          _parseSteps(a['steps']) ?? const [],
        ),
    'jira_xray_add_precondition_to_test': (a) => _client.addPreconditionToTest(
          a['testIssueId'] as String,
          a['preconditionIssueId'] as String,
        ),
    'jira_xray_add_preconditions_to_test': (a) =>
        _client.addPreconditionsToTest(
          a['testIssueId'] as String,
          _parseStringList(a['preconditionIssueIds']),
        ),
  };
}
