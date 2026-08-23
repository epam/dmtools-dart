/// Pull-request, repository, build, and pipeline tools — part of the
/// ADO MCP tool catalog.
///
/// Ports the `@MCPTool` definitions agents use for code review and CI
/// (PRs, threads, labels, repositories, builds, pipelines). Parameter
/// names mirror the Java `AzureDevOpsClient` `@MCPParam` annotations.
part of 'ado_tools.dart';

/// Pull-request tools: `ado_list_prs`, `ado_get_pr`, and reviewer tools.
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
      ToolDefinition(
        name: 'ado_get_pull_request_reviewers',
        description: 'List the reviewers of an Azure DevOps pull request',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          _projectParam(),
          _numberParam('prId', 'The pull request ID'),
        ],
      ),
      ToolDefinition(
        name: 'ado_add_pull_request_reviewer',
        description: 'Add a reviewer to an Azure DevOps pull request',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          _projectParam(),
          _numberParam('prId', 'The pull request ID'),
          ToolParam(name: 'reviewerId', description: 'The reviewer user ID'),
        ],
      ),
    ];

/// Pull-request update tools: `ado_update_pull_request`,
/// `ado_get_pull_request_commits`.
List<ToolDefinition> _pullRequestUpdateTools() => [
      ToolDefinition(
        name: 'ado_update_pull_request',
        description: 'Update the title and description of an Azure DevOps '
            'pull request',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          _projectParam(),
          _numberParam('prId', 'The pull request ID'),
          ToolParam(name: 'title', description: 'The new pull request title'),
          ToolParam(
            name: 'description',
            description: 'The new pull request description',
          ),
        ],
      ),
      ToolDefinition(
        name: 'ado_get_pull_request_commits',
        description: 'List the commits in an Azure DevOps pull request',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          _projectParam(),
          _numberParam('prId', 'The pull request ID'),
        ],
      ),
    ];

/// Pull-request status tools: `ado_get_pull_request_statuses`,
/// `ado_create_pull_request_status`.
List<ToolDefinition> _pullRequestStatusTools() => [
      ToolDefinition(
        name: 'ado_get_pull_request_statuses',
        description: 'List the statuses posted on an Azure DevOps pull request',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          _projectParam(),
          _numberParam('prId', 'The pull request ID'),
        ],
      ),
      ToolDefinition(
        name: 'ado_create_pull_request_status',
        description: 'Post a status (e.g. a build result) to an Azure DevOps '
            'pull request',
        integration: 'ado',
        category: 'pull_requests',
        params: [
          _projectParam(),
          _numberParam('prId', 'The pull request ID'),
          ToolParam(
            name: 'state',
            description: 'The status state: pending, succeeded, or failed',
          ),
          ToolParam(
            name: 'description',
            description: 'The status description',
          ),
          ToolParam(
            name: 'context',
            description: 'The status context name, e.g. ci/build',
          ),
        ],
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
      ToolDefinition(
        name: 'ado_get_repo_branches',
        description: 'List branch statistics for an Azure DevOps repository',
        integration: 'ado',
        category: 'repositories',
        params: [
          _projectParam(),
          ToolParam(name: 'repoId', description: 'The repository ID'),
        ],
      ),
      ToolDefinition(
        name: 'ado_get_commits',
        description: 'List commits in an Azure DevOps repository, optionally '
            'filtered by search criteria',
        integration: 'ado',
        category: 'repositories',
        params: [
          _projectParam(),
          ToolParam(name: 'repoId', description: 'The repository ID'),
          ToolParam(
            name: 'searchCriteria',
            description: 'Optional commit search criteria, e.g. '
                '{"fromDate": "2024-01-01"}',
            type: 'object',
            required: false,
          ),
        ],
      ),
    ];

/// Repository detail/file tools: `ado_get_repo_details`, `ado_get_repo_file`.
///
/// Split out from [_repoTools] to keep each grouping under the 60-line
/// method-size gate.
List<ToolDefinition> _repoDetailTools() => [
      ToolDefinition(
        name: 'ado_get_repo_details',
        description: 'Get details of a Git repository in an Azure DevOps '
            'project',
        integration: 'ado',
        category: 'repositories',
        params: [
          _projectParam(),
          ToolParam(name: 'repoId', description: 'The repository ID'),
        ],
      ),
      ToolDefinition(
        name: 'ado_get_repo_file',
        description: 'Fetch the raw content of a file in an Azure DevOps '
            'repository at a given branch',
        integration: 'ado',
        category: 'repositories',
        params: [
          _projectParam(),
          ToolParam(name: 'repoId', description: 'The repository ID'),
          ToolParam(name: 'path', description: 'The file path in the repo'),
          ToolParam(
            name: 'branch',
            description: 'The branch name to read the file from',
          ),
        ],
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
ToolParam _idParam(String description) => _numberParam('id', description);

/// Shared numeric parameter named [name] with a tool-specific [description].
ToolParam _numberParam(String name, String description) => ToolParam(
      name: name,
      description: description,
      type: 'number',
      required: true,
    );

/// Shared `project` parameter naming the target Azure DevOps project.
ToolParam _projectParam() => ToolParam(
      name: 'project',
      description: 'The Azure DevOps project name',
    );

/// Shared `repository` parameter — the Git repository name (Java parity).
const ToolParam _repositoryParam = ToolParam(
  name: 'repository',
  description: 'The Git repository name',
  required: true,
);

/// Shared `pullRequestId` parameter (numeric, Java parity).
ToolParam _pullRequestIdParam() => _numberParam(
      'pullRequestId',
      'The pull request ID',
    );

/// PR comment tools ported from the Java `AzureDevOpsClient`:
/// `ado_get_pr_comments`, `ado_add_pr_comment`, `ado_reply_to_pr_thread`.
List<ToolDefinition> _prCommentTools() => [
      _getPrCommentsTool(),
      _addPrCommentTool(),
      _replyToPrThreadTool(),
    ];

/// PR thread tools ported from the Java `AzureDevOpsClient`:
/// `ado_resolve_pr_thread`, `ado_add_inline_comment`, `ado_merge_pr`.
List<ToolDefinition> _prThreadTools() => [
      _resolvePrThreadTool(),
      _addInlineCommentTool(),
      _mergePrTool(),
    ];

/// PR label and diff tools ported from the Java `AzureDevOpsClient`:
/// `ado_add_pr_label`, `ado_remove_pr_label`, `ado_get_pr_diff`.
List<ToolDefinition> _prLabelTools() => [
      _addPrLabelTool(),
      _removePrLabelTool(),
      _getPrDiffTool(),
    ];

/// Pipeline tools ported from the Java `AzureDevOpsClient`:
/// `ado_list_pipelines`, `ado_list_pipeline_runs`, `ado_trigger_pipeline`,
/// `ado_get_pipeline_logs`.
List<ToolDefinition> _pipelineAgentTools() => [
      _listPipelinesTool(),
      _listPipelineRunsTool(),
      _triggerPipelineTool(),
      _getPipelineLogsTool(),
    ];

/// PR comment-threads tool: `ado_get_pr_comments` (Java
/// `getPullRequestThreads`).
ToolDefinition _getPrCommentsTool() => ToolDefinition(
      name: 'ado_get_pr_comments',
      description: 'Get all comment threads for an Azure DevOps pull '
          'request; each thread contains comments, file context for inline '
          'comments, and status',
      integration: 'ado',
      category: 'pull_requests',
      params: [_repositoryParam, _pullRequestIdParam()],
    );

/// PR comment tool: `ado_add_pr_comment` (Java `addPullRequestComment`).
ToolDefinition _addPrCommentTool() => ToolDefinition(
      name: 'ado_add_pr_comment',
      description: 'Add a general comment to an Azure DevOps pull request '
          '(creates a new thread); for inline code comments use '
          'ado_add_inline_comment',
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(name: 'text', description: 'The comment text to add'),
      ],
    );

/// PR thread-reply tool: `ado_reply_to_pr_thread` (Java
/// `replyToPullRequestThread`).
ToolDefinition _replyToPrThreadTool() => ToolDefinition(
      name: 'ado_reply_to_pr_thread',
      description: 'Reply to an existing comment thread in an Azure DevOps '
          'pull request; use the threadId from ado_get_pr_comments',
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        _numberParam('threadId', 'The ID of the thread to reply to'),
        ToolParam(name: 'text', description: 'The reply text'),
      ],
    );

/// PR thread-resolve tool: `ado_resolve_pr_thread` (Java `resolveThread`).
ToolDefinition _resolvePrThreadTool() => ToolDefinition(
      name: 'ado_resolve_pr_thread',
      description: "Resolve (close) a comment thread in an Azure DevOps "
          'pull request by setting its status',
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        _numberParam('threadId', 'The ID of the thread to resolve'),
        ToolParam(
          name: 'status',
          description: "The new status: 'fixed' (default), 'closed', "
              "'byDesign', 'wontFix', 'pending', 'active'",
          required: false,
        ),
      ],
    );

/// PR inline-comment tool: `ado_add_inline_comment` (Java
/// `addInlineComment`).
ToolDefinition _addInlineCommentTool() => ToolDefinition(
      name: 'ado_add_inline_comment',
      description: 'Create an inline code comment on a specific file and '
          'line range in an Azure DevOps pull request',
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(
          name: 'filePath',
          description: 'The relative file path in the repository (must '
              'start with /)',
          aliases: ['path'],
        ),
        ToolParam(
          name: 'line',
          description: 'The line number to comment on (1-based)',
          type: 'number',
        ),
        ToolParam(name: 'text', description: 'The comment text'),
        ToolParam(
          name: 'startLine',
          description: 'For multi-line comments: the first line of the '
              'range; must be less than or equal to line',
          type: 'number',
          required: false,
        ),
        ToolParam(
          name: 'side',
          description: "Which diff side to comment on: 'right' (new code, "
              "default) or 'left' (old code)",
          required: false,
        ),
      ],
    );

/// PR merge tool: `ado_merge_pr` (Java `completePullRequest`).
ToolDefinition _mergePrTool() => ToolDefinition(
      name: 'ado_merge_pr',
      description: "Complete (merge) an Azure DevOps pull request; sets "
          "status to 'completed' with the specified merge strategy",
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(
          name: 'mergeStrategy',
          description: "The merge strategy: 'squash' (default), "
              "'noFastForward', 'rebase', 'rebaseMerge'",
          required: false,
        ),
        ToolParam(
          name: 'deleteSourceBranch',
          description: 'Whether to delete the source branch after merging '
              '(default: true)',
          type: 'boolean',
          required: false,
        ),
        ToolParam(
          name: 'commitMessage',
          description: 'Optional merge commit message',
          required: false,
        ),
      ],
    );

/// PR add-label tool: `ado_add_pr_label` (Java `addPullRequestLabel`).
ToolDefinition _addPrLabelTool() => ToolDefinition(
      name: 'ado_add_pr_label',
      description: 'Add a label (tag) to an Azure DevOps pull request',
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(name: 'label', description: 'The label name to add'),
      ],
    );

/// PR remove-label tool: `ado_remove_pr_label` (Java
/// `removePullRequestLabel`).
ToolDefinition _removePrLabelTool() => ToolDefinition(
      name: 'ado_remove_pr_label',
      description: 'Remove a label (tag) from an Azure DevOps pull request '
          'by label ID',
      integration: 'ado',
      category: 'pull_requests',
      params: [
        _repositoryParam,
        _pullRequestIdParam(),
        ToolParam(
          name: 'labelId',
          description: 'The label ID to remove (from the PR labels array, '
              'not the label name)',
        ),
      ],
    );

/// PR diff tool: `ado_get_pr_diff` (Java `getPullRequestDiffStat`).
ToolDefinition _getPrDiffTool() => ToolDefinition(
      name: 'ado_get_pr_diff',
      description: 'Get the diff/changes for an Azure DevOps pull request: '
          'the list of changed files with change types',
      integration: 'ado',
      category: 'pull_requests',
      params: [_repositoryParam, _pullRequestIdParam()],
    );

/// Pipeline-list tool: `ado_list_pipelines` (Java `listPipelines`).
ToolDefinition _listPipelinesTool() => ToolDefinition(
      name: 'ado_list_pipelines',
      description: 'List all pipelines defined in the ADO project',
      integration: 'ado',
      category: 'pipeline_management',
      params: [],
    );

/// Pipeline-runs tool: `ado_list_pipeline_runs` (Java `listPipelineRuns`).
ToolDefinition _listPipelineRunsTool() => ToolDefinition(
      name: 'ado_list_pipeline_runs',
      description: 'List recent runs of a pipeline; equivalent to '
          'github_list_workflow_runs',
      integration: 'ado',
      category: 'pipeline_management',
      params: [
        _numberParam('pipelineId', 'The pipeline ID'),
        ToolParam(
          name: 'top',
          description: 'Number of runs to return (default 10)',
          type: 'number',
          required: false,
        ),
      ],
    );

/// Pipeline-trigger tool: `ado_trigger_pipeline` (Java `triggerPipeline`).
ToolDefinition _triggerPipelineTool() => ToolDefinition(
      name: 'ado_trigger_pipeline',
      description: 'Trigger a pipeline run in ADO; equivalent to '
          'github_trigger_workflow',
      integration: 'ado',
      category: 'pipeline_management',
      params: [
        _numberParam('pipelineId', 'The pipeline ID to trigger'),
        ToolParam(
          name: 'branch',
          description: "The branch to run the pipeline on (e.g. 'main')",
          required: false,
        ),
        ToolParam(
          name: 'variables',
          description: 'JSON object of pipeline variables',
          required: false,
        ),
      ],
    );

/// Pipeline-logs tool: `ado_get_pipeline_logs` (Java `getPipelineLogs`).
ToolDefinition _getPipelineLogsTool() => ToolDefinition(
      name: 'ado_get_pipeline_logs',
      description: 'Get combined logs for all tasks in a pipeline run '
          '(build ID); equivalent to github_get_job_logs',
      integration: 'ado',
      category: 'pipeline_management',
      params: [
        _numberParam(
          'buildId',
          'The build/run ID returned by ado_trigger_pipeline or '
              'ado_list_pipeline_runs',
        ),
        ToolParam(
          name: 'taskName',
          description: 'Filter logs to a specific task name '
              '(case-insensitive substring match)',
          required: false,
        ),
        ToolParam(
          name: 'tailLines',
          description: 'Lines to return from the end of each task log '
              '(default 200, 0 = all)',
          type: 'number',
          required: false,
        ),
      ],
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
