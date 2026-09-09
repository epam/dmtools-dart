/// CI-status, PR-activity, and release-asset tool catalog and executor
/// routes — the Java `GitHub.java` `@MCPTool` set the Dart catalog was
/// missing (dm.ai #543 review surface).
part of 'github_tools.dart';

/// Check-run and commit-status tools (Java category `pull_requests`).
List<ToolDefinition> _ciStatusTools() => [
      ToolDefinition(
        name: 'github_create_check_run',
        description: 'Create a GitHub Check Run — a rich CI check with '
            'progress, annotations, and a full log visible in the PR '
            "'Checks' tab. Use status=in_progress when starting, then call "
            'github_update_check_run to complete it.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'name',
            description: 'The name of the check run displayed in the PR',
            required: true,
          ),
          const ToolParam(
            name: 'headSha',
            description: 'The SHA of the commit to associate this check run '
                'with',
            required: true,
          ),
          const ToolParam(
            name: 'status',
            description: 'The status: queued | in_progress | completed',
            required: false,
          ),
          const ToolParam(
            name: 'title',
            description: 'Title shown in the check run output panel',
            required: false,
          ),
          const ToolParam(
            name: 'summary',
            description: 'Markdown summary shown in the check run output '
                'panel',
            required: false,
          ),
          const ToolParam(
            name: 'text',
            description: 'Additional details in Markdown (supports large '
                'content)',
            required: false,
          ),
          const ToolParam(
            name: 'externalId',
            description: 'Optional external identifier for this check run',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_update_check_run',
        description: 'Update an existing GitHub Check Run — set it to '
            'completed with success/failure conclusion, update summary and '
            'detailed text. Call this after github_create_check_run to '
            'finalize the check.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'checkRunId',
            description: 'The ID of the check run to update (from '
                'github_create_check_run response)',
            required: true,
          ),
          const ToolParam(
            name: 'status',
            description: 'The new status: in_progress | completed',
            required: true,
          ),
          const ToolParam(
            name: 'conclusion',
            description: 'Required when status=completed: success | failure '
                '| neutral | cancelled | skipped | timed_out | '
                'action_required',
            required: false,
          ),
          const ToolParam(
            name: 'title',
            description: 'Updated title for the check run output panel',
            required: false,
          ),
          const ToolParam(
            name: 'summary',
            description: 'Updated Markdown summary for the check run output '
                'panel',
            required: false,
          ),
          const ToolParam(
            name: 'text',
            description: 'Updated detailed Markdown content (full analysis, '
            'annotations etc.)',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_create_commit_status',
        description: 'Create a commit status (the colored dot in PR checks). '
            'Use state=pending when AI analysis starts, success/failure/error '
            "when complete. The 'context' field acts as the status name and "
            'must be unique per check.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'sha',
            description: 'The commit SHA to set status on',
            required: true,
          ),
          const ToolParam(
            name: 'state',
            description: 'The state: pending | success | failure | error',
            required: true,
          ),
          const ToolParam(
            name: 'description',
            description: 'Short human-readable description shown next to the '
                'status dot',
            required: false,
          ),
          const ToolParam(
            name: 'context',
            description: "Unique identifier for this status check, e.g. "
                "'dmtools/pr-review'",
            required: false,
          ),
          const ToolParam(
            name: 'targetUrl',
            description: 'Optional URL to link from the status (e.g. CI run '
                'URL)',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_workflow_run',
        description: 'Get details of a specific GitHub Actions workflow run '
            'by ID. Returns status, conclusion, logs URL, and timing '
            'information.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'runId',
            description: 'The workflow run ID',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_repository_dispatch',
        description: 'Trigger a GitHub repository dispatch event. Workflows '
            "listening to 'on: repository_dispatch' with the matching "
            'event_type will be triggered.',
        integration: 'github',
        category: 'actions',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'eventType',
            description: 'The type of activity that triggers the workflow '
                '(event_type)',
            required: true,
          ),
          const ToolParam(
            name: 'clientPayload',
            description: 'Optional JSON string with payload passed to the '
                'workflow as client_payload',
            required: false,
          ),
        ],
      ),
    ];

/// PR comment-management and activity tools.
List<ToolDefinition> _prActivityTools() => [
      ToolDefinition(
        name: 'github_update_pr_comment',
        description: 'Update (edit) an existing comment on a GitHub pull '
            'request or issue by its comment ID.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'commentId',
            description: 'The ID of the comment to update',
            required: true,
          ),
          const ToolParam(
            name: 'text',
            description: 'The new comment text (replaces existing content)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_delete_pr_comment',
        description: 'Delete a comment on a GitHub pull request or issue by '
            'its comment ID.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'commentId',
            description: 'The ID of the comment to delete',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_pr_activities',
        aliases: ['source_code_get_pr_activities'],
        description: 'Get all activities for a GitHub pull request including '
            'reviews (approvals, change requests), inline code comments, and '
            'general discussion comments.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          _prIdParam(),
        ],
      ),
      ToolDefinition(
        name: 'github_list_prs_filtered',
        description: 'List pull requests in a GitHub repository filtered by '
            'a regex pattern on the PR title. Fetches all PRs matching the '
            'given state and returns only those whose title matches the '
            'regex. Useful for large repos to narrow down results without '
            'loading entire history.',
        integration: 'github',
        category: 'pull_requests',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'state',
            description: "The state of pull requests: 'open', 'closed', or "
                "'merged'.",
            required: true,
          ),
          const ToolParam(
            name: 'titleRegex',
            description: 'Java regular expression matched against the PR '
                'title (case-sensitive). Only PRs whose title contains a '
                "match are returned. Example: '^feat\\\\(.*\\\\)' or "
                "'TICKET-\\\\d+'.",
            required: true,
          ),
        ],
      ),
    ];

/// Release-asset and cross-branch commit tools.
List<ToolDefinition> _releaseAssetTools() => [
      ToolDefinition(
        name: 'github_list_release_assets',
        description: 'List all assets attached to a GitHub release. Returns '
            'a JSON array of asset objects including id, name, size, and '
            'browser_download_url.',
        integration: 'github',
        category: 'releases',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'releaseId',
            description: 'The numeric GitHub release ID.',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_delete_release_asset',
        description: 'Delete a GitHub release asset by its asset ID. Use '
            'github_list_release_assets to find asset IDs.',
        integration: 'github',
        category: 'releases',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'assetId',
            description: 'The numeric asset ID to delete.',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'github_get_commits_from_branches',
        description: 'Fetch commits from all branches whose name matches a '
            'given regex pattern, aggregated and de-duplicated. Useful for '
            'collecting commits from feature/*, release/* or similar groups '
            'of branches without specifying each branch individually.',
        integration: 'github',
        category: 'commits',
        params: [
          _workspaceParam(),
          _repositoryParam(),
          const ToolParam(
            name: 'branchNameRegex',
            description: 'Java regular expression matched against branch '
                'names. All branches with a matching name are included. '
                "Example: '^feature/' or 'release/\\\\d+'.",
            required: true,
          ),
          const ToolParam(
            name: 'since',
            description: 'Optional ISO date (yyyy-MM-dd) to limit commits to '
                'those after this date.',
            required: false,
          ),
        ],
      ),
    ];

/// Executor routes for the CI/PR-activity/release-asset tools.
Map<String, Future<dynamic> Function(Map<String, dynamic>)>
    _ciPrHandlers(GithubClient client) => {
        'github_create_check_run': (a) => client.createCheckRun(
              a['workspace'] as String,
              a['repository'] as String,
              a['name'] as String,
              a['headSha'] as String,
              status: a['status'] as String?,
              title: a['title'] as String?,
              summary: a['summary'] as String?,
              text: a['text'] as String?,
              externalId: a['externalId'] as String?,
            ),
        'github_update_check_run': (a) => client.updateCheckRun(
              a['workspace'] as String,
              a['repository'] as String,
              a['checkRunId'] as String,
              a['status'] as String,
              conclusion: a['conclusion'] as String?,
              title: a['title'] as String?,
              summary: a['summary'] as String?,
              text: a['text'] as String?,
            ),
        'github_create_commit_status': (a) => client.createCommitStatus(
              a['workspace'] as String,
              a['repository'] as String,
              a['sha'] as String,
              a['state'] as String,
              description: a['description'] as String?,
              context: a['context'] as String?,
              targetUrl: a['targetUrl'] as String?,
            ),
        'github_get_workflow_run': (a) => client.getWorkflowRun(
              a['workspace'] as String,
              a['repository'] as String,
              a['runId'].toString(),
            ),
        'github_repository_dispatch': (a) => client.repositoryDispatch(
              a['workspace'] as String,
              a['repository'] as String,
              a['eventType'] as String,
              a['clientPayload'] as String?,
            ),
        'github_update_pr_comment': (a) => client.updatePullRequestComment(
              a['workspace'] as String,
              a['repository'] as String,
              a['commentId'].toString(),
              a['text'] as String,
            ),
        'github_delete_pr_comment': (a) => client.deletePullRequestComment(
              a['workspace'] as String,
              a['repository'] as String,
              a['commentId'].toString(),
            ),
        'github_get_pr_activities': (a) => client.pullRequestActivities(
              a['workspace'] as String,
              a['repository'] as String,
              a['pullRequestId'].toString(),
            ),
        'github_list_prs_filtered': (a) => client.listPullRequestsFiltered(
              a['workspace'] as String,
              a['repository'] as String,
              a['state'] as String,
              a['titleRegex'] as String,
            ),
        'github_list_release_assets': (a) => client.listReleaseAssets(
              a['workspace'] as String,
              a['repository'] as String,
              a['releaseId'].toString(),
            ),
        'github_delete_release_asset': (a) => client.deleteReleaseAsset(
              a['workspace'] as String,
              a['repository'] as String,
              a['assetId'].toString(),
            ),
        'github_get_commits_from_branches': (a) =>
            client.getCommitsFromBranches(
              a['workspace'] as String,
              a['repository'] as String,
              a['branchNameRegex'] as String,
              a['since'] as String?,
            ),
        };
