/// Issue-tracker tool catalog — Java `GitLabIssues.java` (dm.ai bb7a2f93)
/// parity.
///
/// The whole issue family accepts explicit `workspace`/`repository`/
/// `issueNumber` parts, a composite `key` (`namespace/project#123` with
/// nested subgroups, the `gl-123` router convention, or a bare IID resolved
/// against the configured `GITLAB_WORKSPACE` / `GITLAB_REPOSITORY`
/// defaults), and the Java `tracker_*` alias set so GitLab can serve as the
/// tracker backend (`DEFAULT_TRACKER=gitlab`).
part of 'gitlab_tools.dart';

/// Optional `workspace` param (Java marks it optional — the key or the
/// configured defaults may carry it).
ToolParam _glOptWorkspace() => ToolParam(
      name: 'workspace',
      description: 'GitLab group or namespace',
      aliases: ['owner'],
    );

/// Optional `repository` param.
ToolParam _glOptRepository() => ToolParam(
      name: 'repository',
      description: 'Repository name',
      aliases: ['repo'],
    );

/// Optional `issueNumber` param (the composite `key` may carry it).
ToolParam _glOptIssueNumber() => ToolParam(
      name: 'issueNumber',
      description: 'The issue IID',
      aliases: ['number', 'iid', 'pullRequestId'],
    );

/// Optional composite issue `key` param.
ToolParam _glIssueKeyParam() => ToolParam(
      name: 'key',
      description: "Composite issue key 'namespace/project#123' or 'gl-123' "
          '(alternative to workspace/repository/issueNumber)',
    );

/// Issue-tracker tools: `gitlab_get_issue`, `gitlab_search_issues`,
/// `gitlab_create_issue`, `gitlab_close_issue`, `gitlab_reopen_issue`,
/// `gitlab_move_issue_to_status`, `gitlab_assign_issue`,
/// `gitlab_add_issue_label`, `gitlab_remove_issue_label`,
/// `gitlab_create_issue_comment`, `gitlab_get_issue_comments`.
List<ToolDefinition> _issueTrackerTools() => [
      ToolDefinition(
        name: 'gitlab_get_issue',
        aliases: ['tracker_get_ticket'],
        description: 'Get details of a GitLab issue including title, '
            'description, state, author, labels, and assignees.',
        integration: 'gitlab',
        category: 'issues',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_search_issues',
        aliases: ['tracker_search'],
        description: 'Search GitLab issues of a project with a query string '
            'matched against title and description. Returns a JSON array of '
            'issues.',
        integration: 'gitlab',
        category: 'issues',
        params: [
          ToolParam(
            name: 'query',
            description:
                'Text matched against issue title and description',
            required: true,
            aliases: ['jql', 'wiql'],
          ),
          _glOptWorkspace(),
          _glOptRepository(),
          const ToolParam(
            name: 'state',
            description: 'Issue state filter: opened, closed, all (default: '
                'all)',
          ),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_create_issue',
        aliases: ['tracker_create_ticket'],
        description: 'Create a GitLab issue',
        integration: 'gitlab',
        category: 'issues',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          ToolParam(
            name: 'title',
            description: 'The title of the new issue',
            required: true,
            aliases: ['summary'],
          ),
          const ToolParam(
            name: 'body',
            description: 'The issue description (markdown)',
            aliases: ['description'],
          ),
          const ToolParam(
            name: 'key',
            description: "Composite project key 'namespace/project' "
                '(alternative to workspace/repository)',
            aliases: ['project'],
          ),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_close_issue',
        description: 'Close a GitLab issue',
        integration: 'gitlab',
        category: 'issues',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_reopen_issue',
        description: 'Reopen a closed GitLab issue',
        integration: 'gitlab',
        category: 'issues',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_move_issue_to_status',
        aliases: ['tracker_move_to_status'],
        description: "Move a GitLab issue to a status. 'done'/'closed'/"
            "'completed'/'resolved' close the issue, 'open'/'reopened' "
            "reopen it; any other status is applied as a scoped "
            "'status::<status>' label.",
        integration: 'gitlab',
        category: 'issues',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          ToolParam(
            name: 'statusName',
            description: 'Target status: done/closed/completed/resolved '
                'close, open/reopened reopen, else status::<name> label',
            required: true,
          ),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_assign_issue',
        aliases: ['tracker_assign'],
        description: 'Assign a GitLab issue to a user by username',
        integration: 'gitlab',
        category: 'issues',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          ToolParam(
            name: 'user',
            description: 'The username to assign',
            required: true,
          ),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_add_issue_label',
        aliases: ['tracker_add_label'],
        description: 'Add a label to a GitLab issue',
        integration: 'gitlab',
        category: 'issues',
        params: [
          ToolParam(
            name: 'label',
            description: 'The label name to add',
            required: true,
            aliases: ['labels'],
          ),
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_remove_issue_label',
        aliases: ['tracker_remove_label'],
        description: 'Remove a label from a GitLab issue',
        integration: 'gitlab',
        category: 'issues',
        params: [
          ToolParam(
            name: 'label',
            description: 'The label name to remove',
            required: true,
          ),
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_create_issue_comment',
        aliases: ['tracker_post_comment'],
        description: 'Create a comment (note) on a GitLab issue',
        integration: 'gitlab',
        category: 'comments',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          ToolParam(
            name: 'body',
            description: 'The comment body text',
            required: true,
            aliases: ['text', 'comment'],
          ),
          _glIssueKeyParam(),
        ],
      ),
      ToolDefinition(
        name: 'gitlab_get_issue_comments',
        aliases: ['tracker_get_comments'],
        description: 'Get all comments (notes) of a GitLab issue, oldest '
            'first. Returns a JSON array of notes.',
        integration: 'gitlab',
        category: 'comments',
        params: [
          _glOptWorkspace(),
          _glOptRepository(),
          _glOptIssueNumber(),
          _glIssueKeyParam(),
        ],
      ),
    ];
