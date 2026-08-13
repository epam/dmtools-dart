/// MCP tool definitions and dispatcher for the Xray integration.
///
/// The tool list ports the Xray subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [XrayClient] call.
///
/// Per Java convention, Xray tool names and the integration prefix use
/// `jira_xray` because Xray is a Jira app.
library;

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
/// `jira_xray_get_test_steps`.
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

/// Test-execution tool: `jira_xray_create_test_execution`.
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
  };
}
