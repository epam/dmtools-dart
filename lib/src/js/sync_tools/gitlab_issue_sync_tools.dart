/// Issue-tracker sync executors — Java `GitLabIssues.java` (dm.ai bb7a2f93).
///
/// Part of the `gitlab_sync_tools.dart` library so the handlers share the
/// sync config/HTTP helpers. Every issue tool resolves its reference from
/// explicit parts (`workspace`/`repository`/`issueNumber`), a composite
/// `key` (`namespace/project#123` with nested subgroups, `gl-123`, or a
/// bare IID), or the configured `GITLAB_WORKSPACE` / `GITLAB_REPOSITORY`
/// defaults — Java `resolveIssueRef` parity.
part of 'gitlab_sync_tools.dart';

/// The resolved issue reference for one sync call.
class _GlSyncIssueRef {
  final String projectPath;
  final String iid;
  const _GlSyncIssueRef(this.projectPath, this.iid);

  /// `projects/{encoded path}` URL segment.
  String get projectSeg =>
      'projects/${Uri.encodeComponent(projectPath).replaceAll('+', '%20')}';

  /// `projects/{encoded path}/issues/{iid}` URL segment.
  String get issueSeg => '$projectSeg/issues/$iid';
}

/// Composite issue-key pattern: `namespace/subgroup/project#123`.
final RegExp _glCompositeKey = RegExp(r'^([\w.-]+(?:/[\w.-]+)+)#(\d+)$');

/// `gl-123` issue-key pattern — the dmtools-agents router convention.
final RegExp _glRouterKey = RegExp(r'^gl-(\d+)$', caseSensitive: false);

/// First non-blank string among [names] in [args].
String _glFirstStr(Map<String, dynamic> args, List<String> names) {
  for (final name in names) {
    final value = syncAsStr(args[name]).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Resolves the issue reference from tool [args] (Java
/// `GitLabIssues.resolveIssueRef` + `GITLAB_WORKSPACE`/`GITLAB_REPOSITORY`
/// defaults). Explicit parts win over the `key`; a `gl-N` or bare-number
/// key without a project path uses the configured defaults.
///
/// Returns a JSON error string when the reference cannot be resolved.
Object _glResolveIssueRef(Map<String, dynamic> args) {
  var project = _glProjectFromParts(args);
  var iid = _glFirstStr(args, const ['issueNumber', 'number', 'iid']);
  final key = syncAsStr(args['key']).trim();
  if (key.isNotEmpty && (project == null || iid.isEmpty)) {
    final composite = _glCompositeKey.firstMatch(key);
    if (composite != null) {
      project ??= key.substring(0, key.indexOf('#'));
      if (iid.isEmpty) iid = composite.group(2)!;
    } else {
      final router = _glRouterKey.firstMatch(key);
      final bareIid = RegExp(r'^\d+$').hasMatch(key) ? key : null;
      final keyIid = router?.group(1) ?? bareIid;
      if (keyIid == null) {
        return syncErr(
          "Cannot parse GitLab issue key: '$key'. Expected "
          "'namespace/project#123', 'gl-123', or a bare issue IID.",
        );
      }
      if (iid.isEmpty) iid = keyIid;
    }
  } else if (key.isNotEmpty && RegExp(r'^\d+$').hasMatch(key) == false &&
      _glRouterKey.firstMatch(key) == null &&
      _glCompositeKey.firstMatch(key) == null) {
    return syncErr(
      "Cannot parse GitLab issue key: '$key'. Expected "
      "'namespace/project#123', 'gl-123', or a bare issue IID.",
    );
  }
  project ??= _glDefaultProject();
  if (project == null || iid.isEmpty) {
    return syncErr(
      'GitLab issue reference requires workspace/repository/issueNumber '
      "or a composite key 'namespace/project#123' (or 'gl-123' with a "
      'configured default project).',
    );
  }
  return _GlSyncIssueRef(project, iid);
}

/// `{workspace}/{repository}` from explicit args, or `null`.
String? _glProjectFromParts(Map<String, dynamic> args) {
  final workspace = _glFirstStr(args, const ['workspace', 'owner']);
  final repository = _glFirstStr(args, const ['repository', 'repo']);
  if (workspace.isEmpty || repository.isEmpty) return null;
  return '$workspace/$repository';
}

/// `{GITLAB_WORKSPACE}/{GITLAB_REPOSITORY}` when both are set, or `null`.
String? _glDefaultProject() {
  final reader = PropertyReader();
  final workspace = reader.getGitLabWorkspace()?.trim() ?? '';
  final repository = reader.getGitLabRepository()?.trim() ?? '';
  if (workspace.isEmpty || repository.isEmpty) return null;
  return '$workspace/$repository';
}

/// Runs [fn] with the resolved issue reference, or returns the JSON error.
String _glWithIssueRef(
  _GitlabConfig config,
  Map<String, dynamic> args,
  String Function(_GitlabConfig, _GlSyncIssueRef) fn,
) {
  final resolved = _glResolveIssueRef(args);
  return resolved is _GlSyncIssueRef
      ? fn(config, resolved)
      : resolved as String;
}

/// Full project path for search/create tools: explicit parts or defaults.
String _glResolveProjectPath(Map<String, dynamic> args) {
  return _glProjectFromParts(args) ?? _glDefaultProject() ?? '';
}

/// Issue-tracker sync executors — Java `GitLabIssues.java` parity.
class GitLabIssueSyncTools {
  /// Creates the issue-family sync tooling.
  const GitLabIssueSyncTools();

  /// Issue-family executors, keyed by tool name. Each resolves the sync
  /// config per call so config overrides apply immediately (the dispatcher
  /// wraps this map with the required-param guard, then `_wrapHandlers`
  /// semantics apply — config resolution happens here).
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'gitlab_get_issue': (a) => _run(_getIssue, a),
        'gitlab_search_issues': (a) => _run(_searchIssues, a),
        'gitlab_create_issue': (a) => _run(_createIssue, a),
        'gitlab_close_issue': (a) => _run(_closeIssue, a),
        'gitlab_reopen_issue': (a) => _run(_reopenIssue, a),
        'gitlab_move_issue_to_status': (a) => _run(_moveIssueToStatus, a),
        'gitlab_assign_issue': (a) => _run(_assignIssue, a),
        'gitlab_add_issue_label': (a) => _run(_addIssueLabel, a),
        'gitlab_remove_issue_label': (a) => _run(_removeIssueLabel, a),
        'gitlab_create_issue_comment': (a) => _run(_createIssueComment, a),
        'gitlab_get_issue_comments': (a) => _run(_getIssueComments, a),
      };

  /// Resolves the GitLab config and hands [args] to [fn].
  String _run(
    String Function(_GitlabConfig, Map<String, dynamic>) fn,
    Map<String, dynamic> args,
  ) {
    final config = _gitlabConfig();
    if (config == null) return syncErr('GitLab not configured');
    return fn(config, args);
  }

  /// `gitlab_get_issue` — GET `projects/{id}/issues/{iid}`.
  String _getIssue(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(
          config, args, (c, ref) => _glGet(c, '${c.baseUrl}/${ref.issueSeg}'));

  /// `gitlab_search_issues` — GET `projects/{id}/issues?search=…`.
  ///
  /// Java `searchIssues`: text matched against title and description,
  /// `state` defaults to `all`, one page of 100.
  String _searchIssues(_GitlabConfig config, Map<String, dynamic> args) {
    final projectPath = _glResolveProjectPath(args);
    if (projectPath.isEmpty) {
      return syncErr(
        'GitLab project is not configured. Pass workspace/repository '
        'or set GITLAB_WORKSPACE and GITLAB_REPOSITORY.',
      );
    }
    var state = syncAsStr(args['state']).trim();
    if (state.isEmpty) state = 'all';
    final query = syncAsStr(args['query']);
    final url =
        '${config.baseUrl}/projects/${Uri.encodeComponent(projectPath).replaceAll('+', '%20')}'
        '/issues?state=${Uri.encodeQueryComponent(state)}'
        '&per_page=100&search=${Uri.encodeQueryComponent(query)}';
    return _glGet(config, url);
  }

  /// `gitlab_create_issue` — POST `projects/{id}/issues`.
  ///
  /// Java `createIssue`: `key` optionally carries the composite project
  /// path `namespace/project`; blank parts fall back to the defaults.
  String _createIssue(_GitlabConfig config, Map<String, dynamic> args) {
    final key = syncAsStr(args['key']).trim();
    var projectPath = key.contains('/')
        ? key
        : _glResolveProjectPath(args);
    if (projectPath.isEmpty) {
      return syncErr(
        'GitLab project is not configured. Pass workspace/repository '
        'or set GITLAB_WORKSPACE and GITLAB_REPOSITORY.',
      );
    }
    final payload = <String, dynamic>{'title': syncAsStr(args['title'])};
    final body = syncAsStr(args['body'] ?? args['description']).trim();
    if (body.isNotEmpty) payload['description'] = body;
    return syncPostJson(
      config.headers,
      '${config.baseUrl}/projects/'
          '${Uri.encodeComponent(projectPath).replaceAll('+', '%20')}/issues',
      jsonEncode(payload),
    );
  }

  /// `gitlab_close_issue` — PUT `{state_event: close}`.
  String _closeIssue(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(config, args,
          (c, ref) => _glUpdateIssue(c, ref, {'state_event': 'close'}));

  /// `gitlab_reopen_issue` — PUT `{state_event: reopen}`.
  String _reopenIssue(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(config, args,
          (c, ref) => _glUpdateIssue(c, ref, {'state_event': 'reopen'}));

  /// `gitlab_move_issue_to_status` — close/reopen/status-label semantics.
  ///
  /// Java `moveIssueToStatus`: 'done'/'closed'/'completed'/'resolved' close,
  /// 'open'/'opened'/'reopen'/'reopened' reopen, anything else becomes the
  /// scoped label `status::<name>`.
  String _moveIssueToStatus(
      _GitlabConfig config, Map<String, dynamic> args) {
    final status = syncAsStr(args['statusName'] ?? args['status']).trim();
    if (status.isEmpty) return syncErr('statusName is required');
    return _glWithIssueRef(config, args, (c, ref) {
      final lowered = status.toLowerCase();
      if (const {'done', 'closed', 'completed', 'resolved'}
          .contains(lowered)) {
        return _glUpdateIssue(c, ref, {'state_event': 'close'});
      }
      if (const {'open', 'opened', 'reopen', 'reopened'}
          .contains(lowered)) {
        return _glUpdateIssue(c, ref, {'state_event': 'reopen'});
      }
      return _glUpdateIssue(c, ref, {'add_labels': 'status::$status'});
    });
  }

  /// `gitlab_assign_issue` — PUT `{assignee_ids: [id]}`.
  ///
  /// Java `assignIssue`: looks the user up by username via `/users?username=`
  /// and assigns by id; unknown users are an error.
  String _assignIssue(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(config, args, (c, ref) {
        final user = syncAsStr(args['user']).trim();
        final url =
            '${c.baseUrl}/users?username=${Uri.encodeQueryComponent(user)}';
        final body = _glGet(c, url);
        final decoded = syncTryDecode(body);
        if (decoded is! List || decoded.isEmpty) {
          return syncErr('GitLab user not found: $user');
        }
        final userId = decoded.first is Map
            ? (decoded.first as Map)['id']
            : null;
        if (userId is! int) {
          return syncErr('GitLab user not found: $user');
        }
        return _glUpdateIssue(c, ref, {
          'assignee_ids': [userId],
        });
      });

  /// `gitlab_add_issue_label` — PUT `add_labels`.
  String _addIssueLabel(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(
          config,
          args,
          (c, ref) =>
              _glUpdateIssue(c, ref, {'add_labels': syncAsStr(args['label'])}));

  /// `gitlab_remove_issue_label` — PUT `remove_labels`.
  String _removeIssueLabel(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(
          config,
          args,
          (c, ref) => _glUpdateIssue(
              c, ref, {'remove_labels': syncAsStr(args['label'])}));

  /// `gitlab_create_issue_comment` — POST `…/issues/{iid}/notes`.
  String _createIssueComment(
          _GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(
          config,
          args,
          (c, ref) => syncPostJson(c.headers, '${c.baseUrl}/${ref.issueSeg}/notes',
              jsonEncode({'body': syncAsStr(args['body'] ?? args['text'])})));

  /// `gitlab_get_issue_comments` — GET `…/notes` (all pages, oldest first).
  ///
  /// Java `getIssueComments`: pages of 100 ascending until a short page;
  /// system notes are dropped (the Java filter drops `system` notes).
  String _getIssueComments(_GitlabConfig config, Map<String, dynamic> args) =>
      _glWithIssueRef(config, args, (c, ref) {
        final notes = gitlabFetchAllPages(
          c.baseUrl,
          c.headers,
          '${ref.projectSeg}/issues/${ref.iid}/notes?sort=asc',
        );
        return jsonEncode([
          for (final note in notes)
            if (note is Map && note['system'] != true) note,
        ]);
      });
}

/// GET [url] with the GitLab sync config.
String _glGet(_GitlabConfig config, String url) =>
    syncBodyOrError(SyncHttpClient.get(url, headers: config.headers));

/// PUTs a partial issue update (labels, state_event, assignee_ids, …).
String _glUpdateIssue(
        _GitlabConfig config, _GlSyncIssueRef ref, Map<String, dynamic> body) =>
    _putBody(config, '${config.baseUrl}/${ref.issueSeg}', jsonEncode(body));
