/// Catalog entries for the native GitHub PR review tools.
///
/// Java spec: `GitHub.submitPullRequestReview` /
/// `GitHub.listPullRequestReviews` / `GitHub.dismissPullRequestReview`
/// (GitHub.java around line #495). Split out of `github_tools.dart` to
/// keep both files under the loc gate; the workspace/repository/
/// pullRequestId parameter triple is shared to stay under the
/// duplication gate.
import '../mcp/tool_definition.dart';
import '../mcp/tool_param.dart';

/// `github_submit_pr_review`, `github_list_pr_reviews`,
/// `github_dismiss_pr_review` catalog entries, in declaration order.
List<ToolDefinition> prReviewTools() => [
      _submitReviewTool(),
      _listReviewsTool(),
      _dismissReviewTool(),
    ];

/// Shared `workspace`/`repository`/`pullRequestId` parameter triple.
List<ToolParam> _prRefParams() => const [
      ToolParam(
        name: 'workspace',
        description: 'The GitHub owner/organization name',
        required: true,
      ),
      ToolParam(
        name: 'repository',
        description: 'The GitHub repository name',
        required: true,
      ),
      ToolParam(
        name: 'pullRequestId',
        description: 'The pull request number',
        required: true,
      ),
    ];

/// `github_submit_pr_review` — submit a formal review decision.
ToolDefinition _submitReviewTool() => ToolDefinition(
      name: 'github_submit_pr_review',
      description: 'Submit a formal GitHub pull request review (a native '
          'reviewer decision, distinct from labels/comments). event=APPROVE '
          'marks the PR as approved by this reviewer; event=REQUEST_CHANGES '
          "formally blocks the PR (visible as 'Changes requested', and "
          'enforced by branch protection rules requiring approvals) until a '
          'new review or github_dismiss_pr_review clears it; event=COMMENT '
          "leaves a review without approving or blocking. 'body' is "
          'required for REQUEST_CHANGES and COMMENT.',
      integration: 'github',
      category: 'pull_requests',
      params: [
        ..._prRefParams(),
        const ToolParam(
          name: 'event',
          description: 'The review decision: APPROVE, REQUEST_CHANGES, or '
              'COMMENT',
          required: true,
        ),
        const ToolParam(
          name: 'body',
          description: "The review's summary text. Required for "
              'REQUEST_CHANGES and COMMENT.',
          required: false,
        ),
      ],
    );

/// `github_list_pr_reviews` — list submitted reviews chronologically.
ToolDefinition _listReviewsTool() => ToolDefinition(
      name: 'github_list_pr_reviews',
      description: 'List all formal reviews (APPROVE/REQUEST_CHANGES/'
          'COMMENT decisions submitted via github_submit_pr_review or by '
          'human reviewers) for a GitHub pull request, in chronological '
          'order.',
      integration: 'github',
      category: 'pull_requests',
      params: _prRefParams(),
    );

/// `github_dismiss_pr_review` — dismiss a previously submitted review.
ToolDefinition _dismissReviewTool() => ToolDefinition(
      name: 'github_dismiss_pr_review',
      description: 'Dismiss a previously submitted GitHub pull request '
          'review (e.g. clear a REQUEST_CHANGES decision once the issues '
          'have been fixed and a new review approves). Requires repository '
          'admin rights, or being listed as allowed to dismiss reviews, on '
          'protected branches.',
      integration: 'github',
      category: 'pull_requests',
      params: [
        ..._prRefParams(),
        const ToolParam(
          name: 'reviewId',
          description: 'The ID of the review to dismiss (from '
              'github_list_pr_reviews or the response of '
              'github_submit_pr_review)',
          required: true,
        ),
        const ToolParam(
          name: 'message',
          description: 'The reason for dismissing this review',
          required: true,
        ),
      ],
    );
