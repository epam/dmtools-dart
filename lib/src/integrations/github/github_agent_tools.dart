/// Agent-suite GitHub tools — part of the GitHub MCP tool catalog.
///
/// Ports the `@MCPTool` set the dmtools-agents scripts call via the JS
/// bridge (PR comments/threads, inline review comments, Actions runs and
/// logs, draft releases and asset uploads). Parameter names mirror the
/// Java `GitHub.java` `@MCPParam` annotations: `workspace`,
/// `repository`, `pullRequestId`, `text` for comment bodies.
part of 'github_tools.dart';

/// PR comment/label/thread tools used by the agent suite.
List<ToolDefinition> _agentPrTools() => [
      ..._agentPrCommentTools(),
      ..._agentPrReviewReadTools(),
      ..._agentPrThreadTools(),
      _agentPrInlineCommentTool(),
      _agentPrDiffTextTool(),
    ];

/// PR comment and label write tools.
List<ToolDefinition> _agentPrCommentTools() => [
      ToolDefinition(
        name: 'github_add_pr_comment',
        description: 'Add a comment to a GitHub pull request discussion.',
        integration: 'github',
        category: 'pull_requests',
        aliases: ['source_code_add_pr_comment'],
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
          ToolParam(
            name: 'text',
            description: 'The comment text to add',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_add_pr_label',
        description: 'Add a label to a GitHub pull request.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
          ToolParam(
            name: 'label',
            description: 'The label name to add to the pull request',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_remove_pr_label',
        description: 'Remove a label from a GitHub pull request.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
          ToolParam(
            name: 'label',
            description: 'The label name to remove from the pull request',
            required: true,
          ),
        ],
      ),
    ];

/// PR review-thread read tools.
List<ToolDefinition> _agentPrReviewReadTools() => [
      ToolDefinition(
        name: 'github_get_pr_comments',
        description:
            'Get all comments for a GitHub pull request, including both '
            'inline code review comments and general discussion comments. '
            'Results are sorted by creation date.',
        integration: 'github',
        category: 'pull_requests',
        aliases: ['source_code_get_pr_comments'],
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
        ],
      ),
      ToolDefinition(
        name: 'github_get_pr_conversations',
        description:
            'Get all review conversations (inline code comment threads) for '
            'a GitHub pull request, grouped into root comment and replies, '
            'plus general PR discussion comments as separate entries.',
        integration: 'github',
        category: 'pull_requests',
        aliases: ['source_code_get_pr_discussions'],
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
        ],
      ),
      ToolDefinition(
        name: 'github_get_pr_review_threads',
        description:
            "Get all review threads for a GitHub pull request via GraphQL, "
            "including each thread's node ID (needed for resolving), "
            'resolved status, file path, line, and comments.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
        ],
      ),
    ];

/// Review-thread write tools (resolve, reply).
List<ToolDefinition> _agentPrThreadTools() => [
      ToolDefinition(
        name: 'github_resolve_pr_thread',
        description:
            "Resolve a review thread in a GitHub pull request. Requires the "
            "thread's GraphQL node ID from github_get_pr_review_threads.",
        integration: 'github',
        category: 'pull_requests',
        aliases: ['source_code_resolve_pr_thread'],
        params: [
          ToolParam(
            name: 'threadId',
            description: 'The GraphQL node ID of the review thread to resolve',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_reply_to_pr_thread',
        description:
            'Reply to an existing inline code review comment thread in a '
            'GitHub pull request. Use the comment ID of the root comment '
            '(or any comment) in the thread as inReplyToId.',
        integration: 'github',
        category: 'pull_requests',
        aliases: ['source_code_reply_to_pr_thread'],
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
          ToolParam(
            name: 'inReplyToId',
            description:
                'The ID of the comment to reply to (aliases: threadId)',
            required: true,
            aliases: ['threadId'],
          ),
          ToolParam(
            name: 'text',
            description: 'The reply text (Markdown supported)',
            required: true,
          ),
        ],
      ),
    ];

/// Inline code review comment tool.
ToolDefinition _agentPrInlineCommentTool() => ToolDefinition(
      name: 'github_add_inline_comment',
      description:
          "Create a new inline code review comment on a specific file and "
          'line in a GitHub pull request. To comment on a range of lines, '
          "provide both startLine and line. Side is 'RIGHT' for new code "
          "(default) or 'LEFT' for old code.",
      integration: 'github',
      category: 'pull_requests',
      aliases: ['source_code_add_inline_comment'],
      params: [
        _workspaceParam(),
        _repositoryParam(),
        _prIdParam(),
        ToolParam(
          name: 'path',
          description: 'The relative file path in the repository',
          required: true,
          aliases: ['filePath'],
        ),
        ToolParam(
          name: 'line',
          description: 'The line number in the file to comment on',
          type: 'number',
          required: true,
        ),
        ToolParam(
          name: 'text',
          description: 'The comment text (Markdown supported)',
          required: true,
        ),
        ToolParam(
          name: 'commitId',
          description:
              'The SHA of the commit to comment on. If empty, uses the PR '
              'head commit.',
          required: false,
        ),
        ToolParam(
          name: 'startLine',
          description:
              'For multi-line comments: the first line of the range. Must '
              'be less than line.',
          type: 'number',
          required: false,
        ),
        ToolParam(
          name: 'side',
          description:
              "Which diff side to comment on: RIGHT (new code, default) "
              'or LEFT (old code)',
          required: false,
        ),
      ],
    );

/// Raw diff text tool.
ToolDefinition _agentPrDiffTextTool() => ToolDefinition(
      name: 'github_get_pr_diff_text',
      description: 'Get the raw unified diff text for a GitHub pull request. '
          'Requires IS_READ_PULL_REQUEST_DIFF env/config to be enabled.',
      integration: 'github',
      category: 'pull_requests',
      params: [
        _workspaceParam(),
        _repositoryParam(),
        _prIdParam(name: 'pullRequestID'),
      ],
    );

/// Commit-check and Actions tools used by the agent suite.
List<ToolDefinition> _agentActionsTools() => [
      ..._agentCheckRunTools(),
      _agentWorkflowRunsTool(),
      ..._agentWorkflowRunTools(),
    ];

/// Commit check-run and Actions job/run listing tools.
List<ToolDefinition> _agentCheckRunTools() => [
      ToolDefinition(
        name: 'github_get_commit_check_runs',
        description:
            'Get all check runs (CI/CD status checks) for a commit SHA in a '
            'GitHub repository.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          ToolParam(
            name: 'commitSha',
            description: 'The commit SHA to get check runs for',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_job_logs',
        description: 'Get the raw text logs for a specific GitHub Actions job. '
            'Returns the complete log output from all steps in the job.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          ToolParam(
            name: 'jobId',
            description: 'The job ID (from github_get_workflow_run_jobs)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_workflow_run_jobs',
        description:
            'Get all jobs for a specific GitHub Actions workflow run. Shows '
            'individual job statuses, steps, and logs URLs.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          ToolParam(
            name: 'runId',
            description: 'The workflow run ID',
            required: true,
          ),
        ],
      ),
    ];

/// Workflow-run listing tool (with its many filters).
ToolDefinition _agentWorkflowRunsTool() => ToolDefinition(
      name: 'github_list_workflow_runs',
      description:
          "List GitHub Actions workflow runs for a repository, optionally "
          "filtered by status or specific workflow file. Use "
          "status='failure' to get all failed runs.",
      integration: 'github',
      category: 'actions',
      params: [
        _workspaceParam(),
        _repositoryParam(),
        ToolParam(
          name: 'status',
          description:
              'Filter by status: failure, success, in_progress, queued, '
              'cancelled, timed_out, action_required, neutral, skipped, '
              'stale, completed',
          required: false,
        ),
        ToolParam(
          name: 'workflowId',
          description: 'Optional workflow filename to filter runs (e.g. '
              'rework.yml). If omitted, returns runs for all workflows.',
          required: false,
        ),
        ToolParam(
          name: 'perPage',
          description: 'Number of results per page (max 100, default 30)',
          type: 'number',
          required: false,
        ),
        ToolParam(
          name: 'page',
          description: 'Page number for pagination (default 1)',
          type: 'number',
          required: false,
        ),
        ToolParam(
          name: 'created',
          description:
              'Filter by created date/range using GitHub search syntax, '
              'e.g. 2026-05-01..2026-05-31 or >=2026-05-01',
          required: false,
        ),
      ],
    );

/// Workflow dispatch and log-download tools.
List<ToolDefinition> _agentWorkflowRunTools() => [
      ToolDefinition(
        name: 'github_trigger_workflow',
        description: 'Trigger a specific GitHub Actions workflow by filename '
            "(workflow dispatch). The workflow must have "
            "'on: workflow_dispatch' configured.",
        integration: 'github',
        category: 'actions',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          ToolParam(
            name: 'workflowId',
            description: 'The workflow filename or ID to trigger',
            required: true,
          ),
          ToolParam(
            name: 'inputs',
            description: 'JSON string with workflow inputs (e.g. '
                '{"user_request":"...","branch":"main"})',
            required: false,
          ),
          ToolParam(
            name: 'ref',
            description: 'The branch or tag to run the workflow on '
                '(default: main)',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_workflow_run_logs',
        description:
            'Download and extract complete logs for all jobs in a GitHub '
            'Actions workflow run. Returns full untruncated log content '
            'from the ZIP archive GitHub provides.',
        integration: 'github',
        category: 'actions',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          ToolParam(
            name: 'runId',
            description: 'The workflow run ID',
            required: true,
          ),
        ],
      ),
    ];

/// Draft-release storage tools used by the agent suite.
List<ToolDefinition> _agentReleaseTools() => [
      _agentDraftReleaseTool(),
      _agentUploadAssetTool(),
    ];

/// Draft-release get-or-create tool.
ToolDefinition _agentDraftReleaseTool() => ToolDefinition(
      name: 'github_get_or_create_draft_release',
      description:
          'Find an existing draft release by tag or name, or create one '
          'if it does not exist. Useful for a stable PR attachment '
          'storage release.',
      integration: 'github',
      category: 'releases',
      params: [
        _workspaceParam(),
        _repositoryParam(),
        ToolParam(
          name: 'tagName',
          description: 'The Git tag name for the release. Reused to find an '
              'existing draft release.',
          required: true,
        ),
        ToolParam(
          name: 'releaseName',
          description:
              'The human-readable release name. If empty, tagName is used.',
          required: false,
        ),
        ToolParam(
          name: 'targetCommitish',
          description:
              'Optional branch or commit SHA the release should point to '
              'when created.',
          required: false,
        ),
        ToolParam(
          name: 'body',
          description: 'Optional Markdown release notes/body.',
          required: false,
        ),
      ],
    );

/// Release-asset upload tool.
ToolDefinition _agentUploadAssetTool() => ToolDefinition(
      name: 'github_upload_release_asset',
      description: 'Upload a local file as a GitHub release asset. Returns the '
          'uploaded asset metadata including browser_download_url. Set '
          'overwrite=true to automatically delete an existing asset with '
          'the same name before uploading.',
      integration: 'github',
      category: 'releases',
      params: [
        _workspaceParam(),
        _repositoryParam(),
        ToolParam(
          name: 'releaseId',
          description: 'The numeric GitHub release ID returned by '
              'github_get_or_create_draft_release.',
          required: true,
        ),
        ToolParam(
          name: 'filePath',
          description: 'Absolute or relative path to the local file to upload.',
          required: true,
        ),
        ToolParam(
          name: 'assetName',
          description:
              'Optional asset filename shown in GitHub. Defaults to the '
              'local filename.',
          required: false,
        ),
        ToolParam(
          name: 'contentType',
          description: 'Optional MIME type. Defaults to detected type or '
              'application/octet-stream.',
          required: false,
        ),
        ToolParam(
          name: 'label',
          description: 'Optional display label for the uploaded asset.',
          required: false,
        ),
        ToolParam(
          name: 'overwrite',
          description: 'If true, delete any existing asset with the same name '
              'before uploading. Defaults to false.',
          required: false,
        ),
      ],
    );

/// Shared `workspace` parameter (Java `@MCPParam(name = "workspace")`).
ToolParam _workspaceParam() => ToolParam(
      name: 'workspace',
      description: 'The GitHub owner/organization name',
      required: true,
    );

/// Shared `repository` parameter (Java `@MCPParam(name = "repository")`).
ToolParam _repositoryParam() => ToolParam(
      name: 'repository',
      description: 'The GitHub repository name',
      required: true,
    );

/// Shared `pullRequestId` parameter.
///
/// Java spells it `pullRequestId` everywhere except the diff tools, which
/// use `pullRequestID` — pass [name] to override.
ToolParam _prIdParam({String name = 'pullRequestId'}) => ToolParam(
      name: name,
      description: 'The pull request number',
      required: true,
    );
