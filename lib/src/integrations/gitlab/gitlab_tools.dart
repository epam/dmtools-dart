/// MCP tool definitions and dispatcher for the GitLab integration.
///
/// The tool list ports the GitLab subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [GitlabClient]
/// call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'gitlab_client.dart';

/// Returns all GitLab MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> gitlabTools() => [
      ..._systemTools(),
      ..._mergeRequestTools(),
      ..._issueTools(),
    ];

/// Connectivity-check tool: `gitlab_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'gitlab_test',
        description: 'Test GitLab connectivity by fetching the current user',
        integration: 'gitlab',
        category: 'system',
        params: [],
      ),
    ];

/// Merge-request tools: `gitlab_get_mr`, `gitlab_list_mrs`,
/// `gitlab_create_mr_note`.
List<ToolDefinition> _mergeRequestTools() => [
      _getMrTool(),
      _listMrsTool(),
      _createMrNoteTool(),
    ];

/// Merge-request read tool: `gitlab_get_mr`.
ToolDefinition _getMrTool() => ToolDefinition(
      name: 'gitlab_get_mr',
      description: 'Get a GitLab merge request by project and iid',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        ToolParam(
          name: 'project',
          description: 'Project id or group/project path',
          required: true,
        ),
        ToolParam(
          name: 'iid',
          description: 'The merge request internal id',
          type: 'number',
          required: true,
        ),
      ],
    );

/// Merge-request list tool: `gitlab_list_mrs`.
ToolDefinition _listMrsTool() => ToolDefinition(
      name: 'gitlab_list_mrs',
      description: 'List merge requests in a GitLab project',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        ToolParam(
          name: 'project',
          description: 'Project id or group/project path',
          required: true,
        ),
        ToolParam(
          name: 'state',
          description: 'Filter by MR state (opened, closed, merged, all)',
          required: false,
        ),
      ],
    );

/// Merge-request note tool: `gitlab_create_mr_note`.
ToolDefinition _createMrNoteTool() => ToolDefinition(
      name: 'gitlab_create_mr_note',
      description: 'Create a note (comment) on a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        ToolParam(
          name: 'project',
          description: 'Project id or group/project path',
          required: true,
        ),
        ToolParam(
          name: 'iid',
          description: 'The merge request internal id',
          type: 'number',
          required: true,
        ),
        ToolParam(
          name: 'body',
          description: 'The note body text',
          required: true,
        ),
      ],
    );

/// Issue-read tool: `gitlab_get_issue`.
List<ToolDefinition> _issueTools() => [
      ToolDefinition(
        name: 'gitlab_get_issue',
        description: 'Get a GitLab issue by project and iid',
        integration: 'gitlab',
        category: 'issues',
        params: [
          ToolParam(
            name: 'project',
            description: 'Project id or group/project path',
            required: true,
          ),
          ToolParam(
            name: 'iid',
            description: 'The issue internal id',
            type: 'number',
            required: true,
          ),
        ],
      ),
    ];

/// Parses a JSON `iid` argument into an int (accepts int or numeric string).
int _toInt(Object? value) {
  if (value is int) return value;
  return int.parse(value.toString());
}

/// Executes GitLab MCP tools by dispatching to [GitlabClient].
class GitlabToolExecutor {
  final GitlabClient _client;

  /// Creates an executor bound to [_client].
  GitlabToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown GitLab tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown GitLab tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'gitlab_test': (_) => _client.testConnection(),
    'gitlab_get_mr': (a) => _client.getMr(
          a['project'] as String,
          _toInt(a['iid']),
        ),
    'gitlab_list_mrs': (a) => _client.listMrs(
          a['project'] as String,
          a['state'] as String? ?? 'opened',
        ),
    'gitlab_create_mr_note': (a) => _client.createMrNote(
          a['project'] as String,
          _toInt(a['iid']),
          a['body'] as String,
        ),
    'gitlab_get_issue': (a) => _client.getIssue(
          a['project'] as String,
          _toInt(a['iid']),
        ),
  };
}
