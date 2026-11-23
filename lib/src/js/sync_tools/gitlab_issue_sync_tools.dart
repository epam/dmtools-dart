/// Issue-tracker sync executors — Java `GitLabIssues.java` (dm.ai #876).
///
/// Part of the `gitlab_sync_tools.dart` library so the handlers share the
/// sync config/HTTP helpers. Every issue tool resolves its reference from
/// explicit parts (`workspace`/`repository`/`issueNumber`, or the legacy
/// `project`/`iid` pair), a composite `key` (`namespace/project#123`,
/// `gl-123`, or a bare IID), or the configured `GITLAB_WORKSPACE` /
/// `GITLAB_REPOSITORY` defaults — Java `GitLabIssues.resolveIssueRef`
/// parity.
part of 'gitlab_sync_tools.dart';

/// A resolved GitLab issue reference for one sync call.
class _GlSyncIssueRef {
  final String projectPath;
  final String iid;
  const _GlSyncIssueRef(this.projectPath, this.iid);

  /// `projects/<encoded>/issues/<iid>` API path segment.
  String get issueSeg =>
      'projects/${Uri.encodeComponent(projectPath)}/issues/$iid';
}

/// `gl-123` router key convention.
final RegExp _syncGlRouterKey = RegExp(r'^gl-(\d+)$', caseSensitive: false);

/// Bare numeric IID pattern.
final RegExp _syncGlBareDigits = RegExp(r'^\d+$');

/// Statuses that close a GitLab issue (Java parity).
const _syncGlClosedStatuses = {'done', 'closed', 'completed', 'resolved'};

/// Statuses that reopen a GitLab issue (Java parity).
const _syncGlOpenStatuses = {'open', 'opened', 'reopen', 'reopened'};

/// Resolves the GitLab issue reference from tool [args] (Java
/// `GitLabIssues.resolveIssueRef`). Returns a JSON error string when
/// unresolved.
Object _resolveGlSyncIssueRef(Map<String, dynamic> args) {
  var projectPath = _glFirstStr(args, const ['project']);
  if (projectPath.isEmpty) {
    final ws = _glFirstStr(args, const ['workspace', 'owner']);
    final rp = _glFirstStr(args, const ['repository', 'repo']);
    if (ws.isNotEmpty && rp.isNotEmpty) projectPath = '$ws/$rp';
  }
  var iid = _glFirstStr(
    args,
    const ['issueNumber', 'number', 'iid', 'pullRequestId'],
  );
  final key = syncAsStr(args['key']).trim();
  if (key.isNotEmpty && (projectPath.isEmpty || iid.isEmpty)) {
    final fromKey = _applyGlSyncIssueKey(key, projectPath, iid);
    if (fromKey == null) {
      return syncErr(
        "Cannot parse GitLab issue key: '$key'. Expected "
        "'namespace/project#123', 'gl-123', or a bare issue IID.",
      );
    }
    projectPath = fromKey.$1;
    iid = fromKey.$2;
  }
  if (projectPath.isEmpty) {
    final reader = PropertyReader();
    final ws = reader.getGitLabWorkspace()?.trim() ?? '';
    final rp = reader.getGitLabRepository()?.trim() ?? '';
    if (ws.isNotEmpty && rp.isNotEmpty) projectPath = '$ws/$rp';
  }
  if (projectPath.isEmpty || iid.isEmpty) {
    return syncErr(
      'GitLab issue reference requires workspace/repository/issueNumber '
      "or a composite key 'namespace/project#123' (or 'gl-123' with a "
      'configured default project).',
    );
  }
  return _GlSyncIssueRef(projectPath, iid);
}

/// Applies composite `namespace/project#123`, `gl-123`, or bare IID [key].
(String, String)? _applyGlSyncIssueKey(
  String key,
  String projectPath,
  String iid,
) {
  var proj = projectPath;
  var numStr = iid;
  final sep = key.lastIndexOf('#');
  final router = _syncGlRouterKey.firstMatch(key);
  if (sep > 0 &&
      sep < key.length - 1 &&
      _syncGlBareDigits.hasMatch(key.substring(sep + 1))) {
    if (proj.isEmpty) proj = key.substring(0, sep);
    if (numStr.isEmpty) numStr = key.substring(sep + 1);
    return (proj, numStr);
  }
  if (router != null) {
    if (numStr.isEmpty) numStr = router.group(1)!;
    return (proj, numStr);
  }
  if (_syncGlBareDigits.hasMatch(key)) {
    if (numStr.isEmpty) numStr = key;
    return (proj, numStr);
  }
  return null;
}

/// Resolves a GitLab project path from `workspace`/`repository`, `project`,
/// `key`, or configured defaults. Returns `null` when unresolved.
String? _resolveGlSyncProjectPath(Map<String, dynamic> args) {
  final key = syncAsStr(args['key']).trim();
  if (key.contains('/')) return key;
  final project = _glFirstStr(args, const ['project']);
  if (project.isNotEmpty) return project;
  final reader = PropertyReader();
  final ws = _glFirstStr(args, const ['workspace', 'owner']).isNotEmpty
      ? _glFirstStr(args, const ['workspace', 'owner'])
      : reader.getGitLabWorkspace()?.trim() ?? '';
  final rp = _glFirstStr(args, const ['repository', 'repo']).isNotEmpty
      ? _glFirstStr(args, const ['repository', 'repo'])
      : reader.getGitLabRepository()?.trim() ?? '';
  if (ws.isEmpty || rp.isEmpty) return null;
  return '$ws/$rp';
}

/// Runs [fn] with the resolved GitLab issue reference, or returns the JSON
/// error string.
String _withGlIssueRef(
  _GitlabConfig config,
  Map<String, dynamic> args,
  String Function(_GitlabConfig, _GlSyncIssueRef) fn,
) {
  final resolved = _resolveGlSyncIssueRef(args);
  return resolved is _GlSyncIssueRef
      ? fn(config, resolved)
      : resolved as String;
}

/// First non-blank string among [names] in [args].
String _glFirstStr(Map<String, dynamic> args, List<String> names) {
  for (final name in names) {
    final value = syncAsStr(args[name]).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// `gitlab_get_issue` — GET `projects/{id}/issues/{iid}`.
String _getIssue(_GitlabConfig c, Map<String, dynamic> a) => _withGlIssueRef(
      c,
      a,
      (c, ref) => syncBodyOrError(
        SyncHttpClient.get('${c.baseUrl}/${ref.issueSeg}', headers: c.headers),
      ),
    );

/// `gitlab_search_issues` — GET `projects/{id}/issues?state=…&search=…`.
String _searchIssues(_GitlabConfig c, Map<String, dynamic> a) {
  final projectPath = _resolveGlSyncProjectPath(a);
  if (projectPath == null) {
    return syncErr(
      'GitLab project is not configured. Pass workspace/repository '
      'or set GITLAB_WORKSPACE and GITLAB_REPOSITORY.',
    );
  }
  final rawState = syncAsStr(a['state']).trim();
  final state = rawState.isEmpty ? 'all' : rawState;
  final query = syncAsStr(a['query']);
  final url = '${c.baseUrl}/projects/${Uri.encodeComponent(projectPath)}/issues'
      '?state=${Uri.encodeQueryComponent(state)}'
      '&per_page=100'
      '&search=${Uri.encodeQueryComponent(query)}';
  return syncBodyOrError(SyncHttpClient.get(url, headers: c.headers));
}

/// `gitlab_create_issue` — POST `projects/{id}/issues`.
String _createIssue(_GitlabConfig c, Map<String, dynamic> a) {
  final projectPath = _resolveGlSyncProjectPath(a);
  if (projectPath == null) {
    return syncErr(
      'GitLab project is not configured. Pass workspace/repository '
      'or set GITLAB_WORKSPACE and GITLAB_REPOSITORY.',
    );
  }
  final payload = <String, dynamic>{'title': syncAsStr(a['title'])};
  final desc = _glFirstStr(a, const ['body', 'description']);
  if (desc.isNotEmpty) payload['description'] = desc;
  return syncPostJson(
    c.headers,
    '${c.baseUrl}/projects/${Uri.encodeComponent(projectPath)}/issues',
    jsonEncode(payload),
  );
}

/// `gitlab_close_issue` — PUT `state_event=close`.
String _closeIssue(_GitlabConfig c, Map<String, dynamic> a) => _withGlIssueRef(
      c,
      a,
      (c, ref) => _putBody(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        jsonEncode({'state_event': 'close'}),
      ),
    );

/// `gitlab_reopen_issue` — PUT `state_event=reopen`.
String _reopenIssue(_GitlabConfig c, Map<String, dynamic> a) => _withGlIssueRef(
      c,
      a,
      (c, ref) => _putBody(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        jsonEncode({'state_event': 'reopen'}),
      ),
    );

/// `gitlab_move_issue_to_status` — close/reopen/scoped-label semantics.
String _moveIssueToStatus(_GitlabConfig c, Map<String, dynamic> a) {
  final status = syncAsStr(a['statusName']).trim();
  if (status.isEmpty) return syncErr('statusName is required');
  final resolved = _resolveGlSyncIssueRef(a);
  if (resolved is! _GlSyncIssueRef) return resolved as String;
  final lower = status.toLowerCase();
  if (_syncGlClosedStatuses.contains(lower)) {
    return _putBody(
      c,
      '${c.baseUrl}/${resolved.issueSeg}',
      jsonEncode({'state_event': 'close'}),
    );
  }
  if (_syncGlOpenStatuses.contains(lower)) {
    return _putBody(
      c,
      '${c.baseUrl}/${resolved.issueSeg}',
      jsonEncode({'state_event': 'reopen'}),
    );
  }
  return _putBody(
    c,
    '${c.baseUrl}/${resolved.issueSeg}',
    jsonEncode({'add_labels': 'status::$status'}),
  );
}

/// `gitlab_assign_issue` — looks up user via `/users?username=…`, then PUTs
/// `assignee_ids`.
String _assignIssue(_GitlabConfig c, Map<String, dynamic> a) {
  final user = syncAsStr(a['user']).trim();
  if (user.isEmpty) return syncErr('GitLab username must not be empty');
  final resolved = _resolveGlSyncIssueRef(a);
  if (resolved is! _GlSyncIssueRef) return resolved as String;
  final usersRaw = syncBodyOrError(
    SyncHttpClient.get(
      '${c.baseUrl}/users?username=${Uri.encodeQueryComponent(user)}',
      headers: c.headers,
    ),
  );
  final users = syncTryDecode(usersRaw);
  if (users is! List || users.isEmpty || users.first is! Map) {
    return syncErr('GitLab user not found: $user');
  }
  final userId = (users.first as Map)['id'];
  return _putBody(
    c,
    '${c.baseUrl}/${resolved.issueSeg}',
    jsonEncode({
      'assignee_ids': [userId],
    }),
  );
}

/// `gitlab_add_issue_label` — PUT `add_labels` on the issue.
String _addIssueLabel(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => _putBody(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        jsonEncode({'add_labels': syncAsStr(a['label'])}),
      ),
    );

/// `gitlab_remove_issue_label` — PUT `remove_labels` on the issue.
String _removeIssueLabel(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => _putBody(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        jsonEncode({'remove_labels': syncAsStr(a['label'])}),
      ),
    );

/// `gitlab_create_issue_comment` — POST `{body}` to `…/issues/{iid}/notes`.
String _createIssueComment(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => syncPostJson(
        c.headers,
        '${c.baseUrl}/${ref.issueSeg}/notes',
        jsonEncode({
          'body': _glFirstStr(a, const ['body', 'text', 'comment']),
        }),
      ),
    );

/// `gitlab_get_issue_comments` — paginated GET `…/issues/{iid}/notes?sort=asc`.
String _getIssueComments(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => jsonEncode(
        gitlabFetchAllPages(
          c.baseUrl,
          c.headers,
          '${ref.issueSeg}/notes?sort=asc',
        ),
      ),
    );
