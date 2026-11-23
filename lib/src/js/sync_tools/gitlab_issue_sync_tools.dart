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
  final reader = PropertyReader();
  final ws = reader.getGitLabWorkspace()?.trim() ?? '';
  final rp = reader.getGitLabRepository()?.trim() ?? '';
  return (ws.isNotEmpty && rp.isNotEmpty) ? '$ws/$rp' : '';
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
  final reader = PropertyReader();
  final wsArg = _glFirstStr(args, const ['workspace', 'owner']);
  final rpArg = _glFirstStr(args, const ['repository', 'repo']);
  final ws =
      wsArg.isNotEmpty ? wsArg : reader.getGitLabWorkspace()?.trim() ?? '';
  final rp =
      rpArg.isNotEmpty ? rpArg : reader.getGitLabRepository()?.trim() ?? '';
  return (ws.isNotEmpty && rp.isNotEmpty) ? '$ws/$rp' : null;
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
  final payload = _syncGlClosedStatuses.contains(lower)
      ? const <String, dynamic>{'state_event': 'close'}
      : _syncGlOpenStatuses.contains(lower)
          ? const <String, dynamic>{'state_event': 'reopen'}
          : <String, dynamic>{'add_labels': 'status::$status'};
  return _putBody(c, '${c.baseUrl}/${resolved.issueSeg}', jsonEncode(payload));
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
          'body': _glFirstStr(a, const ['body', 'text', 'comment'])
        }),
      ),
    );

/// `gitlab_get_issue_comments` — GET `…/issues/{iid}/notes?sort=asc&per_page=100`.
String _getIssueComments(_GitlabConfig c, Map<String, dynamic> a) =>
    _withGlIssueRef(
      c,
      a,
      (c, ref) => syncBodyOrError(
        SyncHttpClient.get(
          '${c.baseUrl}/${ref.issueSeg}/notes?sort=asc&per_page=100',
          headers: c.headers,
        ),
      ),
    );
