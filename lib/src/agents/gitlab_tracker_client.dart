/// Write-side GitLab issues tracker client — Java `GitLabTrackerClient` /
/// `GitLabTicket` parity (epam/dm.ai#876).
///
/// Java injects a `TrackerClient` into jobs (`DEFAULT_TRACKER=gitlab` via
/// `TrackerModule`); the Dart runtime's tracker surface is the `gitlab_*`
/// sync tool catalog, so this client routes over it through a
/// [SyncToolExecute] dispatcher — the same pattern [GithubTrackerClient]
/// uses. Operations map 1:1 onto the Java tracker client:
///
/// | Java                       | Dart / tool                        |
/// |----------------------------|------------------------------------|
/// | `postComment`              | `gitlab_create_issue_comment`      |
/// | `moveToStatus`             | `gitlab_move_issue_to_status`      |
/// | `assignTo`                 | `gitlab_assign_issue`              |
/// | `addLabelIfNotExists`      | `gitlab_add_issue_label`           |
/// | `deleteLabelInTicket`      | `gitlab_remove_issue_label`        |
/// | `createTicketInProject`    | `gitlab_create_issue`              |
///
/// Tickets are keyed `namespace/project#iid` (Java `GitLabTicket
/// .getTicketKey()` composite). `gl-<n>` and a bare IID resolve against the
/// configured default project (`GITLAB_WORKSPACE` / `GITLAB_REPOSITORY`, or
/// the CI-provided `CI_PROJECT_PATH`). Failures surface as [StateError] —
/// Java's `IOException` parity.
library;

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import 'github_tracker_client.dart'
    show
        SyncToolExecute,
        defaultTrackerExecute,
        trackerErrorOf,
        trackerTryDecode;

/// A resolved `(projectPath, iid)` GitLab issue reference.
typedef GitlabTrackerIssueRef = (String projectPath, String iid);

/// Write-side tracker operations backed by GitLab project issues.
class GitlabTrackerClient {
  /// Creates the client; [execute] defaults to the real sync dispatcher.
  GitlabTrackerClient({SyncToolExecute? execute})
      : _execute = execute ?? defaultTrackerExecute;

  final SyncToolExecute _execute;

  /// Whether GitLab tracker operations can run (`GITLAB_TOKEN` present —
  /// Java `getInstance()` returns null without it).
  bool get isConfigured => (PropertyReader().getGitLabToken() ?? '').isNotEmpty;

  /// Posts a comment to the issue [key] refers to (Java `postComment`).
  void postComment(String key, String body) =>
      _dispatchKeyed(key, 'gitlab_create_issue_comment', {'body': body});

  /// Moves the issue to [status] — done/closed/completed/resolved close it,
  /// open/reopened reopen it, anything else lands as `status::<status>`
  /// (Java `moveToStatus`).
  void moveToStatus(String key, String status) => _dispatchKeyed(
      key, 'gitlab_move_issue_to_status', {'statusName': status});

  /// Assigns the issue to [user] (Java `assignTo`).
  void assignTo(String key, String user) =>
      _dispatchKeyed(key, 'gitlab_assign_issue', {'user': user});

  /// Adds [label] to the issue (Java `addLabelIfNotExists`).
  void addLabel(String key, String label) =>
      _dispatchKeyed(key, 'gitlab_add_issue_label', {'label': label});

  /// Removes [label] from the issue (Java `deleteLabelInTicket`).
  void removeLabel(String key, String label) =>
      _dispatchKeyed(key, 'gitlab_remove_issue_label', {'label': label});

  /// Creates an issue in [project] (`namespace/project`) and returns the
  /// composite key `namespace/project#<iid>` (Java `createTicketInProject`
  /// → `GitLabTicket.getTicketKey()`).
  String createTicket({
    required String project,
    required String summary,
    String description = '',
  }) {
    final trimmedProject = project.trim();
    if (!trimmedProject.contains('/') ||
        trimmedProject.split('/').any((p) => p.trim().isEmpty)) {
      throw StateError(
        "createTicket needs a 'namespace/project' project, got: '$project'",
      );
    }
    final raw = _execute('gitlab_create_issue', {
      'key': trimmedProject,
      'title': summary,
      if (description.isNotEmpty) 'body': description,
    });
    final decoded = raw == null ? null : trackerTryDecode(raw);
    final iid = decoded is Map ? decoded['iid'] : null;
    if (iid == null) {
      throw StateError(
        'gitlab_create_issue returned no issue iid: '
        '${raw == null ? 'tool not dispatchable' : trackerErrorOf(raw)}',
      );
    }
    return '$trimmedProject#$iid';
  }

  /// Dispatches [tool] with the resolved composite `key` and [extraArgs].
  void _dispatchKeyed(
    String key,
    String tool,
    Map<String, dynamic> extraArgs,
  ) {
    final ref = resolveIssueRef(key);
    if (ref == null) {
      throw StateError(
        "Cannot parse GitLab issue key: '$key'. Expected "
        "'namespace/project#123', 'gl-123', or a bare issue IID with the "
        'default project configured.',
      );
    }
    final (projectPath, iid) = ref;
    final raw = _execute(tool, {'key': '$projectPath#$iid', ...extraArgs});
    final error = raw == null
        ? '$tool is not dispatchable in this runtime'
        : trackerErrorOf(raw);
    if (error != null) throw StateError(error);
  }

  /// Resolves [key] to `(projectPath, iid)`:
  /// `namespace/project#42` verbatim; `gl-42` (any case) and bare `42`
  /// against `CI_PROJECT_PATH`, then `GITLAB_WORKSPACE` +
  /// `GITLAB_REPOSITORY`. `null` when anything is missing.
  GitlabTrackerIssueRef? resolveIssueRef(String key) {
    final trimmed = key.trim();
    final sep = trimmed.lastIndexOf('#');
    if (sep > 0 &&
        sep < trimmed.length - 1 &&
        RegExp(r'^\d+$').hasMatch(trimmed.substring(sep + 1))) {
      final proj = trimmed.substring(0, sep).trim();
      if (proj.contains('/') &&
          proj.split('/').every((p) => p.trim().isNotEmpty)) {
        return (proj, trimmed.substring(sep + 1));
      }
    }
    final bare = RegExp(r'^(?:gl-)?(\d+)$', caseSensitive: false)
        .firstMatch(trimmed)
        ?.group(1);
    if (bare == null) return null;
    final reader = PropertyReader();
    final ciPath = (reader.getValue('CI_PROJECT_PATH') ?? '').trim();
    if (ciPath.contains('/')) return (ciPath, bare);
    final ws = reader.getGitLabWorkspace()?.trim() ?? '';
    final rp = reader.getGitLabRepository()?.trim() ?? '';
    return (ws.isNotEmpty && rp.isNotEmpty) ? ('$ws/$rp', bare) : null;
  }
}
