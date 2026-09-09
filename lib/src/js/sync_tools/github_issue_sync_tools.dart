/// Issue-tracker sync executors — Java `GitHubIssues.java` (dm.ai #543).
///
/// Part of the `github_sync_tools.dart` library so the handlers share the
/// sync config/HTTP helpers. Every issue tool resolves its reference from
/// explicit parts (`owner`/`repo`/`number`, or the PR-family
/// `workspace`/`repository`/`pullRequestId` spellings), a composite `key`
/// (`owner/repo#123` or a bare number), or the configured
/// `SOURCE_GITHUB_WORKSPACE` / `SOURCE_GITHUB_REPOSITORY` defaults — Java
/// `resolveIssueRef` parity.
part of 'github_sync_tools.dart';

/// The resolved issue reference for one sync call.
class _SyncIssueRef {
  final String owner;
  final String repo;
  final int number;
  const _SyncIssueRef(this.owner, this.repo, this.number);

  /// `repos/{owner}/{repo}` URL segment.
  String get repoSeg => 'repos/$owner/$repo';

  /// `repos/{owner}/{repo}/issues/{number}` URL segment.
  String get issueSeg => '$repoSeg/issues/$number';
}

/// Composite issue-key pattern: `owner/repo#123`.
final RegExp _syncCompositeKey = RegExp(r'^[\w.-]+/[\w.-]+#(\d+)$');

/// Bare issue-number pattern: `123`.
final RegExp _syncBareNumber = RegExp(r'^\d+$');

/// Resolves the issue reference from tool [args] (Java
/// `GitHubIssues.resolveIssueRef` + `BasicGithub` defaults).
///
/// Returns a JSON error string when the reference cannot be resolved.
Object _resolveSyncIssueRef(Map<String, dynamic> args) {
  var owner = _firstStr(args, const ['owner', 'workspace']);
  var repo = _firstStr(args, const ['repo', 'repository']);
  var number = _firstInt(args, const ['number', 'issueNumber', 'pullRequestId']);
  final key = syncAsStr(args['key']).trim();
  if (key.isNotEmpty) {
    final composite = _syncCompositeKey.firstMatch(key);
    if (composite != null) {
      number = int.parse(composite.group(1)!);
      owner = key.substring(0, key.indexOf('/'));
      repo = key.substring(key.indexOf('/') + 1, key.indexOf('#'));
    } else if (_syncBareNumber.hasMatch(key)) {
      number = int.parse(key);
    } else {
      return syncErr(
        "Cannot parse GitHub issue key: '$key'. Expected 'owner/repo#123' "
        'or a bare issue number.',
      );
    }
  }
  final reader = PropertyReader();
  if (owner.trim().isEmpty) {
    owner = reader.getGithubWorkspace()?.trim() ?? '';
  }
  if (repo.trim().isEmpty) {
    repo = reader.getGithubRepository()?.trim() ?? '';
  }
  if (owner.isEmpty || repo.isEmpty || number == null) {
    return syncErr(
      "Issue reference requires owner/repo/number or a composite key "
      "'owner/repo#123'.",
    );
  }
  return _SyncIssueRef(owner, repo, number);
}

/// Runs [fn] with the resolved issue reference, or returns the JSON error.
String _withIssueRef(
  Map<String, dynamic> args,
  String Function(GhSyncConfig, _SyncIssueRef) fn,
) =>
    _run((config, args) {
      final resolved = _resolveSyncIssueRef(args);
      return resolved is _SyncIssueRef ? fn(config, resolved) : resolved as String;
    }, args);

/// First non-blank string among [names] in [args].
String _firstStr(Map<String, dynamic> args, List<String> names) {
  for (final name in names) {
    final value = syncAsStr(args[name]).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// First parseable int among [names] in [args].
int? _firstInt(Map<String, dynamic> args, List<String> names) {
  for (final name in names) {
    final value = args[name];
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(syncAsStr(value).trim());
    if (parsed != null) return parsed;
  }
  return null;
}

/// Synchronous executors for the issue-tracker family.
class GitHubIssueSyncTools {
  /// Creates the issue-family sync tooling.
  const GitHubIssueSyncTools();

  /// Issue-family executors, keyed by tool name.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'github_get_issue': (args) => _run(_getIssue, args),
        'github_search_issues': (args) => _run(_searchIssues, args),
        'github_create_issue': (args) => _run(_createIssue, args),
        'github_close_issue': (args) => _run(_closeIssue, args),
        'github_reopen_issue': (args) => _run(_reopenIssue, args),
        'github_move_issue_to_status': (args) =>
            _run(_moveIssueToStatus, args),
        'github_assign_issue': (args) => _run(_assignIssue, args),
        'github_add_labels': (args) => _run(_addIssueLabels, args),
        'github_remove_label': (args) => _run(_removeIssueLabel, args),
        'github_create_comment': (args) => _run(_createComment, args),
        'github_get_pr_comments': (args) => _run(_getPrComments, args),
      };

  /// `github_get_issue` — GET `repos/{o}/{r}/issues/{n}`.
  String _getIssue(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(a, (c, ref) => syncBodyOrError(SyncHttpClient.get(
            '${c.baseUrl}/${ref.issueSeg}',
            headers: c.headers,
          )));

  /// `github_search_issues` — GET `search/issues?q=...&per_page=100`.
  ///
  /// Java `GitHubIssues.searchIssues`: the query is scoped with
  /// `repo:<workspace>/<repository>` when it has no `repo:` term and the
  /// defaults are configured.
  String _searchIssues(GhSyncConfig c, Map<String, dynamic> a) {
    var query = syncAsStr(a['query']);
    final reader = PropertyReader();
    final ws = _firstStr(a, const ['workspace']).isNotEmpty
        ? _firstStr(a, const ['workspace'])
        : reader.getGithubWorkspace()?.trim() ?? '';
    final rp = _firstStr(a, const ['repository']).isNotEmpty
        ? _firstStr(a, const ['repository'])
        : reader.getGithubRepository()?.trim() ?? '';
    if (!query.contains('repo:') && ws.isNotEmpty && rp.isNotEmpty) {
      query = 'repo:$ws/$rp $query';
    }
    return syncBodyOrError(SyncHttpClient.get(
      '${c.baseUrl}/search/issues'
      '?q=${Uri.encodeQueryComponent(query)}&per_page=100',
      headers: c.headers,
    ));
  }

  /// `github_create_issue` — POST `repos/{o}/{r}/issues`.
  ///
  /// Java `GitHubIssues.createIssue`: `key` optionally carries the
  /// composite project reference `owner/repo`; blank parts fall back to
  /// the configured defaults.
  String _createIssue(GhSyncConfig c, Map<String, dynamic> a) {
    var owner = _firstStr(a, const ['owner']);
    var repo = _firstStr(a, const ['repo']);
    final key = syncAsStr(a['key']).trim();
    if (key.contains('/')) {
      owner = key.substring(0, key.indexOf('/'));
      repo = key.substring(key.indexOf('/') + 1);
    }
    final reader = PropertyReader();
    if (owner.isEmpty) {
      owner = reader.getGithubWorkspace()?.trim() ?? '';
    }
    if (repo.isEmpty) {
      repo = reader.getGithubRepository()?.trim() ?? '';
    }
    if (owner.isEmpty || repo.isEmpty) {
      return syncErr(
        "github_create_issue requires owner/repo or a composite "
        "key/project 'owner/repo'.",
      );
    }
    final payload = <String, dynamic>{'title': syncAsStr(a['title'])};
    final body = a['body'];
    if (body != null && syncAsStr(body).trim().isNotEmpty) {
      payload['body'] = body;
    }
    return syncBodyOrError(SyncHttpClient.post(
      '${c.baseUrl}/repos/$owner/$repo/issues',
      headers: c.headers,
      body: jsonEncode(payload),
    ));
  }

  /// `github_close_issue` — PATCH `repos/{o}/{r}/issues/{n}` state closed.
  String _closeIssue(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(a, (c, ref) => _syncSetIssueState(c, ref, 'closed'));

  /// `github_reopen_issue` — PATCH `repos/{o}/{r}/issues/{n}` state open.
  String _reopenIssue(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(a, (c, ref) => _syncSetIssueState(c, ref, 'open'));

  /// `github_move_issue_to_status` — close/reopen/label semantics.
  String _moveIssueToStatus(GhSyncConfig c, Map<String, dynamic> a) {
    final status = syncAsStr(a['statusName']).trim();
    if (status.isEmpty) return syncErr('statusName is required');
    final resolved = _resolveSyncIssueRef(a);
    if (resolved is! _SyncIssueRef) return resolved as String;
    final lowered = status.toLowerCase();
    if (_syncClosedStatuses.contains(lowered)) {
      return _syncSetIssueState(c, resolved, 'closed');
    }
    if (_syncOpenStatuses.contains(lowered)) {
      return _syncSetIssueState(c, resolved, 'open');
    }
    return _syncAddLabels(c, resolved, [status]);
  }

  /// `github_assign_issue` — POST `repos/{o}/{r}/issues/{n}/assignees`.
  String _assignIssue(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(a, (c, ref) => syncBodyOrError(SyncHttpClient.post(
            '${c.baseUrl}/${ref.issueSeg}/assignees',
            headers: c.headers,
            body: jsonEncode({
              'assignees': [syncAsStr(a['user'])],
            }),
          )));

  /// `github_add_labels` — POST `repos/{o}/{r}/issues/{n}/labels`.
  String _addIssueLabels(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(
        a,
        (c, ref) => _syncAddLabels(c, ref, (a['labels'] as List?) ?? const []),
      );

  /// `github_remove_label` — DELETE
  /// `repos/{o}/{r}/issues/{n}/labels/{label}`.
  String _removeIssueLabel(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(
        a,
        (c, ref) => syncBodyOrError(SyncHttpClient.delete(
              '${c.baseUrl}/${ref.issueSeg}'
              '/labels/${Uri.encodeComponent(syncAsStr(a['label']))}',
              headers: c.headers,
            )),
      );

  /// `github_create_comment` — POST
  /// `repos/{o}/{r}/issues/{n}/comments` with the comment body.
  String _createComment(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(a, (c, ref) => _syncPostIssueComment(c, ref,
          syncAsStr(a['body'] ?? a['text'] ?? a['comment'])));

  /// `github_get_pr_comments` — inline + discussion comments, sorted.
  ///
  /// Java `GitHubIssues.pullRequestComments`: paginates
  /// `pulls/{n}/comments` (404-tolerant — plain issues have no inline
  /// comments) and `issues/{n}/comments`, concatenates both, sorts by
  /// creation date.
  String _getPrComments(GhSyncConfig c, Map<String, dynamic> a) =>
      _withIssueRef(a, (c, ref) {
        final inline = <Map<String, dynamic>>[];
        final resp = SyncHttpClient.get(
          '${c.baseUrl}/${ref.repoSeg}/pulls/${ref.number}/comments'
          '?per_page=100',
          headers: c.headers,
        );
        if (resp.isOk) {
          final decoded = syncTryDecode(resp.body);
          if (decoded is List) {
            inline.addAll(
                decoded.whereType<Map>().cast<Map<String, dynamic>>());
          }
        }
        final issue = _syncIssueComments(c, ref);
        final all = [...inline, ...issue];
        all.sort((x, y) =>
            syncAsStr(x['created']).compareTo(syncAsStr(y['created'])));
        return jsonEncode(all);
      });
}

/// Statuses that close the issue (Java parity).
const _syncClosedStatuses = {'done', 'closed', 'completed', 'resolved'};

/// Statuses that reopen the issue (Java parity).
const _syncOpenStatuses = {
  'open',
  'reopened',
  'reopen',
  'todo',
  'backlog',
  'in progress',
};

/// PATCHes the issue state (shared by close/reopen).
String _syncSetIssueState(GhSyncConfig c, _SyncIssueRef ref, String state) =>
    syncBodyOrError(SyncHttpClient.patch(
      '${c.baseUrl}/${ref.issueSeg}',
      headers: c.headers,
      body: jsonEncode({'state': state}),
    ));

/// POSTs the label array (shared by add-labels and move-to-status).
String _syncAddLabels(GhSyncConfig c, _SyncIssueRef ref, List labels) =>
    syncBodyOrError(SyncHttpClient.post(
      '${c.baseUrl}/${ref.issueSeg}/labels',
      headers: c.headers,
      body: jsonEncode({'labels': labels}),
    ));

/// POSTs `{"body": text}` to the issue-style comments endpoint.
String _syncPostIssueComment(GhSyncConfig c, _SyncIssueRef ref, String text) =>
    syncBodyOrError(SyncHttpClient.post(
      '${c.baseUrl}/${ref.issueSeg}/comments',
      headers: c.headers,
      body: jsonEncode({'body': text}),
    ));

/// GETs the issue-style discussion comments page.
List<Map<String, dynamic>> _syncIssueComments(
  GhSyncConfig c,
  _SyncIssueRef ref,
) {
  final resp = SyncHttpClient.get(
    '${c.baseUrl}/${ref.issueSeg}/comments?per_page=100',
    headers: c.headers,
  );
  if (!resp.isOk) return const [];
  final decoded = syncTryDecode(resp.body);
  return decoded is List
      ? decoded.whereType<Map>().cast<Map<String, dynamic>>().toList()
      : const [];
}
