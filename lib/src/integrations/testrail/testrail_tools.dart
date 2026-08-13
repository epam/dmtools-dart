/// MCP tool definitions and dispatcher for the TestRail integration.
///
/// The tool list ports the TestRail subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [TestRailClient]
/// call.
library;

import '../../mcp/tool_args.dart';
import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'testrail_client.dart';

/// Returns all TestRail MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> testrailTools() => [
      ..._systemTools(),
      ..._caseTools(),
      ..._resultTools(),
    ];

/// Connectivity-check tool: `testrail_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'testrail_test',
        description: 'Test TestRail connectivity by fetching the current user',
        integration: 'testrail',
        category: 'system',
        params: [],
      ),
    ];

/// Case-read tools: `testrail_get_case`, `testrail_get_cases`.
List<ToolDefinition> _caseTools() => [
      ToolDefinition(
        name: 'testrail_get_case',
        description: 'Get a TestRail test case by ID',
        integration: 'testrail',
        category: 'test_cases',
        params: [
          ToolParam(
            name: 'id',
            description: 'The test case ID',
            type: 'number',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'testrail_get_cases',
        description: 'Get all TestRail test cases in a suite',
        integration: 'testrail',
        category: 'test_cases',
        params: [
          ToolParam(
            name: 'suiteId',
            description: 'The test suite ID',
            type: 'number',
            required: true,
          ),
        ],
      ),
    ];

/// Result tool: `testrail_add_result`.
List<ToolDefinition> _resultTools() => [
      ToolDefinition(
        name: 'testrail_add_result',
        description: 'Add a test result to a TestRail test',
        integration: 'testrail',
        category: 'test_results',
        params: [
          ToolParam(
            name: 'testId',
            description: 'The test ID',
            type: 'number',
            required: true,
          ),
          ToolParam(
            name: 'statusId',
            description: 'The test status ID (e.g. 1=Passed, 2=Blocked)',
            type: 'number',
            required: true,
          ),
          ToolParam(
            name: 'comment',
            description: 'The result comment text',
            required: true,
          ),
        ],
      ),
    ];

/// Executes TestRail MCP tools by dispatching to [TestRailClient].
class TestRailToolExecutor {
  final TestRailClient _client;

  /// Creates an executor bound to [_client].
  TestRailToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown TestRail tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown TestRail tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'testrail_test': (_) => _client.testConnection(),
    'testrail_get_case': (a) => _client.getCase(requiredInt(a, 'id')),
    'testrail_get_cases': (a) => _client.getCases(requiredInt(a, 'suiteId')),
    'testrail_add_result': (a) => _client.addResult(
          requiredInt(a, 'testId'),
          requiredInt(a, 'statusId'),
          a['comment'] as String,
        ),
  };
}
