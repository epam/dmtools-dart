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
  var resolvedProject = _glBlankToNull(project);
  if (resolvedProject == null) {
    final ws = _glBlankToNull(workspace);
    final rp = _glBlankToNull(repository);
    if (ws != null && rp != null) resolvedProject = '$ws/$rp';
  }
  var resolvedIid = _glBlankToNull(issueNumber);
  final k = _glBlankToNull(key);
  if (k != null && (resolvedProject == null || resolvedIid == null)) {
    final applied = _applyGlIssueKey(k, resolvedProject, resolvedIid);
    resolvedProject = applied.$1;
    resolvedIid = applied.$2;
  }
  if (resolvedProject == null) {
    final ws = _glDefaultWorkspace();
    final rp = _glDefaultRepository();
    if (ws != null && rp != null) resolvedProject = '$ws/$rp';
  }
  if (resolvedProject == null || resolvedIid == null) {
    throw ArgumentError(
      'GitLab issue reference requires workspace/repository/issueNumber '
      "or a composite key 'namespace/project#123' (or 'gl-123' with a "
      'configured default project).',
    );
  }
  return GlIssueRef(resolvedProject, resolvedIid);
}

/// Parses composite `namespace/project#123`, `gl-123`, or bare IID [k].
(String?, String?) _applyGlIssueKey(
  String k,
  String? currentProject,
  String? currentIid,
) {
  var proj = currentProject;
  var iid = currentIid;
  final sep = k.lastIndexOf('#');
  final router = _glRouterKey.firstMatch(k);
  if (sep > 0 &&
      sep < k.length - 1 &&
      _glBareDigits.hasMatch(k.substring(sep + 1))) {
    proj ??= k.substring(0, sep);
    iid ??= k.substring(sep + 1);
  } else if (router != null) {
    iid ??= router.group(1);
  } else if (_glBareDigits.hasMatch(k)) {
    iid ??= k;
  } else {
    throw ArgumentError(
      "Cannot parse GitLab issue key: '$k'. Expected 'namespace/project#123', "
      "'gl-123', or a bare issue IID.",
    );
  }
  return (proj, iid);
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
  final ws = _glBlankToNull(workspace) ?? _glDefaultWorkspace();
  final rp = _glBlankToNull(repository) ?? _glDefaultRepository();
  if (ws == null || rp == null) {
    throw ArgumentError(
      'GitLab project is not configured. Pass workspace/repository '
      'or set GITLAB_WORKSPACE and GITLAB_REPOSITORY.',
    );
  }
  return '$ws/$rp';
}

String? _glBlankToNull(String? value) {
  final t = value?.trim() ?? '';
  return t.isEmpty ? null : t;
}

String? _glDefaultWorkspace() =>
    _glBlankToNull(PropertyReader().getGitLabWorkspace());

String? _glDefaultRepository() =>
    _glBlankToNull(PropertyReader().getGitLabRepository());

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
    String? body,
    String? workspace,
    String? repository,
    String? key,
  }) {
    final desc = _glBlankToNull(description) ?? _glBlankToNull(body);
    final resolvedProject = resolveGlProjectPath(
      workspace: workspace,
      repository: repository,
      project: project,
      key: key,
    );
    return createIssue(resolvedProject, title, desc);
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
  Future<Map<String, dynamic>?> closeIssueByRef({
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) {
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
    return _putObject(_issuePath(ref), jsonEncode({'state_event': 'close'}));
  }

  /// `gitlab_reopen_issue` — PUT `projects/{id}/issues/{iid}` `state_event=reopen`.
  Future<Map<String, dynamic>?> reopenIssueByRef({
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) {
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
    return _putObject(_issuePath(ref), jsonEncode({'state_event': 'reopen'}));
  }

  /// `gitlab_move_issue_to_status` — close/reopen/scoped-label semantics.
  Future<Map<String, dynamic>?> moveIssueToStatus(
    String statusName, {
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) {
    final trimmed = _glBlankToNull(statusName);
    if (trimmed == null) throw ArgumentError('statusName is required');
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
    final lower = trimmed.toLowerCase();
    if (_glClosedStatuses.contains(lower)) {
      return _putObject(_issuePath(ref), jsonEncode({'state_event': 'close'}));
    }
    if (_glOpenStatuses.contains(lower)) {
      return _putObject(_issuePath(ref), jsonEncode({'state_event': 'reopen'}));
    }
    return _putObject(
      _issuePath(ref),
      jsonEncode({'add_labels': 'status::$trimmed'}),
    );
  }

  /// `gitlab_assign_issue` — resolves username via `/users?username=…`, then
  /// PUTs `assignee_ids` on the issue.
  Future<Map<String, dynamic>?> assignIssue(
    String user, {
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) async {
    final trimmed = _glBlankToNull(user);
    if (trimmed == null) {
      throw ArgumentError('GitLab username must not be empty');
    }
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
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
  Future<Map<String, dynamic>?> addIssueLabel(
    String label, {
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) {
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
    return _putObject(_issuePath(ref), jsonEncode({'add_labels': label}));
  }

  /// `gitlab_remove_issue_label` — PUT `remove_labels` on the issue.
  Future<Map<String, dynamic>?> removeIssueLabel(
    String label, {
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) {
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
    return _putObject(_issuePath(ref), jsonEncode({'remove_labels': label}));
  }

  /// `gitlab_create_issue_comment` — POST `{body}` to `…/issues/{iid}/notes`.
  Future<Map<String, dynamic>?> createIssueComment(
    String body, {
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) {
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
    return _postObject(
      '${_issuePath(ref)}/notes',
      jsonEncode({'body': body}),
    );
  }

  /// `gitlab_get_issue_comments` — paginated GET `…/issues/{iid}/notes?sort=asc`.
  Future<List<Map<String, dynamic>>> getIssueComments({
    String? workspace,
    String? repository,
    String? issueNumber,
    String? key,
    String? project,
  }) async {
    final ref = resolveGlIssueRef(
      key: key,
      workspace: workspace,
      repository: repository,
      issueNumber: issueNumber,
      project: project,
    );
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
