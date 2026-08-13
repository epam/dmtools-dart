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
      ..._caseWriteTools(),
      ..._resultTools(),
      ..._runTools(),
      ..._milestoneTools(),
      ..._runWriteTools(),
      ..._metadataTools(),
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

/// Case-write tools: `testrail_add_case`, `testrail_update_case`.
List<ToolDefinition> _caseWriteTools() => [
      ToolDefinition(
        name: 'testrail_add_case',
        description: 'Add a test case to a TestRail section',
        integration: 'testrail',
        category: 'test_cases',
        params: [
          ToolParam(
            name: 'sectionId',
            description: 'The section ID to add the case to',
            type: 'number',
            required: true,
          ),
          ToolParam(
            name: 'title',
            description: 'The test case title',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'testrail_update_case',
        description: 'Update a TestRail test case with new field values',
        integration: 'testrail',
        category: 'test_cases',
        params: [
          ToolParam(
            name: 'id',
            description: 'The test case ID',
            type: 'number',
            required: true,
          ),
          ToolParam(
            name: 'fields',
            description: 'Case fields to update as key-value pairs',
            type: 'object',
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

/// Run and section tools: `testrail_get_runs`, `testrail_get_sections`.
List<ToolDefinition> _runTools() => [
      ToolDefinition(
        name: 'testrail_get_runs',
        description: 'Get TestRail test runs for a project',
        integration: 'testrail',
        category: 'test_runs',
        params: [
          ToolParam(
            name: 'projectId',
            description: 'The project ID',
            type: 'number',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'testrail_get_sections',
        description: 'Get TestRail sections for a suite',
        integration: 'testrail',
        category: 'sections',
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

/// Milestone and plan tools: `testrail_get_milestones`, `testrail_get_plans`.
List<ToolDefinition> _milestoneTools() => [
      ToolDefinition(
        name: 'testrail_get_milestones',
        description: 'Get TestRail milestones for a project',
        integration: 'testrail',
        category: 'milestones',
        params: [
          ToolParam(
            name: 'projectId',
            description: 'The project ID',
            type: 'number',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'testrail_get_plans',
        description: 'Get TestRail test plans for a project',
        integration: 'testrail',
        category: 'test_plans',
        params: [
          ToolParam(
            name: 'projectId',
            description: 'The project ID',
            type: 'number',
            required: true,
          ),
        ],
      ),
    ];

/// Run-write tools: `testrail_add_run`, `testrail_update_run`.
List<ToolDefinition> _runWriteTools() => [
      ToolDefinition(
        name: 'testrail_add_run',
        description: 'Add a TestRail test run to a project',
        integration: 'testrail',
        category: 'test_runs',
        params: [
          ToolParam(
            name: 'projectId',
            description: 'The project ID',
            type: 'number',
            required: true,
          ),
          ToolParam(
            name: 'name',
            description: 'The test run name',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'testrail_update_run',
        description: 'Update a TestRail test run name',
        integration: 'testrail',
        category: 'test_runs',
        params: [
          ToolParam(
            name: 'runId',
            description: 'The test run ID',
            type: 'number',
            required: true,
          ),
          ToolParam(
            name: 'name',
            description: 'The new test run name',
            required: true,
          ),
        ],
      ),
    ];

/// Metadata tools: `testrail_get_case_types`, `testrail_get_priorities`,
/// `testrail_get_statuses`.
List<ToolDefinition> _metadataTools() => [
      ToolDefinition(
        name: 'testrail_get_case_types',
        description: 'Get TestRail case types for a project',
        integration: 'testrail',
        category: 'metadata',
        params: [
          ToolParam(
            name: 'projectId',
            description: 'The project ID',
            type: 'number',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'testrail_get_priorities',
        description: 'Get TestRail case priorities',
        integration: 'testrail',
        category: 'metadata',
        params: [],
      ),
      ToolDefinition(
        name: 'testrail_get_statuses',
        description: 'Get TestRail case statuses',
        integration: 'testrail',
        category: 'metadata',
        params: [],
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
    'testrail_get_runs': (a) => _client.getRuns(requiredInt(a, 'projectId')),
    'testrail_get_sections': (a) =>
        _client.getSections(requiredInt(a, 'suiteId')),
    'testrail_add_case': (a) => _client.addCase(
          requiredInt(a, 'sectionId'),
          a['title'] as String,
        ),
    'testrail_update_case': (a) => _client.updateCase(
          requiredInt(a, 'id'),
          a['fields'] as Map<String, dynamic>,
        ),
    'testrail_get_milestones': (a) =>
        _client.getMilestones(requiredInt(a, 'projectId')),
    'testrail_get_plans': (a) => _client.getPlans(requiredInt(a, 'projectId')),
    'testrail_add_run': (a) => _client.addRun(
          requiredInt(a, 'projectId'),
          a['name'] as String,
        ),
    'testrail_update_run': (a) => _client.updateRun(
          requiredInt(a, 'runId'),
          a['name'] as String,
        ),
    'testrail_get_case_types': (a) =>
        _client.getCaseTypes(requiredInt(a, 'projectId')),
    'testrail_get_priorities': (_) => _client.getPriorities(),
    'testrail_get_statuses': (_) => _client.getStatuses(),
  };
}
