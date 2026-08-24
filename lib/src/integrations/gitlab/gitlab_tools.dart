/// MCP tool definitions and dispatcher for the GitLab integration.
///
/// The tool list ports the GitLab subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [GitlabClient]
/// call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'gitlab_client.dart';
part 'gitlab_project_tools.dart';
part 'gitlab_release_tools.dart';

/// Returns all GitLab MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> gitlabTools() => [
      ..._systemTools(),
      ..._mergeRequestTools(),
      ..._agentMergeRequestTools(),
      ..._agentMrReviewTools(),
      ..._issueTools(),
      ..._repositoryTools(),
      ..._pipelineTools(),
      ..._memberTools(),
      ..._groupTools(),
      ..._projectTools(),
      ..._mrPipelineTools(),
      ..._projectHookTools(),
      ..._ciTools(),
      ..._ciPipelineTools(),
      ..._releaseTools(),
      ..._releaseAssetTools(),
    ];

/// Shared `project` param — numeric id or `group/project` path.
const ToolParam _projectParam = ToolParam(
  name: 'project',
  description: 'Project id or group/project path',
  required: true,
);

/// Shared `workspace` param — GitLab group or namespace (Java parity).
const ToolParam _workspaceParam = ToolParam(
  name: 'workspace',
  description: 'GitLab group or namespace',
  required: true,
);

/// Shared `repository` param — repository name within the workspace.
const ToolParam _repositoryParam = ToolParam(
  name: 'repository',
  description: 'Repository name',
  required: true,
);

/// Shared `pullRequestId` param — merge request IID (Java parity).
ToolParam _pullRequestIdParam() => ToolParam(
      name: 'pullRequestId',
      description: 'Merge request IID',
      required: true,
    );

/// Shared `iid` param for a numbered entity (merge request or issue).
ToolParam _iidParam(String entity) => ToolParam(
      name: 'iid',
      description: 'The $entity internal id',
      type: 'number',
      required: true,
    );

/// Shared `group_id` param — numeric id or `group/subgroup` path.
const ToolParam _groupIdParam = ToolParam(
  name: 'group_id',
  description: 'Group id or group/subgroup path',
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
/// `gitlab_get_mr_diff`, `gitlab_approve_mr`, `gitlab_unapprove_mr`,
/// `gitlab_get_mr_notes`, `gitlab_get_mr_approvals`, `gitlab_get_mr_discussions`,
/// `gitlab_trigger_mr_discussion_resolve`.
List<ToolDefinition> _mergeRequestTools() => [
      _getMrTool(),
      _listMrsTool(),
      _createMrNoteTool(),
      _mergeMrTool(),
      _closeMrTool(),
      _getMrDiffTool(),
      _approveMrTool(),
      _unapproveMrTool(),
      _getMrNotesTool(),
      _getMrApprovalsTool(),
      _getMrDiscussionsTool(),
      _triggerMrDiscussionResolveTool(),
    ];

/// Agent-facing merge-request tools ported from the Java `GitLab` client.
///
/// These take the Java `workspace`/`repository`/`pullRequestId` argument
/// names that agent scripts (js/common/scm.js) pass.
///
/// Comment tools: `gitlab_add_mr_comment`, `gitlab_get_mr_comments`,
/// `gitlab_get_mr_diff_text`, `gitlab_reply_to_mr_thread`,
/// `gitlab_resolve_mr_thread`.
/// Agent-facing merge-request tools ported from the Java `GitLab` client.
///
/// These take the Java `workspace`/`repository`/`pullRequestId` argument
/// names that agent scripts (js/common/scm.js) pass: `gitlab_add_mr_comment`,
/// `gitlab_get_mr_comments`, `gitlab_get_mr_diff_text`,
/// `gitlab_reply_to_mr_thread`, `gitlab_resolve_mr_thread`.
List<ToolDefinition> _agentMergeRequestTools() => [
      _addMrCommentTool(),
      _getMrCommentsTool(),
      _getMrDiffTextTool(),
      _replyToMrThreadTool(),
      _resolveMrThreadTool(),
    ];

/// Agent-facing merge-request review tools (continuation of
/// [_agentMergeRequestTools]; split for the method-size gate):
/// `gitlab_add_inline_mr_comment`, `gitlab_create_mr`, `gitlab_rebase_mr`,
/// `gitlab_add_mr_label`, `gitlab_remove_mr_label`.
List<ToolDefinition> _agentMrReviewTools() => [
      _addInlineMrCommentTool(),
      _createMrTool(),
      _rebaseMrTool(),
      _addMrLabelTool(),
      _removeMrLabelTool(),
    ];

/// MR comment tool: `gitlab_add_mr_comment` (Java `addPullRequestComment`).
ToolDefinition _addMrCommentTool() => ToolDefinition(
      name: 'gitlab_add_mr_comment',
      description: 'Add a general discussion comment to a GitLab merge '
          'request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(name: 'text', description: 'Comment text'),
      ],
    );

/// MR comments tool: `gitlab_get_mr_comments` (Java `pullRequestComments`).
ToolDefinition _getMrCommentsTool() => ToolDefinition(
      name: 'gitlab_get_mr_comments',
      description: 'Get all comments for a GitLab merge request, including '
          'inline code review comments and general discussion notes; '
          'system-generated notes are excluded',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_workspaceParam, _repositoryParam, _pullRequestIdParam()],
    );

/// MR diff-text tool: `gitlab_get_mr_diff_text` (Java
/// `getPullRequestDiffText`).
ToolDefinition _getMrDiffTextTool() => ToolDefinition(
      name: 'gitlab_get_mr_diff_text',
      description: 'Get the raw unified diff text for a GitLab merge request '
          '(suitable for locating file/line positions for inline review '
          'comments)',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_workspaceParam, _repositoryParam, _pullRequestIdParam()],
    );

/// MR thread-reply tool: `gitlab_reply_to_mr_thread` (Java
/// `replyToPullRequestComment`).
ToolDefinition _replyToMrThreadTool() => ToolDefinition(
      name: 'gitlab_reply_to_mr_thread',
      description: 'Reply to an existing discussion thread in a GitLab merge '
          'request; use the discussion id from gitlab_get_mr_discussions',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(
          name: 'discussionId',
          description: 'Discussion thread ID',
          aliases: ['threadId'],
        ),
        ToolParam(name: 'text', description: 'Reply text'),
      ],
    );

/// MR thread-resolve tool: `gitlab_resolve_mr_thread` (Java
/// `resolveReviewThread`).
ToolDefinition _resolveMrThreadTool() => ToolDefinition(
      name: 'gitlab_resolve_mr_thread',
      description: 'Resolve (close) a review discussion thread in a GitLab '
          'merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(
          name: 'discussionId',
          description: 'Discussion thread ID to resolve',
          aliases: ['threadId'],
        ),
      ],
    );

/// MR inline-comment tool: `gitlab_add_inline_mr_comment` (Java
/// `addInlineReviewComment`).
ToolDefinition _addInlineMrCommentTool() => ToolDefinition(
      name: 'gitlab_add_inline_mr_comment',
      description: 'Create an inline code review comment on a specific file '
          'and line in a GitLab merge request; requires the base, head, and '
          'start SHAs from the MR diff refs',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(
          name: 'filePath',
          description: 'Path to the file to comment on',
        ),
        ToolParam(
          name: 'line',
          description: 'Line number in the new file to comment on',
          type: 'number',
        ),
        ToolParam(name: 'text', description: 'Comment text'),
        ToolParam(
            name: 'baseSha',
            description: 'Base commit SHA from MR '
                'diff refs'),
        ToolParam(
            name: 'headSha',
            description: 'Head commit SHA from MR '
                'diff refs'),
        ToolParam(
            name: 'startSha',
            description: 'Start commit SHA from MR '
                'diff refs'),
      ],
    );

/// MR create tool: `gitlab_create_mr` (Java `createMergeRequest`).
ToolDefinition _createMrTool() => ToolDefinition(
      name: 'gitlab_create_mr',
      description: 'Create a GitLab merge request from a source branch into '
          'a target branch',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        ToolParam(name: 'sourceBranch', description: 'Source branch name'),
        ToolParam(name: 'targetBranch', description: 'Target branch name'),
        ToolParam(name: 'title', description: 'Merge request title'),
        ToolParam(
          name: 'description',
          description: 'Merge request description',
          required: false,
        ),
        ToolParam(
          name: 'removeSourceBranch',
          description: 'Remove source branch after merge',
          type: 'boolean',
          required: false,
        ),
      ],
    );

/// MR rebase tool: `gitlab_rebase_mr` (Java `rebaseMergeRequest`).
ToolDefinition _rebaseMrTool() => ToolDefinition(
      name: 'gitlab_rebase_mr',
      description: 'Ask GitLab to rebase a merge request source branch with '
          'its target branch',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_workspaceParam, _repositoryParam, _pullRequestIdParam()],
    );

/// MR add-label tool: `gitlab_add_mr_label` (Java `addPullRequestLabel`).
ToolDefinition _addMrLabelTool() => ToolDefinition(
      name: 'gitlab_add_mr_label',
      description: 'Add a label to a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(name: 'label', description: 'Label to add'),
      ],
    );

/// MR remove-label tool: `gitlab_remove_mr_label` (Java
/// `removePullRequestLabel`).
ToolDefinition _removeMrLabelTool() => ToolDefinition(
      name: 'gitlab_remove_mr_label',
      description: 'Remove a label from a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _workspaceParam,
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(name: 'label', description: 'Label to remove'),
      ],
    );

/// Issue tools: `gitlab_get_issue`, `gitlab_create_issue`,
/// `gitlab_list_issues`.
List<ToolDefinition> _issueTools() => [
      _getIssueTool(),
      _createIssueTool(),
      _listIssuesTool(),
    ];

/// Repository tools: `gitlab_create_branch`, `gitlab_get_file_content`,
/// `gitlab_create_tag`, `gitlab_get_tags`, `gitlab_get_branches`.
List<ToolDefinition> _repositoryTools() => [
      _createBranchTool(),
      _getFileContentTool(),
      _createTagTool(),
      _getTagsTool(),
      _getBranchesTool(),
    ];

/// Pipeline tools: `gitlab_get_pipelines`, `gitlab_trigger_pipeline`,
/// `gitlab_get_pipeline`.
List<ToolDefinition> _pipelineTools() => [
      _getPipelinesTool(),
      _triggerPipelineTool(),
      _getPipelineTool(),
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

/// Group-member tools: `gitlab_get_group_members`.
List<ToolDefinition> _groupTools() => [
      ToolDefinition(
        name: 'gitlab_get_group_members',
        description: 'List the members of a GitLab group',
        integration: 'gitlab',
        category: 'members',
        params: [_groupIdParam],
      ),
    ];

/// CI tools ported from the Java `GitLab` client (category `ci`) —
/// statuses and job logs: `gitlab_get_commit_statuses`,
/// `gitlab_get_job_logs`.
List<ToolDefinition> _ciTools() => [
      ToolDefinition(
        name: 'gitlab_get_commit_statuses',
        description: 'Get CI/CD statuses for a commit SHA in a GitLab '
            'project; when the same status name was reported more than once '
            'for the commit, only the most recent report per name is '
            'returned',
        integration: 'gitlab',
        category: 'ci',
        params: [
          _workspaceParam,
          _repositoryParam,
          ToolParam(
            name: 'commitSha',
            description: 'The commit SHA to get statuses for',
          ),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_get_job_logs',
        description: 'Get GitLab CI job trace logs',
        integration: 'gitlab',
        category: 'ci',
        params: [
          _workspaceParam,
          _repositoryParam,
          ToolParam(
              name: 'jobId', description: 'GitLab job ID', type: 'number'),
        ],
      ),
    ];

/// CI pipeline tool ported from the Java `GitLab` client (category `ci`):
/// `gitlab_list_pipeline_runs`. (`gitlab_trigger_pipeline` already exists
/// in the pipeline group above.)
List<ToolDefinition> _ciPipelineTools() => [
      ToolDefinition(
        name: 'gitlab_list_pipeline_runs',
        description: 'List recent GitLab CI pipelines, optionally filtered '
            'by status, ref, and limit',
        integration: 'gitlab',
        category: 'ci',
        params: [
          _workspaceParam,
          _repositoryParam,
          ToolParam(
            name: 'status',
            description: 'Pipeline status filter',
            required: false,
          ),
          ToolParam(
            name: 'ref',
            description: 'Branch or tag ref',
            required: false,
          ),
          ToolParam(
            name: 'limit',
            description: 'Maximum number of pipelines to return',
            type: 'number',
            required: false,
          ),
        ],
      ),
    ];

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
    ..._systemHandlers(),
    ..._mergeRequestHandlers(),
    ..._issueHandlers(),
    ..._repositoryHandlers(),
    ..._pipelineHandlers(),
    ..._memberHandlers(),
    ..._projectHandlers(),
    ..._mrPipelineHandlers(),
    ..._projectHookHandlers(),
  };

  /// Connectivity-check handler.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _systemHandlers() => {
            'gitlab_test': (_) => _client.testConnection(),
          };

  /// Merge-request tool handlers.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _mergeRequestHandlers() => {
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
            'gitlab_approve_mr': (a) => _client.approveMr(
                  a['project'] as String,
                  _toInt(a['iid']),
                ),
            'gitlab_unapprove_mr': (a) => _client.unapproveMr(
                  a['project'] as String,
                  _toInt(a['iid']),
                ),
            'gitlab_get_mr_notes': (a) => _client.getMrNotes(
                  a['project'] as String,
                  _toInt(a['iid']),
                ),
            'gitlab_get_mr_approvals': (a) => _client.getMrApprovals(
                  a['project'] as String,
                  _toInt(a['iid']),
                ),
            'gitlab_get_mr_discussions': (a) => _client.getMrDiscussions(
                  a['project'] as String,
                  _toInt(a['iid']),
                ),
            'gitlab_trigger_mr_discussion_resolve': (a) =>
                _client.triggerMrDiscussionResolve(
                  a['project'] as String,
                  _toInt(a['iid']),
                  a['discussion_id'] as String,
                  _toBool(a['resolved']),
                ),
          };

  /// Issue tool handlers.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _issueHandlers() => {
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
          };

  /// Repository tool handlers.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _repositoryHandlers() => {
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
            'gitlab_create_tag': (a) => _client.createTag(
                  a['project'] as String,
                  a['tag_name'] as String,
                  a['ref'] as String,
                ),
            'gitlab_get_tags': (a) => _client.getTags(a['project'] as String),
            'gitlab_get_branches': (a) =>
                _client.getBranches(a['project'] as String),
          };

  /// Pipeline tool handlers.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _pipelineHandlers() => {
            'gitlab_get_pipelines': (a) =>
                _client.getPipelines(a['project'] as String),
            'gitlab_trigger_pipeline': (a) => _client.triggerPipeline(
                  a['project'] as String,
                  a['ref'] as String,
                ),
            'gitlab_get_pipeline': (a) => _client.getPipeline(
                  a['project'] as String,
                  _toInt(a['pipeline_id']),
                ),
          };

  /// Member tool handlers (project and group scopes).
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _memberHandlers() => {
            'gitlab_get_project_members': (a) =>
                _client.getProjectMembers(a['project'] as String),
            'gitlab_get_group_members': (a) =>
                _client.getGroupMembers(a['group_id'] as String),
          };

  /// Project tool handlers.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _projectHandlers() => {
            'gitlab_get_project_details': (a) =>
                _client.getProjectDetails(a['project'] as String),
            'gitlab_get_project_variables': (a) =>
                _client.getProjectVariables(a['project'] as String),
          };

  /// Merge-request pipeline handler.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _mrPipelineHandlers() => {
            'gitlab_get_mr_pipelines': (a) => _client.getMrPipelines(
                  a['project'] as String,
                  _toInt(a['iid']),
                ),
          };

  /// Project webhook handlers.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _projectHookHandlers() => {
            'gitlab_get_project_hooks': (a) =>
                _client.getProjectHooks(a['project'] as String),
            'gitlab_add_project_hook': (a) => _client.addProjectHook(
                  a['project'] as String,
                  a['url'] as String,
                ),
          };
}
