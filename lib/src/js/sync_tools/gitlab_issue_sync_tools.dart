/// Issue-tracker sync executors — Java `GitLabIssues.java` (dm.ai #876).
///
/// Part of the `gitlab_sync_tools.dart` library so the handlers share the
/// sync config/HTTP helpers. Every issue tool resolves its reference from
/// explicit parts (`workspace`/`repository`/`issueNumber`, or the legacy
/// `project`/`iid` pair), a composite `key` (`namespace/project#123`,
/// `gl-123`, or a bare IID), or the configured `CI_PROJECT_PATH` /
/// `GITLAB_WORKSPACE` + `GITLAB_REPOSITORY` defaults — Java
/// `GitLabIssues.resolveIssueRef` parity.
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

/// Parsed composite/partial GitLab sync key parts.
typedef _GlSyncKeyParts = ({String projectPath, String iid});

/// Resolves the GitLab issue reference from tool [args] (Java
/// `GitLabIssues.resolveIssueRef`). Returns a JSON error string when
/// unresolved.
Object _resolveGlSyncIssueRef(Map<String, dynamic> args) {
  final initialProj = _glExplicitProject(args);
  final initialIid = _glFirstStr(
    args,
    const ['issueNumber', 'number', 'iid', 'pullRequestId'],
  );
  final key = syncAsStr(args['key']).trim();
  final parsed = _parseGlSyncIssueKey(key);
  if (key.isNotEmpty && parsed == null) {
    return syncErr(
      "Cannot parse GitLab issue key: '$key'. Expected "
      "'namespace/project#123', 'gl-123', or a bare issue IID.",
    );
  }
  final projFromKey =
      initialProj.isNotEmpty ? initialProj : (parsed?.projectPath ?? '');
  final finalProj =
      projFromKey.isNotEmpty ? projFromKey : _glConfiguredProjectPath();
  final finalIid = initialIid.isNotEmpty ? initialIid : (parsed?.iid ?? '');
  if (finalProj.isEmpty || finalIid.isEmpty) {
    return syncErr(
      'GitLab issue reference requires workspace/repository/issueNumber '
      "or a composite key 'namespace/project#123' (or 'gl-123' with a "
      'configured default project).',
    );
  }
  return _GlSyncIssueRef(finalProj, finalIid);
}

String _glExplicitProject(Map<String, dynamic> args) {
  final direct = _glFirstStr(args, const ['project']);
  if (direct.isNotEmpty) return direct;
  final ws = _glFirstStr(args, const ['workspace', 'owner']);
  final rp = _glFirstStr(args, const ['repository', 'repo']);
  return (ws.isNotEmpty && rp.isNotEmpty) ? '$ws/$rp' : '';
}

String _glConfiguredProjectPath() {
  final r = PropertyReader();
  final ci = syncAsStr(r.getValue('CI_PROJECT_PATH')).trim();
  if (ci.contains('/')) return ci;
  final w = (r.getGitLabWorkspace() ?? '').trim();
  final p = (r.getGitLabRepository() ?? '').trim();
  return (w.isNotEmpty && p.isNotEmpty) ? '$w/$p' : '';
}

/// Parses composite `namespace/project#123`, `gl-123`, or bare IID [key].
_GlSyncKeyParts? _parseGlSyncIssueKey(String key) {
  if (key.isEmpty) return (projectPath: '', iid: '');
  final sep = key.lastIndexOf('#');
  if (sep > 0 &&
      sep < key.length - 1 &&
      _syncGlBareDigits.hasMatch(key.substring(sep + 1))) {
    return (
      projectPath: key.substring(0, sep),
      iid: key.substring(sep + 1),
    );
  }
  final router = _syncGlRouterKey.firstMatch(key)?.group(1);
  if (router != null) return (projectPath: '', iid: router);
  if (_syncGlBareDigits.hasMatch(key)) return (projectPath: '', iid: key);
  return null;
}

/// Resolves a GitLab project path from `workspace`/`repository`, `project`,
/// `key`, or configured defaults. Returns `null` when unresolved.
String? _resolveGlSyncProjectPath(Map<String, dynamic> args) {
  final key = syncAsStr(args['key']).trim();
  if (key.contains('/')) return key;
  final explicit = _glExplicitProject(args);
  if (explicit.isNotEmpty) return explicit;
  final configured = _glConfiguredProjectPath();
  return configured.isNotEmpty ? configured : null;
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
String _glFirstStr(Map<String, dynamic> args, List<String> names) =>
    syncFirstStr(args, names);

String _putIssueJson(_GitlabConfig c, String url, Map<String, dynamic> body) =>
    syncStrictBodyOrError(
      SyncHttpClient.put(url, headers: c.headers, body: jsonEncode(body)),
    );

/// `gitlab_get_issue` — GET `projects/{id}/issues/{iid}`.
String _getIssue(_GitlabConfig c, Map<String, dynamic> a) => _withGlIssueRef(
      c,
      a,
      (c, ref) => syncStrictBodyOrError(
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
  return syncStrictBodyOrError(SyncHttpClient.get(url, headers: c.headers));
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
  return syncStrictBodyOrError(
    SyncHttpClient.post(
      '${c.baseUrl}/projects/${Uri.encodeComponent(projectPath)}/issues',
      headers: c.headers,
      body: jsonEncode(payload),
    ),
  );
}

/// `gitlab_close_issue` — PUT `state_event=close`.
String _closeIssue(_GitlabConfig c, Map<String, dynamic> a) => _withGlIssueRef(
      c,
      a,
      (c, ref) => _putIssueJson(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        const {'state_event': 'close'},
      ),
    );

/// `gitlab_reopen_issue` — PUT `state_event=reopen`.
String _reopenIssue(_GitlabConfig c, Map<String, dynamic> a) => _withGlIssueRef(
      c,
      a,
      (c, ref) => _putIssueJson(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        const {'state_event': 'reopen'},
      ),
    );

/// `gitlab_move_issue_to_status` — close/reopen/scoped-label semantics.
String _moveIssueToStatus(_GitlabConfig c, Map<String, dynamic> a) {
  final status = syncAsStr(a['statusName']).trim();
  if (status.isEmpty) return syncErr('statusName is required');
  final resolved = _resolveGlSyncIssueRef(a);
  if (resolved is! _GlSyncIssueRef) return resolved as String;
  final lower = status.toLowerCase();
  final payload = _syncGlClosedStatuses.contains(lower)
      ? const <String, dynamic>{'state_event': 'close'}
      : _syncGlOpenStatuses.contains(lower)
          ? const <String, dynamic>{'state_event': 'reopen'}
          : <String, dynamic>{'add_labels': 'status::$status'};
  return _putIssueJson(c, '${c.baseUrl}/${resolved.issueSeg}', payload);
}

/// `gitlab_assign_issue` — looks up user via `/users?username=…`, then PUTs
/// `assignee_ids`.
String _assignIssue(_GitlabConfig c, Map<String, dynamic> a) {
  final user = syncAsStr(a['user']).trim();
  if (user.isEmpty) return syncErr('GitLab username must not be empty');
  final resolved = _resolveGlSyncIssueRef(a);
  if (resolved is! _GlSyncIssueRef) return resolved as String;
  final usersResp = SyncHttpClient.get(
    '${c.baseUrl}/users?username=${Uri.encodeQueryComponent(user)}',
    headers: c.headers,
  );
  if (!usersResp.isOk) return syncStrictBodyOrError(usersResp);
  final users = syncTryDecode(usersResp.body);
  if (users is! List || users.isEmpty || users.first is! Map) {
    return syncErr('GitLab user not found: $user');
  }
  final userId = (users.first as Map)['id'];
  return _putIssueJson(c, '${c.baseUrl}/${resolved.issueSeg}', {
    'assignee_ids': [userId],
  });
}

/// `gitlab_add_issue_label` — PUT `add_labels` on the issue.
String _addIssueLabel(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => _putIssueJson(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        {'add_labels': syncAsStr(a['label'])},
      ),
    );

/// `gitlab_remove_issue_label` — PUT `remove_labels` on the issue.
String _removeIssueLabel(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => _putIssueJson(
        c,
        '${c.baseUrl}/${ref.issueSeg}',
        {'remove_labels': syncAsStr(a['label'])},
      ),
    );

/// `gitlab_create_issue_comment` — POST `{body}` to `…/issues/{iid}/notes`.
String _createIssueComment(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => syncStrictBodyOrError(
        SyncHttpClient.post(
          '${c.baseUrl}/${ref.issueSeg}/notes',
          headers: c.headers,
          body: jsonEncode({
            'body': _glFirstStr(a, const ['body', 'text', 'comment']),
          }),
        ),
      ),
    );

/// `gitlab_get_issue_comments` — paginated GET `…/issues/{iid}/notes?sort=asc`
/// (Java `GitLabIssues.getIssueComments` parity).
String _getIssueComments(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(c, a, _fetchAllIssueComments);

String _fetchAllIssueComments(_GitlabConfig c, _GlSyncIssueRef ref) {
  final all = <dynamic>[];
  var page = 1;
  while (true) {
    final resp = SyncHttpClient.get(
      '${c.baseUrl}/${ref.issueSeg}/notes?sort=asc&per_page=100&page=$page',
      headers: c.headers,
    );
    if (!resp.isOk) return syncStrictBodyOrError(resp);
    final decoded = syncTryDecode(resp.body);
    if (decoded is! List) return resp.body;
    all.addAll(decoded);
    if (decoded.length < 100) return jsonEncode(all);
    page++;
  }
}
