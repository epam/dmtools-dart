/// Synchronous GitHub tool executors for the QuickJS tool bridge.
///
/// Java spec: `GitHub.java` (`@MCPTool`/`@MCPParam` names are law). Tool
/// arguments use the Java parameter names — `workspace`, `repository`,
/// `pullRequestId`, `text` for comment bodies — matching what the agent
/// scripts in dmtools-agents pass. HTTP goes through [SyncHttpClient]
/// (curl subprocess) so calls stay synchronous inside `NativeCallable`
/// callbacks; config (token, base path) comes from [PropertyReader].
///
/// Binary-specific requests (release-asset upload, workflow-run log ZIP
/// download) run curl directly because [SyncHttpClient] only moves UTF-8
/// strings: uploads stream `--data-binary @file` from the real file, and
/// the ZIP download reads raw stdout bytes.
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';
import 'github_release_assets.dart';
import 'github_workflow_logs.dart';

/// Connection config for one GitHub sync call.
typedef GhSyncConfig = ({String baseUrl, Map<String, String> headers});

/// Synchronous executors for the `github_*` MCP tools.
///
/// Pure functions from a tool-argument map to a JSON result string
/// (or a plain string where Java returns one, e.g. workflow trigger).
/// The [handlers] map is wired into [SyncToolDispatcher] by the host
/// bridge; each entry resolves config first and reports
/// `{"error": "GitHub not configured"}` when the token is missing —
/// the same contract as the dispatcher's other integrations.
class GitHubSyncTools {
  /// Creates GitHub sync tooling reading config on every dispatch.
  const GitHubSyncTools();

  /// GitHub tool executors, keyed by tool name.
  ///
  /// Covers the agent-suite surface: PR read/comment/label/merge tools,
  /// inline review threads (REST + GraphQL), Actions runs and logs, and
  /// draft-release asset storage.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'github_get_pr': (args) => _run(_getPr, args),
        'github_list_prs': (args) => _run(_listPrs, args),
        'github_create_comment': (args) => _run(_createComment, args),
        'github_add_pr_comment': (args) => _run(_addPrComment, args),
        'github_add_pr_label': (args) => _run(_addPrLabel, args),
        'github_remove_pr_label': (args) => _run(_removePrLabel, args),
        'github_get_pr_comments': (args) => _run(_getPrComments, args),
        'github_get_pr_conversations': (args) =>
            _run(_getPrConversations, args),
        'github_get_pr_review_threads': (args) =>
            _run(_getPrReviewThreads, args),
        'github_resolve_pr_thread': (args) => _run(_resolvePrThread, args),
        'github_reply_to_pr_thread': (args) => _run(_replyToPrThread, args),
        'github_add_inline_comment': (args) => _run(_addInlineComment, args),
        'github_get_pr_diff': (args) => _run(_getPrDiff, args),
        'github_get_pr_diff_text': (args) => _run(_getPrDiffText, args),
        'github_merge_pr': (args) => _run(_mergePr, args),
        'github_get_commit_check_runs': (args) =>
            _run(_getCommitCheckRuns, args),
        'github_get_job_logs': (args) => _run(_getJobLogs, args),
        'github_list_workflow_runs': (args) => _run(_listWorkflowRuns, args),
        'github_trigger_workflow': (args) => _run(_triggerWorkflow, args),
        'github_get_workflow_run_jobs': (args) =>
            _run(_getWorkflowRunJobs, args),
        'github_get_workflow_run_logs': (args) =>
            _run(_getWorkflowRunLogs, args),
        'github_get_or_create_draft_release': (args) =>
            _run(_getOrCreateDraftRelease, args),
        'github_upload_release_asset': (args) =>
            _run(_uploadReleaseAsset, args),
      };

  /// Resolves GitHub config, then runs [fn] with it.
  String _run(
    String Function(GhSyncConfig, Map<String, dynamic>) fn,
    Map<String, dynamic> args,
  ) {
    final config = _resolveConfig();
    if (config == null) return syncErr('GitHub not configured');
    return fn(config, args);
  }

  /// Builds GitHub config, or `null` when the token is missing.
  ///
  /// Headers mirror the async [GithubHttpClient]: Bearer auth plus the
  /// GitHub-recommended `Accept` and api-version headers.
  GhSyncConfig? _resolveConfig() {
    final reader = PropertyReader();
    final token = reader.getGithubToken();
    if (token == null || token.isEmpty) return null;
    return (
      baseUrl: reader.getGithubBasePath(),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      },
    );
  }
}

// ── Pull requests ──────────────────────────────────────────────────────

/// `github_get_pr` — GET `repos/{w}/{r}/pulls/{id}` (Java `pullRequest`).
String _getPr(GhSyncConfig c, Map<String, dynamic> a) =>
    syncBodyOrError(SyncHttpClient.get(_prUrl(c, a), headers: c.headers));

/// `github_list_prs` — first page (up to 100) of `repos/{w}/{r}/pulls`.
///
/// Java `listPullRequests`/`pullRequests`: state synonyms are normalized
/// (`opened`→`open`, `declined`/`merged`→`closed`) and `state=merged`
/// keeps only PRs with a `merged_at` timestamp.
String _listPrs(GhSyncConfig c, Map<String, dynamic> a) {
  final requested = syncAsStr(a['state']).trim().toLowerCase();
  final normalized = switch (requested) {
    'opened' => 'open',
    'declined' || 'merged' => 'closed',
    _ => requested,
  };
  final url = '${c.baseUrl}/${_repoSeg(a)}/pulls'
      '?state=$normalized&sort=updated&direction=desc&per_page=100&page=1';
  final resp = SyncHttpClient.get(url, headers: c.headers);
  final body = syncBodyOrError(resp);
  if (requested != 'merged' || !resp.isOk) return body;
  final decoded = syncTryDecode(body);
  final prs = decoded is List ? decoded : const [];
  final merged =
      prs.where((pr) => pr is Map && pr['merged_at'] != null).toList();
  return jsonEncode(merged);
}

/// `github_create_comment` — POST `repos/{w}/{r}/issues/{id}/comments`.
///
/// Dart-catalog tool (no Java counterpart); accepts the Java-family
/// `text` argument as well as the cataloged `body`.
String _createComment(GhSyncConfig c, Map<String, dynamic> a) =>
    _postIssueComment(c, a, a['text'] ?? a['body']);

/// `github_add_pr_comment` — POST `repos/{w}/{r}/issues/{id}/comments`.
String _addPrComment(GhSyncConfig c, Map<String, dynamic> a) =>
    _postIssueComment(c, a, a['text']);

/// Posts `{"body": text}` to the PR (issue-style) comments endpoint.
String _postIssueComment(
  GhSyncConfig c,
  Map<String, dynamic> a,
  dynamic text,
) =>
    _postJson(
      c,
      '${c.baseUrl}/${_repoSeg(a)}/issues/${_prId(a)}/comments',
      {'body': syncAsStr(text)},
    );

/// `github_add_pr_label` — POST `repos/{w}/{r}/issues/{id}/labels`.
String _addPrLabel(GhSyncConfig c, Map<String, dynamic> a) => _postJson(
      c,
      '${c.baseUrl}/${_repoSeg(a)}/issues/${_prId(a)}/labels',
      [syncAsStr(a['label'])],
    );

/// `github_remove_pr_label` — DELETE `repos/{w}/{r}/issues/{id}/labels/{l}`.
String _removePrLabel(GhSyncConfig c, Map<String, dynamic> a) =>
    syncBodyOrError(
      SyncHttpClient.delete(
        '${c.baseUrl}/${_repoSeg(a)}/issues/${_prId(a)}'
        '/labels/${Uri.encodeComponent(syncAsStr(a['label']))}',
        headers: c.headers,
      ),
    );

/// `github_merge_pr` — PUT `repos/{w}/{r}/pulls/{id}/merge`.
String _mergePr(GhSyncConfig c, Map<String, dynamic> a) {
  final body = <String, dynamic>{
    'merge_method': _orDefault(a['mergeMethod'], 'merge'),
  };
  _putIfNotBlank(body, 'commit_title', a['commitTitle']);
  _putIfNotBlank(body, 'commit_message', a['commitMessage']);
  return _putJson(
    c,
    '${c.baseUrl}/${_repoSeg(a)}/pulls/${_prId(a)}/merge',
    body,
  );
}

/// `github_get_pr_diff` — diff statistics (Java `getPullRequestDiff`).
///
/// Gated by `IS_READ_PULL_REQUEST_DIFF` (default on); failures degrade to
/// the empty stats object, never an error, mirroring the Java catch.
String _getPrDiff(GhSyncConfig c, Map<String, dynamic> a) {
  if (!PropertyReader().isReadPullRequestDiff()) {
    return jsonEncode(_emptyDiffStats);
  }
  final diff = _fetchPrDiff(c, a);
  if (diff == null) return jsonEncode(_emptyDiffStats);
  return jsonEncode(_parseDiffStats(diff));
}

/// `github_get_pr_diff_text` — raw unified diff text (Java parity).
String _getPrDiffText(GhSyncConfig c, Map<String, dynamic> a) {
  if (!PropertyReader().isReadPullRequestDiff()) return '';
  return _fetchPrDiff(c, a) ?? '';
}

/// GETs `pulls/{id}` with the `application/vnd.github.diff` accept header.
String? _fetchPrDiff(GhSyncConfig c, Map<String, dynamic> a) {
  final headers = {...c.headers, 'Accept': 'application/vnd.github.diff'};
  final resp = SyncHttpClient.get(_prUrl(c, a), headers: headers);
  return resp.isOk ? resp.body : null;
}

/// Java `parseDiffStats`: `+`/`-` line counts (excluding `+++`/`---`).
Map<String, dynamic> _parseDiffStats(String diff) {
  var added = 0;
  var removed = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      added++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      removed++;
    }
  }
  return {
    'stats': {
      'total': added + removed,
      'additions': added,
      'deletions': removed,
    },
    'changes': const <dynamic>[],
  };
}

/// The `IDiffStats.Empty()` shape returned when reading diffs is disabled.
const Map<String, dynamic> _emptyDiffStats = {
  'stats': {'total': 0, 'additions': 0, 'deletions': 0},
  'changes': <dynamic>[],
};

// ── Comments and review threads ────────────────────────────────────────

/// `github_get_pr_comments` — inline + discussion comments, sorted.
///
/// Java `pullRequestComments`: paginates `pulls/{id}/comments` and
/// `issues/{id}/comments`, concatenates both, sorts by creation date.
String _getPrComments(GhSyncConfig c, Map<String, dynamic> a) {
  final pages = _prCommentPages(c, a);
  final all = [...pages.inline, ...pages.issue];
  all.sort(
      (x, y) => syncAsStr(x['created']).compareTo(syncAsStr(y['created'])));
  return jsonEncode(all);
}

/// `github_get_pr_conversations` — inline threads + discussion entries.
///
/// Java `getPRConversations`: groups inline comments into threads by
/// `in_reply_to_id` (`{path, rootComment, replies, totalComments}` — the
/// Java `GitHubConversation.toJSON` shape), then appends one entry per
/// issue-style discussion comment.
String _getPrConversations(GhSyncConfig c, Map<String, dynamic> a) {
  final pages = _prCommentPages(c, a);
  return jsonEncode(_groupConversations(pages.inline, pages.issue));
}

/// Fetches both comment listings of a PR: inline review comments and
/// issue-style discussion comments.
({List<Map<String, dynamic>> inline, List<Map<String, dynamic>> issue})
    _prCommentPages(GhSyncConfig c, Map<String, dynamic> a) => (
          inline: _fetchPages(c, '${c.baseUrl}/${_prSeg(a)}/comments'),
          issue: _fetchPages(
            c,
            '${c.baseUrl}/${_repoSeg(a)}/issues/${_prId(a)}/comments',
          ),
        );

/// Groups [inline] comments into conversations, appends [issue] entries.
List<Map<String, dynamic>> _groupConversations(
  List<Map<String, dynamic>> inline,
  List<Map<String, dynamic>> issue,
) {
  final conversations = <Map<String, dynamic>>[];
  final byRootId = <String, Map<String, dynamic>>{};
  for (final comment in inline) {
    final id = syncAsStr(comment['id']);
    final replyTo = comment['in_reply_to_id'];
    final parent = replyTo == null ? null : byRootId[syncAsStr(replyTo)];
    if (parent == null) {
      final conversation = _conversation(comment);
      byRootId[id] = conversation;
      conversations.add(conversation);
    } else {
      (parent['replies'] as List).add(comment);
      parent['totalComments'] = 1 + (parent['replies'] as List).length;
    }
  }
  conversations.addAll(issue.map(_conversation));
  return conversations;
}

/// Builds one `GitHubConversation.toJSON()` object for [root].
Map<String, dynamic> _conversation(Map<String, dynamic> root) => {
      'path': root['path'],
      'rootComment': root,
      'replies': <dynamic>[],
      'totalComments': 1,
    };

/// `github_get_pr_review_threads` — GraphQL `reviewThreads` query.
String _getPrReviewThreads(GhSyncConfig c, Map<String, dynamic> a) {
  const query = 'query(\$owner: String!, \$repo: String!, \$prNumber: Int!) '
      '{ repository(owner: \$owner, name: \$repo) '
      '{ pullRequest(number: \$prNumber) { reviewThreads(first: 100) '
      '{ nodes { id isResolved path line startLine '
      'comments(first: 50) { nodes { databaseId body author { login } '
      'createdAt } } } } } } }';
  final prNumber = int.tryParse(_prId(a));
  if (prNumber == null) return syncErr('Invalid pullRequestId: ${_prId(a)}');
  return _graphQl(c, query, {
    'owner': syncAsStr(a['workspace']),
    'repo': syncAsStr(a['repository']),
    'prNumber': prNumber,
  });
}

/// `github_resolve_pr_thread` — GraphQL `resolveReviewThread` mutation.
String _resolvePrThread(GhSyncConfig c, Map<String, dynamic> a) {
  final threadId = syncAsStr(a['threadId']);
  final mutation =
      'mutation { resolveReviewThread(input: { threadId: "$threadId" }) '
      '{ thread { id isResolved } } }';
  return _graphQl(c, mutation, null);
}

/// `github_reply_to_pr_thread` — POST `pulls/{id}/comments` with
/// `in_reply_to` (Java `replyToPullRequestComment`).
String _replyToPrThread(GhSyncConfig c, Map<String, dynamic> a) {
  final raw = syncAsStr(a['inReplyToId'] ?? a['threadId']);
  final inReplyTo = int.tryParse(raw);
  if (inReplyTo == null) {
    return syncErr(
      "Invalid inReplyToId: expected a numeric GitHub comment ID, "
      "but got: '$raw'",
    );
  }
  return _postJson(c, '${c.baseUrl}/${_prSeg(a)}/comments', {
    'body': syncAsStr(a['text']),
    'in_reply_to': inReplyTo,
  });
}

/// `github_add_inline_comment` — POST `pulls/{id}/comments` (Java
/// `addInlineReviewComment`): resolves the head SHA when `commitId` is
/// blank, submits any pending review first (GitHub 422 guard), then
/// posts the comment.
String _addInlineComment(GhSyncConfig c, Map<String, dynamic> a) {
  final line = _intOrError(a['line'], 'line');
  if (line is! int) return line;
  final commitId = _inlineCommitId(c, a);
  if (commitId == null) {
    return syncErr(
      'Unable to resolve head commit SHA: empty pull request response '
      "for repo '${syncAsStr(a['workspace'])}/${syncAsStr(a['repository'])}', "
      "pull request '${_prId(a)}'.",
    );
  }
  final side = syncAsStr(a['side']).trim().toUpperCase();
  final resolvedSide = side.isEmpty ? 'RIGHT' : side;
  final body = <String, dynamic>{
    'body': syncAsStr(a['text']),
    'commit_id': commitId,
    'path': syncAsStr(a['path'] ?? a['filePath']),
    'line': line,
    'side': resolvedSide,
  };
  final startError = _addStartLine(body, a['startLine'], resolvedSide);
  if (startError != null) return startError;
  _submitPendingReview(c, a);
  return _postJson(c, '${c.baseUrl}/${_prSeg(a)}/comments', body);
}

/// Parses [value] as an int, returning a JSON error string when invalid.
dynamic _intOrError(dynamic value, String name) {
  final parsed = int.tryParse(syncAsStr(value).trim());
  if (parsed != null) return parsed;
  return syncErr(
    'Invalid $name: expected a numeric value, but got: '
    "'${syncAsStr(value)}'",
  );
}

/// Resolves `commitId`, fetching the PR head SHA when blank (Java parity).
String? _inlineCommitId(GhSyncConfig c, Map<String, dynamic> a) {
  final explicit = syncAsStr(a['commitId']).trim();
  if (explicit.isNotEmpty) return explicit;
  final resp = SyncHttpClient.get(_prUrl(c, a), headers: c.headers);
  final decoded = syncTryDecode(resp.isOk ? resp.body : '');
  final head = decoded is Map ? decoded['head'] : null;
  final sha = syncAsStr(head is Map ? head['sha'] : '');
  return sha.isEmpty ? null : sha;
}

/// Adds `start_line`/`start_side` for multi-line comments; error JSON
/// when `startLine` is present but non-numeric.
String? _addStartLine(
  Map<String, dynamic> body,
  dynamic startLine,
  String side,
) {
  final raw = syncAsStr(startLine).trim();
  if (raw.isEmpty) return null;
  final parsed = int.tryParse(raw);
  if (parsed == null) {
    return syncErr(
      "Invalid startLine: expected a numeric line number, but got: '$raw'",
    );
  }
  body['start_line'] = parsed;
  body['start_side'] = side;
  return null;
}

/// Submits any PENDING review before posting an inline comment —
/// best-effort, mirroring Java `submitPendingReview`.
void _submitPendingReview(GhSyncConfig c, Map<String, dynamic> a) {
  final url = '${c.baseUrl}/${_prSeg(a)}/reviews';
  final resp = SyncHttpClient.get(url, headers: c.headers);
  if (!resp.isOk) return;
  final decoded = syncTryDecode(resp.body);
  if (decoded is! List) return;
  for (final review in decoded) {
    if (review is Map && review['state'] == 'PENDING') {
      _postJson(c, '$url/${syncAsStr(review['id'])}/events', {
        'event': 'COMMENT',
        'body': '',
      });
    }
  }
}

/// POSTs a GraphQL `query` (+ optional [variables]) to `{base}/graphql`.
String _graphQl(
  GhSyncConfig c,
  String query,
  Map<String, dynamic>? variables,
) {
  final body = <String, dynamic>{'query': query};
  if (variables != null) body['variables'] = variables;
  return _postJson(c, '${c.baseUrl}/graphql', body);
}

// ── Commits, checks, Actions ───────────────────────────────────────────

/// `github_get_commit_check_runs` — GET `commits/{sha}/check-runs`.
String _getCommitCheckRuns(GhSyncConfig c, Map<String, dynamic> a) =>
    _getRepoPath(c, a, 'commits/${syncAsStr(a['commitSha'])}/check-runs');

/// `github_get_job_logs` — raw text logs from `actions/jobs/{id}/logs`.
String _getJobLogs(GhSyncConfig c, Map<String, dynamic> a) =>
    _getRepoPath(c, a, 'actions/jobs/${syncAsStr(a['jobId'])}/logs');

/// `github_get_workflow_run_jobs` — GET `actions/runs/{id}/jobs`.
String _getWorkflowRunJobs(GhSyncConfig c, Map<String, dynamic> a) =>
    _getRepoPath(c, a, 'actions/runs/${syncAsStr(a['runId'])}/jobs');

/// `github_list_workflow_runs` — GET `actions/runs` (or a workflow's
/// runs) with the optional `status`/`per_page`/`page`/`created` filters.
String _listWorkflowRuns(GhSyncConfig c, Map<String, dynamic> a) {
  final workflowId = syncAsStr(a['workflowId']).trim();
  final base = workflowId.isEmpty
      ? '${_repoSeg(a)}/actions/runs'
      : '${_repoSeg(a)}/actions/workflows/$workflowId/runs';
  final query = <String>[];
  void addIf(String key, String value) {
    if (value.isNotEmpty) query.add('$key=$value');
  }

  addIf('status', syncAsStr(a['status']).trim());
  addIf('per_page', syncAsStr(a['perPage']).trim());
  addIf('page', syncAsStr(a['page']).trim());
  addIf(
    'created',
    Uri.encodeQueryComponent(syncAsStr(a['created']).trim()),
  );
  final suffix = query.isEmpty ? '' : '?${query.join('&')}';
  return syncBodyOrError(
    SyncHttpClient.get('${c.baseUrl}/$base$suffix', headers: c.headers),
  );
}

/// `github_trigger_workflow` — POST `actions/workflows/{id}/dispatches`.
///
/// Returns Java's success message string on 2xx (the MCP tool returns a
/// plain String, not JSON).
String _triggerWorkflow(GhSyncConfig c, Map<String, dynamic> a) {
  final workflowId = syncAsStr(a['workflowId']);
  final body = <String, dynamic>{
    'ref': _orDefault(a['ref'], 'main'),
  };
  final inputs = syncAsStr(a['inputs']).trim();
  final decodedInputs = inputs.isEmpty ? null : syncTryDecode(inputs);
  if (decodedInputs is Map) body['inputs'] = decodedInputs;
  final resp = SyncHttpClient.post(
    '${c.baseUrl}/${_repoSeg(a)}/actions/workflows/$workflowId/dispatches',
    headers: c.headers,
    body: jsonEncode(body),
  );
  if (!resp.isOk) {
    return syncErr(
      "Workflow trigger failed for '$workflowId' "
      "(${resp.statusCode}): ${resp.body}",
    );
  }
  return "Workflow '$workflowId' triggered successfully on "
      '${syncAsStr(a['workspace'])}/${syncAsStr(a['repository'])}';
}

/// `github_get_workflow_run_logs` — download + extract the run's log ZIP.
///
/// Java `GitHubWorkflowUtils.downloadWorkflowRunLogs`: follow the 302 to
/// the pre-signed archive, then concatenate every `.txt` entry with
/// `--- name ---` separators.
String _getWorkflowRunLogs(GhSyncConfig c, Map<String, dynamic> a) =>
    fetchWorkflowRunLogs(
      baseUrl: c.baseUrl,
      headers: c.headers,
      repoSegment: _repoSeg(a),
      runId: syncAsStr(a['runId']),
    );

// ── Releases ───────────────────────────────────────────────────────────

/// `github_get_or_create_draft_release` — Java `getOrCreateDraftRelease`:
/// find by tag (or name), return drafts, error on published matches,
/// otherwise create a new draft release.
String _getOrCreateDraftRelease(GhSyncConfig c, Map<String, dynamic> a) {
  final tagName = syncAsStr(a['tagName']);
  final releaseName = syncIsBlank(a['releaseName'])
      ? tagName
      : syncAsStr(a['releaseName']).trim();
  final existing = _findReleaseByTagOrName(c, a, tagName, releaseName);
  if (existing != null) {
    if (existing['draft'] != true) {
      return syncErr(
        "Release '$releaseName' ($tagName) already exists but is not a "
        'draft release.',
      );
    }
    return jsonEncode(existing);
  }
  return _createDraftRelease(c, a, tagName, releaseName);
}

/// Pages `releases` until a tag match (immediate) or a short page.
Map<String, dynamic>? _findReleaseByTagOrName(
  GhSyncConfig c,
  Map<String, dynamic> a,
  String tagName,
  String releaseName,
) {
  Map<String, dynamic>? nameMatch;
  for (var page = 1;; page++) {
    final url = '${c.baseUrl}/${_repoSeg(a)}/releases'
        '?per_page=100&page=$page';
    final releases = _getJson(c, url);
    if (releases is! List) return nameMatch;
    final tagMatch = _tagMatchInPage(releases, tagName);
    if (tagMatch != null) return tagMatch;
    nameMatch ??= _nameMatchInPage(releases, releaseName);
    if (releases.length < 100) return nameMatch;
  }
}

/// The release tagged [tagName] on one releases page, or `null`.
Map<String, dynamic>? _tagMatchInPage(List releases, String tagName) {
  for (final release in releases) {
    if (release is Map && tagName == release['tag_name']) {
      return release.cast<String, dynamic>();
    }
  }
  return null;
}

/// The first release named [releaseName] on one releases page, or `null`.
Map<String, dynamic>? _nameMatchInPage(List releases, String releaseName) {
  for (final release in releases) {
    if (release is Map && releaseName == release['name']) {
      return release.cast<String, dynamic>();
    }
  }
  return null;
}

/// POSTs the draft-release creation body (Java `createRelease`).
String _createDraftRelease(
  GhSyncConfig c,
  Map<String, dynamic> a,
  String tagName,
  String releaseName,
) {
  final body = <String, dynamic>{
    'tag_name': tagName,
    'name': releaseName,
    'draft': true,
  };
  _putIfNotBlank(body, 'target_commitish', a['targetCommitish']);
  _putIfNotBlank(body, 'body', a['body']);
  return _postJson(c, '${c.baseUrl}/${_repoSeg(a)}/releases', body);
}

/// `github_upload_release_asset` — validates then binary-uploads the file
/// (see `github_release_assets.dart`).
String _uploadReleaseAsset(GhSyncConfig c, Map<String, dynamic> a) =>
    uploadReleaseAsset(
      baseUrl: c.baseUrl,
      headers: c.headers,
      args: a,
    );

// ── Shared helpers ─────────────────────────────────────────────────────

/// `repos/{workspace}/{repository}` URL segment from Java param names.
String _repoSeg(Map<String, dynamic> a) =>
    'repos/${syncAsStr(a['workspace'])}/${syncAsStr(a['repository'])}';

/// `repos/{workspace}/{repository}/pulls/{pullRequestId}` URL.
String _prUrl(GhSyncConfig c, Map<String, dynamic> a) =>
    '${c.baseUrl}/${_repoSeg(a)}/pulls/${_prId(a)}';

/// GETs `{base}/{repoSeg}/{suffix}` and returns the response body.
String _getRepoPath(GhSyncConfig c, Map<String, dynamic> a, String suffix) =>
    syncBodyOrError(SyncHttpClient.get(
      '${c.baseUrl}/${_repoSeg(a)}/$suffix',
      headers: c.headers,
    ));

/// `repos/{workspace}/{repository}/pulls/{pullRequestId}` segment.
String _prSeg(Map<String, dynamic> a) => '${_repoSeg(a)}/pulls/${_prId(a)}';

/// The pull request id argument, as a string (agents pass `String(prId)`).
///
/// Accepts both Java spellings: `pullRequestId` and the diff tools'
/// `pullRequestID`.
String _prId(Map<String, dynamic> a) =>
    syncAsStr(a['pullRequestId'] ?? a['pullRequestID']);

/// Fetches all pages of a comment listing endpoint (100 per page).
List<Map<String, dynamic>> _fetchPages(GhSyncConfig c, String urlBase) {
  final out = <Map<String, dynamic>>[];
  for (var page = 1;; page++) {
    final resp = SyncHttpClient.get('$urlBase?per_page=100&page=$page',
        headers: c.headers);
    if (!resp.isOk) break;
    final decoded = syncTryDecode(resp.body);
    if (decoded is! List) break;
    out.addAll(decoded.whereType<Map>().cast<Map<String, dynamic>>());
    if (decoded.length < 100) break;
  }
  return out;
}

/// GETs [url] and decodes the JSON body; `null` on failure or non-2xx.
dynamic _getJson(GhSyncConfig c, String url) {
  final resp = SyncHttpClient.get(url, headers: c.headers);
  if (!resp.isOk) return null;
  return syncTryDecode(resp.body);
}

/// POSTs [body] as JSON and returns the response body.
String _postJson(GhSyncConfig c, String url, Object? body) => syncBodyOrError(
      SyncHttpClient.post(url, headers: c.headers, body: jsonEncode(body)),
    );

/// PUTs [body] as JSON and returns the response body.
String _putJson(GhSyncConfig c, String url, Object? body) => syncBodyOrError(
      SyncHttpClient.put(url, headers: c.headers, body: jsonEncode(body)),
    );

/// Sets `body[key] = value.trim()` when [value] is non-blank.
void _putIfNotBlank(Map<String, dynamic> body, String key, dynamic value) {
  if (!syncIsBlank(value)) body[key] = syncAsStr(value).trim();
}

/// `value` trimmed, or [fallback] when blank.
String _orDefault(dynamic value, String fallback) =>
    syncIsBlank(value) ? fallback : syncAsStr(value).trim();
