/// Project administration tools — part of the GitLab MCP tool catalog.
///
/// Ports the project, MR-pipeline, and project-hook `@MCPTool`
/// definitions. Parameter names mirror the Java `GitLab.java`
/// `@MCPParam` annotations.
part of 'gitlab_tools.dart';

/// Project tools: `gitlab_get_project_details`,
/// `gitlab_get_project_variables`.
List<ToolDefinition> _projectTools() => [
      _getProjectDetailsTool(),
      _getProjectVariablesTool(),
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

/// Merge-request approve tool: `gitlab_approve_mr`.
ToolDefinition _approveMrTool() => ToolDefinition(
      name: 'gitlab_approve_mr',
      description: 'Approve a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request unapprove tool: `gitlab_unapprove_mr`.
ToolDefinition _unapproveMrTool() => ToolDefinition(
      name: 'gitlab_unapprove_mr',
      description: 'Unapprove a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request notes tool: `gitlab_get_mr_notes`.
ToolDefinition _getMrNotesTool() => ToolDefinition(
      name: 'gitlab_get_mr_notes',
      description: 'List the notes (comments) of a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request approvals tool: `gitlab_get_mr_approvals`.
ToolDefinition _getMrApprovalsTool() => ToolDefinition(
      name: 'gitlab_get_mr_approvals',
      description: 'Get the approval state of a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request discussions tool: `gitlab_get_mr_discussions`.
ToolDefinition _getMrDiscussionsTool() => ToolDefinition(
      name: 'gitlab_get_mr_discussions',
      description: 'List the discussions (threads) of a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [_projectParam, _iidParam('merge request')],
    );

/// Merge-request discussion resolve tool: `gitlab_trigger_mr_discussion_resolve`.
ToolDefinition _triggerMrDiscussionResolveTool() => ToolDefinition(
      name: 'gitlab_trigger_mr_discussion_resolve',
      description:
          'Resolve or unresolve a discussion on a GitLab merge request',
      integration: 'gitlab',
      category: 'merge_requests',
      params: [
        _projectParam,
        _iidParam('merge request'),
        ToolParam(
          name: 'discussion_id',
          description: 'The discussion (thread) id',
          required: true,
        ),
        ToolParam(
          name: 'resolved',
          description: 'true to resolve, false to unresolve the discussion',
          type: 'boolean',
          required: true,
        ),
      ],
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

/// Tag-create tool: `gitlab_create_tag`.
ToolDefinition _createTagTool() => ToolDefinition(
      name: 'gitlab_create_tag',
      description: 'Create a tag in a GitLab project repository',
      integration: 'gitlab',
      category: 'repository',
      params: [
        _projectParam,
        ToolParam(
          name: 'tag_name',
          description: 'The name of the tag to create',
          required: true,
        ),
        ToolParam(
          name: 'ref',
          description: 'The branch, tag, or commit to create the tag from',
          required: true,
        ),
      ],
    );

/// Tag-list tool: `gitlab_get_tags`.
ToolDefinition _getTagsTool() => ToolDefinition(
      name: 'gitlab_get_tags',
      description: 'List the tags of a GitLab project repository',
      integration: 'gitlab',
      category: 'repository',
      params: [_projectParam],
    );

/// Branch-list tool: `gitlab_get_branches`.
ToolDefinition _getBranchesTool() => ToolDefinition(
      name: 'gitlab_get_branches',
      description: 'List the branches of a GitLab project repository',
      integration: 'gitlab',
      category: 'repository',
      params: [_projectParam],
    );

/// Pipeline-list tool: `gitlab_get_pipelines`.
ToolDefinition _getPipelinesTool() => ToolDefinition(
      name: 'gitlab_get_pipelines',
      description: 'List the pipelines of a GitLab project',
      integration: 'gitlab',
      category: 'pipelines',
      params: [_projectParam],
    );

/// Pipeline-trigger tool: `gitlab_trigger_pipeline`.
ToolDefinition _triggerPipelineTool() => ToolDefinition(
      name: 'gitlab_trigger_pipeline',
      description: 'Trigger a new pipeline for a GitLab project ref',
      integration: 'gitlab',
      category: 'pipelines',
      params: [
        _projectParam,
        ToolParam(
          name: 'ref',
          description: 'The branch or tag to run the pipeline for',
          required: true,
        ),
      ],
    );

/// Pipeline-read tool: `gitlab_get_pipeline`.
ToolDefinition _getPipelineTool() => ToolDefinition(
      name: 'gitlab_get_pipeline',
      description: 'Get a GitLab project pipeline by id',
      integration: 'gitlab',
      category: 'pipelines',
      params: [
        _projectParam,
        ToolParam(
          name: 'pipeline_id',
          description: 'The pipeline id',
          type: 'number',
          required: true,
        ),
      ],
    );

/// Project-details tool: `gitlab_get_project_details`.
ToolDefinition _getProjectDetailsTool() => ToolDefinition(
      name: 'gitlab_get_project_details',
      description: 'Get details of a GitLab project',
      integration: 'gitlab',
      category: 'projects',
      params: [_projectParam],
    );

/// Project-variables tool: `gitlab_get_project_variables`.
ToolDefinition _getProjectVariablesTool() => ToolDefinition(
      name: 'gitlab_get_project_variables',
      description: 'List the CI/CD variables of a GitLab project',
      integration: 'gitlab',
      category: 'projects',
      params: [_projectParam],
    );

/// MR-pipelines tool: `gitlab_get_mr_pipelines`.
List<ToolDefinition> _mrPipelineTools() => [
      ToolDefinition(
        name: 'gitlab_get_mr_pipelines',
        description: 'List pipelines for a GitLab merge request',
        integration: 'gitlab',
        category: 'merge_requests',
        params: [_projectParam, _iidParam('merge request')],
      ),
    ];

/// Project-hook tools: `gitlab_get_project_hooks`, `gitlab_add_project_hook`.
List<ToolDefinition> _projectHookTools() => [
      ToolDefinition(
        name: 'gitlab_get_project_hooks',
        description: 'List webhooks of a GitLab project',
        integration: 'gitlab',
        category: 'projects',
        params: [_projectParam],
      ),
      ToolDefinition(
        name: 'gitlab_add_project_hook',
        description: 'Add a webhook to a GitLab project',
        integration: 'gitlab',
        category: 'projects',
        params: [
          _projectParam,
          ToolParam(
            name: 'url',
            description: 'The webhook callback URL',
            required: true,
          ),
        ],
      ),
    ];
