/// Issue-tracker tool catalog and executor routes — Java `GitLabIssues.java`
/// (dm.ai #876) parity.
///
/// The GitLab issue family accepts explicit `workspace`/`repository`/
/// `issueNumber` parts, the legacy `project`/`iid` pair on `gitlab_get_issue`
/// and `gitlab_create_issue`, a composite `key` (`namespace/project#123`,
/// `gl-123`, or a bare IID resolved against the configured
/// `GITLAB_WORKSPACE`/`GITLAB_REPOSITORY` defaults), and the Java `tracker_*`
/// alias set so GitLab can serve as the tracker backend
/// (`DEFAULT_TRACKER=gitlab`).
part of 'gitlab_tools.dart';

/// Issue tools: tracker-critical CRUD plus the search/move/assign/reopen/
/// label/comment tracker layer (Java `GitLabIssues.java` parity).
List<ToolDefinition> _issueTrackerTools() => [
      ..._glIssueMutationTools(),
      ..._glIssueCommentTools(),
    ];

/// `gitlab_search_issues`, `gitlab_close_issue`, `gitlab_reopen_issue`,
/// `gitlab_move_issue_to_status`, `gitlab_assign_issue`,
/// `gitlab_add_issue_label`, `gitlab_remove_issue_label`.
List<ToolDefinition> _glIssueMutationTools() => [
      _searchIssuesTool(),
      _closeIssueTool(),
      _reopenIssueTool(),
      _moveIssueToStatusTool(),
      _assignIssueTool(),
      _addIssueLabelTool(),
      _removeIssueLabelTool(),
    ];

/// `gitlab_create_issue_comment` + `gitlab_get_issue_comments`.
List<ToolDefinition> _glIssueCommentTools() => [
      _createIssueCommentTool(),
      _getIssueCommentsTool(),
    ];

/// `gitlab_search_issues` (Java `GitLabIssues.searchIssues`).
ToolDefinition _searchIssuesTool() => ToolDefinition(
      name: 'gitlab_search_issues',
      aliases: ['tracker_search'],
      description: 'Search GitLab issues of a project with a query string '
          'matched against title and description. Returns a JSON array of '
          'issues.',
      integration: 'gitlab',
      category: 'issues',
      params: [
        const ToolParam(
          name: 'query',
          description: 'Text matched against issue title and description',
          required: true,
          aliases: ['jql', 'wiql'],
        ),
        _glOptionalWorkspace(),
        _glOptionalRepository(),
        const ToolParam(
          name: 'state',
          description: 'Issue state filter: opened, closed, all (default: all)',
          required: false,
        ),
      ],
    );

/// `gitlab_close_issue` (Java `GitLabIssues.closeIssue`).
ToolDefinition _closeIssueTool() => ToolDefinition(
      name: 'gitlab_close_issue',
      description: 'Close a GitLab issue',
      integration: 'gitlab',
      category: 'issues',
      params: _glIssueRefParams(),
    );

/// `gitlab_reopen_issue` (Java `GitLabIssues.reopenIssue`).
ToolDefinition _reopenIssueTool() => ToolDefinition(
      name: 'gitlab_reopen_issue',
      description: 'Reopen a closed GitLab issue',
      integration: 'gitlab',
      category: 'issues',
      params: _glIssueRefParams(),
    );

/// `gitlab_move_issue_to_status` (Java `GitLabIssues.moveIssueToStatus`).
ToolDefinition _moveIssueToStatusTool() => ToolDefinition(
      name: 'gitlab_move_issue_to_status',
      aliases: ['tracker_move_to_status'],
      description: 'Move a GitLab issue to a status. '
          "'done'/'closed'/'completed'/'resolved' close the issue, "
          "'open'/'reopened' reopen it; any other status is applied as a "
          "scoped 'status::<status>' label.",
      integration: 'gitlab',
      category: 'issues',
      params: [
        const ToolParam(
          name: 'statusName',
          description: 'The target status name',
          required: true,
          aliases: ['state', 'status'],
        ),
        ..._glIssueRefParams(),
      ],
    );

/// `gitlab_assign_issue` (Java `GitLabIssues.assignIssue`).
ToolDefinition _assignIssueTool() => ToolDefinition(
      name: 'gitlab_assign_issue',
      aliases: ['tracker_assign_ticket', 'tracker_assign'],
      description: 'Assign a GitLab issue to a user by username',
      integration: 'gitlab',
      category: 'issues',
      params: [
        const ToolParam(
          name: 'user',
          description: 'The assignee GitLab username',
          required: true,
          aliases: ['accountId', 'assignee', 'userName'],
        ),
        ..._glIssueRefParams(),
      ],
    );

/// `gitlab_add_issue_label` (Java `GitLabIssues.addIssueLabel`).
ToolDefinition _addIssueLabelTool() => ToolDefinition(
      name: 'gitlab_add_issue_label',
      aliases: ['tracker_add_label'],
      description: 'Add a label to a GitLab issue',
      integration: 'gitlab',
      category: 'issues',
      params: [
        const ToolParam(
          name: 'label',
          description: 'The label name to add',
          required: true,
          aliases: ['labels'],
        ),
        ..._glIssueRefParams(),
      ],
    );

/// `gitlab_remove_issue_label` (Java `GitLabIssues.removeIssueLabel`).
ToolDefinition _removeIssueLabelTool() => ToolDefinition(
      name: 'gitlab_remove_issue_label',
      aliases: ['tracker_remove_label'],
      description: 'Remove a label from a GitLab issue',
      integration: 'gitlab',
      category: 'issues',
      params: [
        const ToolParam(
          name: 'label',
          description: 'The label name to remove',
          required: true,
        ),
        ..._glIssueRefParams(),
      ],
    );

/// `gitlab_create_issue_comment` (Java `GitLabIssues.createIssueComment`).
ToolDefinition _createIssueCommentTool() => ToolDefinition(
      name: 'gitlab_create_issue_comment',
      aliases: ['tracker_post_comment'],
      description: 'Create a comment (note) on a GitLab issue',
      integration: 'gitlab',
      category: 'comments',
      params: [
        _glOptionalWorkspace(),
        _glOptionalRepository(),
        _glOptionalIssueNumber(),
        const ToolParam(
          name: 'body',
          description: 'The comment body text',
          required: true,
          aliases: ['text', 'comment'],
        ),
        _glIssueKeyParam(),
      ],
    );

/// `gitlab_get_issue_comments` (Java `GitLabIssues.getIssueComments`).
ToolDefinition _getIssueCommentsTool() => ToolDefinition(
      name: 'gitlab_get_issue_comments',
      aliases: ['tracker_get_comments'],
      description: 'Get all comments (notes) of a GitLab issue, oldest first. '
          'Returns a JSON array of notes.',
      integration: 'gitlab',
      category: 'comments',
      params: _glIssueRefParams(),
    );

/// Shared `workspace`/`repository`/`issueNumber`/`key` parameter list.
List<ToolParam> _glIssueRefParams() => [
      _glOptionalWorkspace(),
      _glOptionalRepository(),
      _glOptionalIssueNumber(),
      _glIssueKeyParam(),
    ];

/// Optional `workspace` parameter for GitLab issue tools.
ToolParam _glOptionalWorkspace() => const ToolParam(
      name: 'workspace',
      description: 'GitLab group or namespace',
      required: false,
      aliases: ['owner'],
    );

/// Optional `repository` parameter for GitLab issue tools.
ToolParam _glOptionalRepository() => const ToolParam(
      name: 'repository',
      description: 'Repository name',
      required: false,
      aliases: ['repo'],
    );

/// Optional `issueNumber` parameter for GitLab issue tools.
ToolParam _glOptionalIssueNumber() => const ToolParam(
      name: 'issueNumber',
      description: 'The issue IID',
      required: false,
      aliases: ['number', 'iid', 'pullRequestId'],
    );

/// Optional composite `key` parameter for GitLab issue tools.
ToolParam _glIssueKeyParam() => const ToolParam(
      name: 'key',
      description: "Composite issue key 'namespace/project#123' or 'gl-123' "
          '(alternative to workspace/repository/issueNumber)',
      required: false,
    );

/// Executor routes for the GitLab issue-tracker family.
Map<String, Future<dynamic> Function(Map<String, dynamic>)>
    _glIssueTrackerHandlers(GitlabClient client) => {
          'gitlab_search_issues': (a) => client.searchIssues(
                _glArgStr(a['query']) ?? '',
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                state: _glArgStr(a['state']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_close_issue': (a) => client.closeIssueByRef(
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_reopen_issue': (a) => client.reopenIssueByRef(
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_move_issue_to_status': (a) => client.moveIssueToStatus(
                _glArgStr(a['statusName']) ?? '',
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_assign_issue': (a) => client.assignIssue(
                _glArgStr(a['user']) ?? '',
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_add_issue_label': (a) => client.addIssueLabel(
                _glArgStr(a['label']) ?? '',
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_remove_issue_label': (a) => client.removeIssueLabel(
                _glArgStr(a['label']) ?? '',
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_create_issue_comment': (a) => client.createIssueComment(
                _glArgStr(a['body']) ?? _glArgStr(a['text']) ?? '',
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
          'gitlab_get_issue_comments': (a) => client.getIssueComments(
                workspace: _glArgStr(a['workspace']),
                repository: _glArgStr(a['repository']),
                issueNumber: _glArgStr(a['issueNumber']) ?? _glArgStr(a['iid']),
                key: _glArgStr(a['key']),
                project: _glArgStr(a['project']),
              ),
        };

/// Coerces a loosely-typed executor argument to a string.
String? _glArgStr(dynamic value) => value?.toString();
