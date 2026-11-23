/// Issue-tracker client methods — Java `GitLabIssues.java` (dm.ai #876).
///
/// Part of the [GitlabClient] library so the extension shares private
/// transport access. Issue tools resolve references like Java:
/// explicit `workspace`/`repository`/`issueNumber` parts (or legacy
/// `project`/`iid`), a composite `namespace/project#123` or `gl-123` or
/// bare IID `key`, then the configured `GITLAB_WORKSPACE` /
/// `GITLAB_REPOSITORY` defaults.
part of 'gitlab_client.dart';

/// A resolved GitLab issue reference: full project path + issue IID.
class GlIssueRef {
  /// Full `namespace/project` path (or numeric project id).
  final String projectPath;

  /// Project-scoped issue IID.
  final String iid;

  /// Creates a resolved GitLab issue reference.
  const GlIssueRef(this.projectPath, this.iid);
}

/// Composite or partial GitLab issue-key parts.
typedef GlKeyParts = ({String? projectPath, String? iid});

/// `gl-123` router key convention.
final RegExp _glRouterKey = RegExp(r'^gl-(\d+)$', caseSensitive: false);

/// Bare numeric issue IID.
final RegExp _glBareDigits = RegExp(r'^\d+$');

/// Statuses that close a GitLab issue (Java parity).
const _glClosedStatuses = {'done', 'closed', 'completed', 'resolved'};

/// Statuses that reopen a GitLab issue (Java parity).
const _glOpenStatuses = {'open', 'opened', 'reopen', 'reopened'};

/// Resolves a GitLab issue reference from explicit parts, legacy
/// `project`/`iid`, or a composite [key] (Java `GitLabIssues.resolveIssueRef`).
GlIssueRef resolveGlIssueRef({
  String? key,
  String? workspace,
  String? repository,
  String? issueNumber,
  String? project,
}) {
  final initialProj =
      _glBlankToNull(project) ?? _glJoinPair(workspace, repository);
  final initialIid = _glBlankToNull(issueNumber);
  final parsed = parseGlIssueKey(_glBlankToNull(key));
  final finalProj = initialProj ?? parsed.projectPath ?? _glDefaultProject();
  final finalIid = initialIid ?? parsed.iid;
  if (finalProj == null || finalIid == null) {
    throw ArgumentError(
      'GitLab issue reference requires workspace/repository/issueNumber '
      "or a composite key 'namespace/project#123' (or 'gl-123' with a "
      'configured default project).',
    );
  }
  return GlIssueRef(finalProj, finalIid);
}

String? _glJoinPair(String? ws, String? rp) {
  final w = _glBlankToNull(ws);
  final r = _glBlankToNull(rp);
  return (w != null && r != null) ? '$w/$r' : null;
}

/// Parses composite `namespace/project#123`, `gl-123`, or bare IID [k].
GlKeyParts parseGlIssueKey(String? k) {
  if (k == null) return (projectPath: null, iid: null);
  final sep = k.lastIndexOf('#');
  if (sep > 0 &&
      sep < k.length - 1 &&
      _glBareDigits.hasMatch(k.substring(sep + 1))) {
    return (
      projectPath: k.substring(0, sep),
      iid: k.substring(sep + 1),
    );
  }
  final router = _glRouterKey.firstMatch(k);
  if (router != null) return (projectPath: null, iid: router.group(1));
  if (_glBareDigits.hasMatch(k)) return (projectPath: null, iid: k);
  throw ArgumentError(
    "Cannot parse GitLab issue key: '$k'. Expected 'namespace/project#123', "
    "'gl-123', or a bare issue IID.",
  );
}

/// Resolves a GitLab project path from explicit parts, `project`/`key`, or
/// configured defaults (`GITLAB_WORKSPACE` + `GITLAB_REPOSITORY`).
String resolveGlProjectPath({
  String? workspace,
  String? repository,
  String? project,
  String? key,
}) {
  final k = _glBlankToNull(key);
  if (k != null && k.contains('/')) return k;
  final p = _glBlankToNull(project);
  if (p != null) return p;
  final ws = _glBlankToNull(workspace);
  final rp = _glBlankToNull(repository);
  if (ws != null && rp != null) return '$ws/$rp';
  final def = _glDefaultProject(workspaceOverride: ws, repositoryOverride: rp);
  if (def != null) return def;
  throw ArgumentError(
    'GitLab project is not configured. Pass workspace/repository '
    'or set GITLAB_WORKSPACE and GITLAB_REPOSITORY.',
  );
}

String? _glBlankToNull(String? value) {
  final t = value?.trim() ?? '';
  return t.isEmpty ? null : t;
}

String? _glDefaultProject({
  String? workspaceOverride,
  String? repositoryOverride,
}) {
  final reader = PropertyReader();
  if (workspaceOverride == null && repositoryOverride == null) {
    final ciPath = _glBlankToNull(reader.getValue('CI_PROJECT_PATH'));
    if (ciPath != null && ciPath.contains('/')) return ciPath;
  }
  final ws = workspaceOverride ?? _glBlankToNull(reader.getGitLabWorkspace());
  final rp = repositoryOverride ?? _glBlankToNull(reader.getGitLabRepository());
  return (ws != null && rp != null) ? '$ws/$rp' : null;
}

/// Issue-tracker methods on [GitlabClient] (Java `GitLabIssues` parity).
extension GitlabIssueTrackerTools on GitlabClient {
  /// API path for one issue: `projects/<encoded>/issues/<iid>`.
  String _issuePath(GlIssueRef ref) =>
      'projects/${_encodeProject(ref.projectPath)}/issues/${ref.iid}';

  /// `gitlab_get_issue` with composite-key / workspace+repository fallback.
  Future<Map<String, dynamic>?> getIssueByRef({
    String? project,
    int? iid,
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
  }) {
    if (project != null && iid != null) return getIssue(project, iid);
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber ?? iid?.toString(),
      project: project,
    );
    return _getObject(_issuePath(ref));
  }

  /// `gitlab_create_issue` with composite-key / workspace+repository fallback.
  Future<Map<String, dynamic>?> createIssueByRef(
    String title, {
    String? project,
    String? description,
    String? workspace,
    String? repository,
    String? key,
  }) {
    final resolvedProject = resolveGlProjectPath(
      workspace: workspace,
      repository: repository,
      project: project,
      key: key,
    );
    return createIssue(resolvedProject, title, _glBlankToNull(description));
  }

  /// `gitlab_search_issues` — GET `projects/{id}/issues?state=…&search=…`.
  Future<List<Map<String, dynamic>>> searchIssues(
    String query, {
    String? workspace,
    String? repository,
    String? state,
    String? project,
  }) {
    final projectPath = resolveGlProjectPath(
      workspace: workspace,
      repository: repository,
      project: project,
    );
    final effectiveState = _glBlankToNull(state) ?? 'all';
    return _getList(
      'projects/${_encodeProject(projectPath)}/issues',
      queryParams: {
        'state': effectiveState,
        'per_page': 100,
        'search': query,
      },
    );
  }

  /// `gitlab_close_issue` — PUT `projects/{id}/issues/{iid}` `state_event=close`.
  Future<Map<String, dynamic>?> closeIssueByRef(GlIssueRef ref) =>
      _putObject(_issuePath(ref), jsonEncode(const {'state_event': 'close'}));

  /// `gitlab_reopen_issue` — PUT `projects/{id}/issues/{iid}` `state_event=reopen`.
  Future<Map<String, dynamic>?> reopenIssueByRef(GlIssueRef ref) =>
      _putObject(_issuePath(ref), jsonEncode(const {'state_event': 'reopen'}));

  /// `gitlab_move_issue_to_status` — close/reopen/scoped-label semantics.
  Future<Map<String, dynamic>?> moveIssueToStatus(
    GlIssueRef ref,
    String statusName,
  ) {
    final trimmed = _glBlankToNull(statusName);
    if (trimmed == null) throw ArgumentError('statusName is required');
    final lower = trimmed.toLowerCase();
    final payload = _glClosedStatuses.contains(lower)
        ? const <String, dynamic>{'state_event': 'close'}
        : _glOpenStatuses.contains(lower)
            ? const <String, dynamic>{'state_event': 'reopen'}
            : <String, dynamic>{'add_labels': 'status::$trimmed'};
    return _putObject(_issuePath(ref), jsonEncode(payload));
  }

  /// `gitlab_assign_issue` — resolves username via `/users?username=…`, then
  /// PUTs `assignee_ids` on the issue.
  Future<Map<String, dynamic>?> assignIssue(
    GlIssueRef ref,
    String user,
  ) async {
    final trimmed = _glBlankToNull(user);
    if (trimmed == null) {
      throw ArgumentError('GitLab username must not be empty');
    }
    final users = await _getList('users', queryParams: {'username': trimmed});
    if (users.isEmpty) {
      throw StateError('GitLab user not found: $user');
    }
    final userId = users.first['id'];
    return _putObject(
      _issuePath(ref),
      jsonEncode({
        'assignee_ids': [userId],
      }),
    );
  }

  /// `gitlab_add_issue_label` — PUT `add_labels` on the issue.
  Future<Map<String, dynamic>?> addIssueLabel(GlIssueRef ref, String label) =>
      _putObject(_issuePath(ref), jsonEncode({'add_labels': label}));

  /// `gitlab_remove_issue_label` — PUT `remove_labels` on the issue.
  Future<Map<String, dynamic>?> removeIssueLabel(
    GlIssueRef ref,
    String label,
  ) =>
      _putObject(_issuePath(ref), jsonEncode({'remove_labels': label}));

  /// `gitlab_create_issue_comment` — POST `{body}` to `…/issues/{iid}/notes`.
  Future<Map<String, dynamic>?> createIssueComment(
    GlIssueRef ref,
    String body,
  ) =>
      _postObject('${_issuePath(ref)}/notes', jsonEncode({'body': body}));

  /// `gitlab_get_issue_comments` — paginated GET `…/issues/{iid}/notes?sort=asc`.
  Future<List<Map<String, dynamic>>> getIssueComments(GlIssueRef ref) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final notes = await _getList(
        '${_issuePath(ref)}/notes',
        queryParams: {'sort': 'asc', 'per_page': 100, 'page': page},
      );
      all.addAll(notes);
      if (notes.length < 100) return all;
      page++;
    }
  }
}
