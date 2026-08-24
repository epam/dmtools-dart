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
      ..._caseCreateTools(),
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

/// Case-write tools: `testrail_add_case`, `testrail_update_case`,
/// `testrail_delete_case`.
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
      ToolDefinition(
        name: 'testrail_delete_case',
        description: 'Delete a TestRail test case by ID',
        integration: 'testrail',
        category: 'test_cases',
        params: [
          ToolParam(
            name: 'id',
            description: 'The test case ID to delete',
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
        description: 'Get all test sections for a TestRail project and '
            'optional suite. Sections define the hierarchy used to organize '
            'test cases.',
        integration: 'testrail',
        category: 'sections',
        params: [
          ToolParam(
            name: 'project_name',
            description: 'Project name to get sections from',
            required: true,
          ),
          ToolParam(
            name: 'suite_id',
            description: 'Suite ID to filter by (optional). Required for '
                'projects with multiple suites.',
            required: false,
          ),
        ],
      ),
    ];

/// Section-aware case-creation tools: `testrail_create_case`,
/// `testrail_create_case_detailed`, `testrail_create_case_steps`.
///
/// Ports the Java PR "testrail-sections-and-section-aware-case-creation":
/// every tool takes an optional `section_id` and falls back to the project's
/// default section when it is omitted.
List<ToolDefinition> _caseCreateTools() => [
      _createCaseTool(),
      _createCaseDetailedTool(),
      _createCaseStepsTool(),
    ];

/// `testrail_create_case` — the basic case-creation tool.
ToolDefinition _createCaseTool() => ToolDefinition(
      name: 'testrail_create_case',
      description: 'Create a new test case in TestRail',
      integration: 'testrail',
      category: 'test_cases',
      params: [
        _projectNameParam(),
        _titleParam(),
        ToolParam(
          name: 'description',
          description: 'Test case description/steps (optional)',
          required: false,
        ),
        _priorityIdParam(),
        _refsParam(),
        _sectionIdParam(),
      ],
    );

/// `testrail_create_case_detailed` — text-template case with full fields.
ToolDefinition _createCaseDetailedTool() => ToolDefinition(
      name: 'testrail_create_case_detailed',
      description: 'Create a new test case in TestRail with detailed fields '
          '(preconditions, steps, expected results, labels, type). Note: '
          'TestRail uses its own table format in text fields: '
          '|||:Col 1|:Col 2|:Col 3\\n||val1|val2|val3. Standard Markdown '
          'tables (| Col | Col |) will be auto-converted to TestRail format.',
      integration: 'testrail',
      category: 'test_cases',
      params: [
        _projectNameParam(),
        _titleParam(),
        ToolParam(
          name: 'preconditions',
          description: 'Preconditions (optional). For tables use TestRail '
              'format: |||:Col1|:Col2\\n||val1|val2',
          required: false,
        ),
        ToolParam(
          name: 'steps',
          description: 'Test steps separated by double newline (optional)',
          required: false,
        ),
        ToolParam(
          name: 'expected',
          description: 'Expected results (optional)',
          required: false,
        ),
        ..._caseMetaParams(),
        _sectionIdParam(),
      ],
    );

/// `testrail_create_case_steps` — Steps-template (template_id=2) case.
ToolDefinition _createCaseStepsTool() => ToolDefinition(
      name: 'testrail_create_case_steps',
      description: "Create a TestRail test case using the 'Test Case "
          "(Steps)' template (template_id=2). Steps are provided as a JSON "
          'array: [{"content":"step text","expected":"expected result"}, '
          '...]. Markdown tables in step content or expected are '
          'auto-converted to HTML tables. Use testrail_get_case_types for '
          'type_id, testrail_get_labels for label_ids.',
      integration: 'testrail',
      category: 'test_cases',
      params: [
        _projectNameParam(),
        _titleParam(),
        ToolParam(
          name: 'preconditions',
          description: 'Preconditions text (optional)',
          required: false,
        ),
        ToolParam(
          name: 'steps_json',
          description: 'JSON array of step objects: '
              '[{"content":"step","expected":"result"}, ...]. Markdown '
              'tables are auto-converted to HTML.',
          required: true,
        ),
        ..._caseMetaParams(),
        _sectionIdParam(),
      ],
    );

/// The optional `section_id` parameter shared by the case-creation tools.
ToolParam _sectionIdParam() => ToolParam(
      name: 'section_id',
      description: 'Section ID where the case should be created (optional). '
          "Uses the project's default section when omitted.",
      required: false,
    );

/// The `project_name` parameter shared by the case-creation tools.
ToolParam _projectNameParam() => ToolParam(
      name: 'project_name',
      description: 'Project name',
      required: true,
    );

/// The `title` parameter shared by the case-creation tools.
ToolParam _titleParam() => ToolParam(
      name: 'title',
      description: 'Test case title/summary',
      required: true,
    );

/// The `priority_id` parameter shared by the case-creation tools.
ToolParam _priorityIdParam() => ToolParam(
      name: 'priority_id',
      description:
          'Priority ID: 1=Low, 2=Medium, 3=High, 4=Critical (optional, '
          'default=2)',
      required: false,
    );

/// The `type_id` parameter shared by the case-creation tools.
ToolParam _typeIdParam() => ToolParam(
      name: 'type_id',
      description: 'Case type ID (optional). Use testrail_get_case_types to '
          'get available types.',
      required: false,
    );

/// The `refs` parameter shared by the case-creation tools.
ToolParam _refsParam() => ToolParam(
      name: 'refs',
      description: 'Reference to requirement (e.g., JIRA key)',
      required: false,
    );

/// The `label_ids` parameter shared by the case-creation tools.
ToolParam _labelIdsParam() => ToolParam(
      name: 'label_ids',
      description: 'Comma-separated label IDs (optional). Use '
          'testrail_get_labels to find IDs.',
      required: false,
    );

/// The priority/type/refs/labels tail shared by the detailed and steps
/// create tools.
List<ToolParam> _caseMetaParams() => [
      _priorityIdParam(),
      _typeIdParam(),
      _refsParam(),
      _labelIdsParam(),
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
/// `testrail_get_statuses`, `testrail_get_references`, `testrail_get_templates`.
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
      ToolDefinition(
        name: 'testrail_get_references',
        description: 'Get TestRail references for a project',
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
        name: 'testrail_get_templates',
        description: 'Get TestRail templates',
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
    'testrail_get_sections': (a) => _client.getSectionsByProjectName(
          requiredString(a, 'project_name'),
          suiteId: _optionalString(a, 'suite_id'),
        ),
    'testrail_create_case': (a) => _client.createCase(
          requiredString(a, 'project_name'),
          requiredString(a, 'title'),
          description: _optionalString(a, 'description'),
          priorityId: _optionalString(a, 'priority_id'),
          refs: _optionalString(a, 'refs'),
          sectionId: _optionalString(a, 'section_id'),
        ),
    'testrail_create_case_detailed': (a) => _client.createCaseDetailed(
          requiredString(a, 'project_name'),
          requiredString(a, 'title'),
          preconditions: _optionalString(a, 'preconditions'),
          steps: _optionalString(a, 'steps'),
          expected: _optionalString(a, 'expected'),
          priorityId: _optionalString(a, 'priority_id'),
          typeId: _optionalString(a, 'type_id'),
          refs: _optionalString(a, 'refs'),
          labelIds: _optionalString(a, 'label_ids'),
          sectionId: _optionalString(a, 'section_id'),
        ),
    'testrail_create_case_steps': (a) => _client.createCaseSteps(
          requiredString(a, 'project_name'),
          requiredString(a, 'title'),
          preconditions: _optionalString(a, 'preconditions'),
          stepsJson: requiredString(a, 'steps_json'),
          priorityId: _optionalString(a, 'priority_id'),
          typeId: _optionalString(a, 'type_id'),
          refs: _optionalString(a, 'refs'),
          labelIds: _optionalString(a, 'label_ids'),
          sectionId: _optionalString(a, 'section_id'),
        ),
    'testrail_add_case': (a) => _client.addCase(
          requiredInt(a, 'sectionId'),
          a['title'] as String,
        ),
    'testrail_update_case': (a) => _client.updateCase(
          requiredInt(a, 'id'),
          a['fields'] as Map<String, dynamic>,
        ),
    'testrail_delete_case': (a) => _client.deleteCase(requiredInt(a, 'id')),
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
    'testrail_get_references': (a) =>
        _client.getReferences(requiredInt(a, 'projectId')),
    'testrail_get_templates': (_) => _client.getTemplates(),
  };
}

/// Reads a required string argument, rejecting null and non-strings.
String requiredString(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is String && value.isNotEmpty) return value;
  throw ArgumentError('Missing required parameter: $key');
}

/// Reads an optional string argument; `null` when absent.
String? _optionalString(Map<String, dynamic> args, String key) {
  final value = args[key];
  return value is String ? value : null;
}
