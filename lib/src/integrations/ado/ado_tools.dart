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
      ..._pullRequestTools(),
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

/// Work-item tools: `ado_get_work_item`, `ado_create_work_item`.
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

/// Shared numeric `id` parameter with a tool-specific [description].
ToolParam _idParam(String description) => ToolParam(
      name: 'id',
      description: description,
      type: 'number',
      required: true,
    );

/// Coerces the `id` argument to an int, accepting int/num/String forms.
int _id(Map<String, dynamic> a) {
  final v = a['id'];
  return v is int ? v : int.parse('$v');
}

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
    'ado_list_prs': (a) => _client.listPrs(a['status'] as String?),
    'ado_get_pr': (a) => _client.getPr(_id(a)),
  };
}
