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
      ..._repositoryTools(),
      ..._memberTools(),
    ];

/// Shared `project` param — numeric id or `group/project` path.
const ToolParam _projectParam = ToolParam(
  name: 'project',
  description: 'Project id or group/project path',
  required: true,
);

/// Shared `iid` param for a numbered entity (merge request or issue).
ToolParam _iidParam(String entity) => ToolParam(
      name: 'iid',
      description: 'The $entity internal id',
      type: 'number',
      required: true,
    );

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
/// `gitlab_create_mr_note`, `gitlab_merge_mr`, `gitlab_close_mr`,
/// `gitlab_get_mr_diff`.
List<ToolDefinition> _mergeRequestTools() => [
      _getMrTool(),
      _listMrsTool(),
      _createMrNoteTool(),
      _mergeMrTool(),
      _closeMrTool(),
      _getMrDiffTool(),
    ];

/// Issue tools: `gitlab_get_issue`, `gitlab_create_issue`,
/// `gitlab_list_issues`.
List<ToolDefinition> _issueTools() => [
      _getIssueTool(),
      _createIssueTool(),
      _listIssuesTool(),
    ];

/// Repository tools: `gitlab_create_branch`, `gitlab_get_file_content`.
List<ToolDefinition> _repositoryTools() => [
      _createBranchTool(),
      _getFileContentTool(),
    ];

/// Project-member tools: `gitlab_get_project_members`.
List<ToolDefinition> _memberTools() => [
      ToolDefinition(
        name: 'gitlab_get_project_members',
        description: 'List the members of a GitLab project',
        integration: 'gitlab',
        category: 'members',
        params: [_projectParam],
      ),
    ];

/// Merge-request read tool: `gitlab_get_mr`.
ToolDefinition _getMrTool() => ToolDefinition(
      name: 'gitlab_get_mr',
      description: 'Get a GitLab merge request by project and iid',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request list tool: `gitlab_list_mrs`.
ToolDefinition _listMrsTool() => ToolDefinition(
      name: 'gitlab_list_mrs',
      description: 'List merge requests in a GitLab project',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _projectParam,
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
        _projectParam,
        _iidParam('merge request'),
        ToolParam(
          name: 'body',
          description: 'The note body text',
          required: true,
        ),
      ],
    );

/// Merge-request merge tool: `gitlab_merge_mr`.
ToolDefinition _mergeMrTool() => ToolDefinition(
      name: 'gitlab_merge_mr',
      description: 'Merge a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request close tool: `gitlab_close_mr`.
ToolDefinition _closeMrTool() => ToolDefinition(
      name: 'gitlab_close_mr',
      description: 'Close a GitLab merge request without merging',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request diff tool: `gitlab_get_mr_diff`.
ToolDefinition _getMrDiffTool() => ToolDefinition(
      name: 'gitlab_get_mr_diff',
      description: 'Get the diffs (changes) of a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Issue-read tool: `gitlab_get_issue`.
ToolDefinition _getIssueTool() => ToolDefinition(
      name: 'gitlab_get_issue',
      description: 'Get a GitLab issue by project and iid',
      integration: 'gitlab',
      category: 'issues',
      params: [_projectParam, _iidParam('issue')],
    );

/// Issue-create tool: `gitlab_create_issue`.
ToolDefinition _createIssueTool() => ToolDefinition(
      name: 'gitlab_create_issue',
      description: 'Create an issue in a GitLab project',
      integration: 'gitlab',
      category: 'issues',
      params: [
        _projectParam,
        ToolParam(
          name: 'title',
          description: 'The issue title',
          required: true,
        ),
        ToolParam(
          name: 'description',
          description: 'The issue description',
          required: false,
        ),
      ],
    );

/// Issue-list tool: `gitlab_list_issues`.
ToolDefinition _listIssuesTool() => ToolDefinition(
      name: 'gitlab_list_issues',
      description: 'List issues in a GitLab project',
      integration: 'gitlab',
      category: 'issues',
      params: [
        _projectParam,
        ToolParam(
          name: 'state',
          description: 'Filter by issue state (opened, closed, all)',
          required: false,
        ),
      ],
    );

/// Branch-create tool: `gitlab_create_branch`.
ToolDefinition _createBranchTool() => ToolDefinition(
      name: 'gitlab_create_branch',
      description: 'Create a branch in a GitLab project repository',
      integration: 'gitlab',
      category: 'repository',
      params: [
        _projectParam,
        ToolParam(
          name: 'branch',
          description: 'The name of the branch to create',
          required: true,
        ),
        ToolParam(
          name: 'ref',
          description: 'The branch, tag, or commit to create the branch from',
          required: true,
        ),
      ],
    );

/// File-content tool: `gitlab_get_file_content`.
ToolDefinition _getFileContentTool() => ToolDefinition(
      name: 'gitlab_get_file_content',
      description: 'Get the contents of a file in a GitLab project repository',
      integration: 'gitlab',
      category: 'repository',
      params: [
        _projectParam,
        ToolParam(
          name: 'file_path',
          description: 'The path of the file inside the repository',
          required: true,
        ),
        ToolParam(
          name: 'ref',
          description: 'The name of branch, tag or commit to read from',
          required: false,
        ),
      ],
    );

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
    'gitlab_merge_mr': (a) => _client.mergeMr(
          a['project'] as String,
          _toInt(a['iid']),
        ),
    'gitlab_close_mr': (a) => _client.closeMr(
          a['project'] as String,
          _toInt(a['iid']),
        ),
    'gitlab_get_mr_diff': (a) => _client.getMrDiff(
          a['project'] as String,
          _toInt(a['iid']),
        ),
    'gitlab_get_issue': (a) => _client.getIssue(
          a['project'] as String,
          _toInt(a['iid']),
        ),
    'gitlab_create_issue': (a) => _client.createIssue(
          a['project'] as String,
          a['title'] as String,
          a['description'] as String?,
        ),
    'gitlab_list_issues': (a) => _client.listIssues(
          a['project'] as String,
          a['state'] as String? ?? 'opened',
        ),
    'gitlab_create_branch': (a) => _client.createBranch(
          a['project'] as String,
          a['branch'] as String,
          a['ref'] as String,
        ),
    'gitlab_get_file_content': (a) => _client.getFileContent(
          a['project'] as String,
          a['file_path'] as String,
          a['ref'] as String?,
        ),
    'gitlab_get_project_members': (a) =>
        _client.getProjectMembers(a['project'] as String),
  };
}
