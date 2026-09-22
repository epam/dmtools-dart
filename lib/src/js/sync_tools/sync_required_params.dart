/// Java `MCPToolProcessor`-parity required-parameter validation for the
/// sync tool classes (gh-191 Section 3, ledger P6-VCS-16).
///
/// The Java MCP executors are generated code: before a tool method runs,
/// each `@MCPParam(required = true)` value is checked in declaration order
/// and a missing one aborts with
/// `IllegalArgumentException("Required parameter 'x' is missing")` — the
/// parameter is looked up through its declared [aliases] first, so passing
/// `threadId` satisfies an `inReplyToId` check. The sync bridge mirrors
/// that contract: dispatch-time validation, Java error text, Java order.
library;

import 'dart:convert';

/// `github_*` tools with Java-required parameters, in Java declaration
/// order (extracted from `GitHub.java` `@MCPParam(required = true)`).
///
/// Only tools with at least one required param appear; `github_test` and
/// friends accept empty argument maps. `github_get_pr_diff` /
/// `github_get_pr_diff_text` keep Java's `pullRequestID` casing — the
/// error text must match Java verbatim, while the check also accepts the
/// Dart-side `pullRequestId` spelling (see [syncMissingRequiredParam]).
const Map<String, List<String>> kGithubRequiredParams = {
  'github_add_inline_comment': [
    'workspace',
    'repository',
    'pullRequestId',
    'path',
    'line',
    'text',
  ],
  'github_add_pr_comment': ['workspace', 'repository', 'pullRequestId', 'text'],
  'github_add_pr_label': ['workspace', 'repository', 'pullRequestId', 'label'],
  'github_create_check_run': ['workspace', 'repository', 'name', 'headSha'],
  'github_create_commit_status': ['workspace', 'repository', 'sha', 'state'],
  'github_delete_pr_comment': ['workspace', 'repository', 'commentId'],
  'github_delete_release_asset': ['workspace', 'repository', 'assetId'],
  'github_dismiss_pr_review': [
    'workspace',
    'repository',
    'pullRequestId',
    'reviewId',
    'message',
  ],
  'github_get_commit_check_runs': ['workspace', 'repository', 'commitSha'],
  'github_get_commits_from_branches': [
    'workspace',
    'repository',
    'branchNameRegex',
  ],
  'github_get_job_logs': ['workspace', 'repository', 'jobId'],
  'github_get_or_create_draft_release': [
    'workspace',
    'repository',
    'tagName',
  ],
  'github_get_pr': ['workspace', 'repository', 'pullRequestId'],
  'github_get_pr_activities': ['workspace', 'repository', 'pullRequestId'],
  'github_get_pr_conversations': ['workspace', 'repository', 'pullRequestId'],
  'github_get_pr_diff': ['workspace', 'repository', 'pullRequestID'],
  'github_get_pr_diff_text': ['workspace', 'repository', 'pullRequestID'],
  'github_get_pr_review_threads': ['workspace', 'repository', 'pullRequestId'],
  'github_get_workflow_run': ['workspace', 'repository', 'runId'],
  'github_get_workflow_run_jobs': ['workspace', 'repository', 'runId'],
  'github_get_workflow_run_logs': ['workspace', 'repository', 'runId'],
  'github_list_pr_reviews': ['workspace', 'repository', 'pullRequestId'],
  'github_list_prs': ['workspace', 'repository', 'state'],
  'github_list_prs_filtered': [
    'workspace',
    'repository',
    'state',
    'titleRegex',
  ],
  'github_list_release_assets': ['workspace', 'repository', 'releaseId'],
  'github_list_workflow_runs': ['workspace', 'repository'],
  'github_merge_pr': ['workspace', 'repository', 'pullRequestId'],
  'github_remove_pr_label': [
    'workspace',
    'repository',
    'pullRequestId',
    'label',
  ],
  'github_reply_to_pr_thread': [
    'workspace',
    'repository',
    'pullRequestId',
    'inReplyToId',
    'text',
  ],
  'github_repository_dispatch': ['workspace', 'repository', 'eventType'],
  'github_resolve_pr_thread': ['threadId'],
  'github_submit_pr_review': [
    'workspace',
    'repository',
    'pullRequestId',
    'event',
  ],
  'github_trigger_workflow': ['workspace', 'repository', 'workflowId'],
  'github_update_check_run': [
    'workspace',
    'repository',
    'checkRunId',
    'status',
  ],
  'github_update_pr_comment': [
    'workspace',
    'repository',
    'commentId',
    'text',
  ],
  'github_upload_release_asset': [
    'workspace',
    'repository',
    'releaseId',
    'filePath',
  ],
};

/// `gitlab_*` tools with Java-required parameters, in Java declaration
/// order (extracted from `GitLab.java` `@MCPParam(required = true)`).
const Map<String, List<String>> kGitlabRequiredParams = {
  'gitlab_add_inline_mr_comment': [
    // Java also marks baseSha/headSha/startSha required, but the Dart
    // handler resolves them from the MR's `diff_refs` server-side — they
    // are genuinely optional here, so validation must not demand them.
    'workspace',
    'repository',
    'pullRequestId',
    'path',
    'line',
    'text',
  ],
  'gitlab_add_mr_comment': ['workspace', 'repository', 'pullRequestId', 'text'],
  'gitlab_add_mr_label': ['workspace', 'repository', 'pullRequestId', 'label'],
  'gitlab_approve_mr': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_cancel_job': ['workspace', 'repository', 'jobId'],
  'gitlab_create_mr': [
    'workspace',
    'repository',
    'sourceBranch',
    'targetBranch',
    'title',
  ],
  'gitlab_create_mr_note': ['workspace', 'repository', 'pullRequestId', 'text'],
  'gitlab_delete_release_asset': [
    'workspace',
    'repository',
    'tagName',
    'assetName',
  ],
  'gitlab_download_release_asset': [
    'workspace',
    'repository',
    'tagName',
    'assetName',
    'targetFilePath',
  ],
  'gitlab_get_commit_statuses': ['workspace', 'repository', 'commitSha'],
  'gitlab_get_job_logs': ['workspace', 'repository', 'jobId'],
  'gitlab_get_mr': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_mr_activities': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_mr_comments': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_mr_diff': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_mr_diff_text': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_mr_discussions': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_mr_pipelines': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_get_or_create_release': ['workspace', 'repository', 'tagName'],
  'gitlab_get_pipeline_jobs': ['workspace', 'repository', 'pipelineId'],
  'gitlab_list_issues': ['workspace', 'repository'],
  'gitlab_list_mrs': ['workspace', 'repository', 'state'],
  'gitlab_list_pipeline_runs': ['workspace', 'repository'],
  'gitlab_list_project_jobs': ['workspace', 'repository'],
  'gitlab_list_release_assets': ['workspace', 'repository', 'tagName'],
  'gitlab_merge_mr': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_rebase_mr': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_remove_mr_label': [
    'workspace',
    'repository',
    'pullRequestId',
    'label',
  ],
  'gitlab_reply_to_mr_thread': [
    'workspace',
    'repository',
    'pullRequestId',
    'discussionId',
    'text',
  ],
  'gitlab_resolve_mr_thread': [
    'workspace',
    'repository',
    'pullRequestId',
    'discussionId',
  ],
  'gitlab_trigger_pipeline': ['workspace', 'repository', 'ref'],
  'gitlab_unapprove_mr': ['workspace', 'repository', 'pullRequestId'],
  'gitlab_upload_release_asset': [
    'workspace',
    'repository',
    'tagName',
    'filePath',
  ],
};

/// `@MCPParam(aliases = …)` per tool: primary name → accepted aliases
/// (Java resolves aliases before the required check).
const Map<String, Map<String, List<String>>> kGithubParamAliases = {
  'github_add_inline_comment': {
    'path': ['filePath'],
  },
  'github_reply_to_pr_thread': {
    'inReplyToId': ['threadId'],
  },
};

/// Alias tables for the GitLab family (Java `GitLab.java` annotations).
const Map<String, Map<String, List<String>>> kGitlabParamAliases = {
  'gitlab_add_inline_mr_comment': {
    'path': ['filePath'],
  },
  'gitlab_create_mr_note': {
    'text': ['body', 'note'],
  },
  'gitlab_reply_to_mr_thread': {
    'discussionId': ['threadId'],
  },
  'gitlab_resolve_mr_thread': {
    'discussionId': ['threadId'],
  },
};

/// Dart-side spellings the handlers already read that Java spells
/// differently — accepted so validation never rejects a call the handler
/// would have served (only the error TEXT is Java's).
const Map<String, List<String>> kGithubAcceptedNames = {
  'github_get_pr_diff': ['pullRequestId'],
  'github_get_pr_diff_text': ['pullRequestId'],
};

/// Dart-side accepted spellings for the GitLab family: several MR tools
/// keep a legacy `project`/`iid` calling contract alongside the Java
/// names — accepted so those calls keep working (only the error TEXT is
/// Java's).
const Map<String, List<String>> kGitlabAcceptedNames = {
  'gitlab_get_mr': ['project', 'iid'],
  'gitlab_create_mr_note': ['project', 'iid'],
  'gitlab_list_mrs': ['project'],
};

/// Returns the Java-style error payload for the first missing required
/// parameter of [tool], or `null` when every requirement is satisfied.
///
/// [requiredParams] and [paramAliases] are the `k*RequiredParams` /
/// `k*ParamAliases` tables above. A name counts as present when the map
/// carries a non-null value under the Java name, one of its aliases, or
/// any extra [acceptedNames] (the Dart-side spellings handlers already
/// read, e.g. `pullRequestId` for Java's `pullRequestID`) — validation
/// must never break a call the handler itself would have accepted.
String? syncMissingRequiredParam(
  String tool,
  Map<String, dynamic> args,
  Map<String, List<String>> requiredParams,
  Map<String, Map<String, List<String>>> paramAliases, [
  Map<String, List<String>> acceptedNames = const {},
]) {
  final required = requiredParams[tool];
  if (required == null) return null;
  final extra = acceptedNames[tool] ?? const <String>[];
  final aliases = paramAliases[tool] ?? const <String, List<String>>{};
  for (final name in required) {
    final candidates = [name, ...aliases[name] ?? const <String>[], ...extra];
    var found = false;
    for (final candidate in candidates) {
      if (args.containsKey(candidate) && args[candidate] != null) {
        found = true;
        break;
      }
    }
    if (!found) {
      return jsonEncode({'error': "Required parameter '$name' is missing"});
    }
  }
  return null;
}

/// Wraps [handlers] so each call is validated against [requiredParams]
/// before the handler runs (Java: executor validation precedes the client).
Map<String, String Function(Map<String, dynamic> args)> syncGuardRequired(
  Map<String, String Function(Map<String, dynamic> args)> handlers,
  Map<String, List<String>> requiredParams,
  Map<String, Map<String, List<String>>> paramAliases, [
  Map<String, List<String>> acceptedNames = const {},
]) =>
    {
      for (final entry in handlers.entries)
        entry.key: (args) {
          final missing = syncMissingRequiredParam(
            entry.key,
            args,
            requiredParams,
            paramAliases,
            acceptedNames,
          );
          if (missing != null) return missing;
          return entry.value(args);
        },
    };
