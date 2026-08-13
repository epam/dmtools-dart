/// MCP tool definitions and dispatcher for the Azure DevOps integration.
///
/// The tool list ports the ADO subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [AdoClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'ado_client.dart';

/// Returns all Azure DevOps MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> adoTools() => [
      ..._systemTools(),
      ..._workItemTools(),
      ..._workItemQueryTools(),
      ..._pullRequestTools(),
      ..._repoTools(),
      ..._buildTools(),
    ];

/// Connectivity-check tool: `ado_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'ado_test',
        description: 'Test Azure DevOps connectivity via the connection-data '
            'endpoint',
        integration: 'ado',
        category: 'system',
        params: [],
      ),
    ];

/// Work-item tools: get/create/update work items.
List<ToolDefinition> _workItemTools() => [
      ToolDefinition(
        name: 'ado_get_work_item',
        description: 'Get an Azure DevOps work item by ID',
        integration: 'ado',
        category: 'work_item_management',
        params: [_idParam('The work item ID')],
      ),
      ToolDefinition(
        name: 'ado_create_work_item',
        description: 'Create a new Azure DevOps work item',
        integration: 'ado',
        category: 'work_item_management',
        params: [
          ToolParam(
            name: 'type',
            description: 'The work item type (Bug, Task, User Story, etc.)',
            required: true,
          ),
          ToolParam(
            name: 'title',
            description: 'The work item title',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'ado_update_work_item',
        description: 'Update an Azure DevOps work item by setting fields',
        integration: 'ado',
        category: 'work_item_management',
        params: [
          _idParam('The work item ID to update'),
          ToolParam(
            name: 'fields',
            description: 'Map of field path to value, e.g. '
                '{"System.Title": "New title"}',
            type: 'object',
          ),
        ],
      ),
    ];

/// Work-item query tools: batch fetch, WIQL queries, and work-item types.
List<ToolDefinition> _workItemQueryTools() => [
      ToolDefinition(
        name: 'ado_get_work_items',
        description: 'Get multiple Azure DevOps work items by ID',
        integration: 'ado',
        category: 'work_item_management',
        params: [
          ToolParam(
            name: 'ids',
            description: 'The work item IDs to fetch',
            type: 'array',
          ),
        ],
      ),
      ToolDefinition(
        name: 'ado_list_work_items',
        description: 'Run a WIQL query to list Azure DevOps work items',
        integration: 'ado',
        category: 'work_item_management',
        params: [
          ToolParam(name: 'wiql', description: 'The WIQL query string'),
        ],
      ),
      ToolDefinition(
        name: 'ado_get_work_item_types',
        description: 'List the work item types defined in a project',
        integration: 'ado',
        category: 'work_item_management',
        params: [_projectParam()],
      ),
    ];

/// Pull-request tools: `ado_list_prs`, `ado_get_pr`.
List<ToolDefinition> _pullRequestTools() => [
      ToolDefinition(
        name: 'ado_list_prs',
        description: 'List Azure DevOps pull requests in a project',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          ToolParam(
            name: 'status',
            description:
                'PR status filter: active, abandoned, completed, or all',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'ado_get_pr',
        description: 'Get an Azure DevOps pull request by ID',
        integration: 'ado',
        category: 'pull_requests',
        params: [_idParam('The pull request ID')],
      ),
    ];

/// Repository tools: `ado_create_repo`, `ado_get_repos`.
List<ToolDefinition> _repoTools() => [
      ToolDefinition(
        name: 'ado_create_repo',
        description: 'Create a Git repository in an Azure DevOps project',
        integration: 'ado',
        category: 'repositories',
        params: [
          _projectParam(),
          ToolParam(name: 'name', description: 'The repository name'),
        ],
      ),
      ToolDefinition(
        name: 'ado_get_repos',
        description: 'List Git repositories in an Azure DevOps project',
        integration: 'ado',
        category: 'repositories',
        params: [_projectParam()],
      ),
    ];

/// Build tools: `ado_get_builds`, `ado_trigger_build`.
List<ToolDefinition> _buildTools() => [
      ToolDefinition(
        name: 'ado_get_builds',
        description: 'List Azure DevOps pipeline builds, optionally filtered',
        integration: 'ado',
        category: 'builds',
        params: [
          _projectParam(),
          ToolParam(
            name: 'definitions',
            description: 'Optional definition IDs to filter by',
            type: 'array',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'ado_trigger_build',
        description: 'Queue an Azure DevOps pipeline build by definition ID',
        integration: 'ado',
        category: 'builds',
        params: [
          ToolParam(
            name: 'definitionId',
            description: 'The pipeline definition ID to queue',
            type: 'number',
          ),
        ],
      ),
    ];

/// Shared numeric `id` parameter with a tool-specific [description].
ToolParam _idParam(String description) => ToolParam(
      name: 'id',
      description: description,
      type: 'number',
      required: true,
    );

/// Shared `project` parameter naming the target Azure DevOps project.
ToolParam _projectParam() => ToolParam(
      name: 'project',
      description: 'The Azure DevOps project name',
    );

/// Coerces the `id` argument to an int, accepting int/num/String forms.
int _id(Map<String, dynamic> a) => _num(a, 'id');

/// Coerces the numeric arg [key] in [a] to an int, accepting int/num/String.
int _num(Map<String, dynamic> a, String key) {
  final v = a[key];
  return v is int ? v : int.parse('$v');
}

/// Coerces the array arg [key] in [a] to a list of ints.
List<int> _intList(Map<String, dynamic> a, String key) => [
      for (final v in a[key] as List) v is int ? v : int.parse('$v'),
    ];

/// Executes Azure DevOps MCP tools by dispatching to [AdoClient].
class AdoToolExecutor {
  final AdoClient _client;

  /// Creates an executor bound to [_client].
  AdoToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown ADO tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown ADO tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'ado_test': (_) => _client.testConnection(),
    'ado_get_work_item': (a) => _client.getWorkItem(_id(a)),
    'ado_create_work_item': (a) => _client.createWorkItem(
          a['type'] as String,
          a['title'] as String,
        ),
    'ado_update_work_item': (a) => _client.updateWorkItem(
          _id(a),
          a['fields'] as Map<String, dynamic>,
        ),
    'ado_get_work_items': (a) => _client.getWorkItems(_intList(a, 'ids')),
    'ado_list_work_items': (a) => _client.listWorkItems(a['wiql'] as String),
    'ado_get_work_item_types': (a) =>
        _client.getWorkItemTypes(a['project'] as String),
    'ado_list_prs': (a) => _client.listPrs(a['status'] as String?),
    'ado_get_pr': (a) => _client.getPr(_id(a)),
    'ado_create_repo': (a) => _client.createRepo(
          a['project'] as String,
          a['name'] as String,
        ),
    'ado_get_repos': (a) => _client.getRepos(a['project'] as String),
    'ado_get_builds': (a) => _client.getBuilds(
          a['project'] as String,
          a['definitions'] == null ? null : _intList(a, 'definitions'),
        ),
    'ado_trigger_build': (a) => _client.triggerBuild(_num(a, 'definitionId')),
  };
}
