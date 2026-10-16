/// Write-side GitHub issues tracker client — Java `GitHubTrackerClient` /
/// `GitHubTicket` parity (gh-35).
///
/// Java injects a `TrackerClient` into jobs (`DEFAULT_TRACKER=github` via
/// `TrackerModule`); the Dart runtime's tracker surface is the `github_*`
/// sync tool catalog, so this client routes over it through a
/// [SyncToolExecute] dispatcher — the same pattern [TeammateJob] uses for
/// its Jira source. Operations map 1:1 onto the Java tracker client:
///
/// | Java                       | Dart / tool                        |
/// |----------------------------|------------------------------------|
/// | `postComment`              | `github_create_comment`            |
/// | `moveToStatus`             | `github_move_issue_to_status`      |
/// | `assignTo`                 | `github_assign_issue`              |
/// | `addLabelIfNotExists`      | `github_add_labels`                |
/// | `deleteLabelInTicket`      | `github_remove_label`              |
/// | `createTicketInProject`    | `github_create_issue`              |
///
/// Tickets are keyed `owner/repo#number` (Java `GitHubTicket
/// .getTicketKey()` composite). A bare number resolves against the
/// configured default repo (`SOURCE_GITHUB_WORKSPACE` /
/// `SOURCE_GITHUB_REPOSITORY`, or the CI-provided `GITHUB_REPOSITORY`);
/// the Dart ticket source's `GH-<n>` keys resolve the same way. Failures
/// surface as [StateError] — Java's `IOException` parity.
library;

import 'dart:convert';

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import '../js/sync_tool_dispatcher.dart';

/// The dispatch seam this client routes through (the sync tool surface).
/// [SyncToolDispatcher.execute] returns `null` for undispatchable calls,
/// which this client reports as an error.
typedef SyncToolExecute = String? Function(
  String toolName,
  Map<String, dynamic> args,
);

/// A resolved `owner/repo#number` reference.
typedef TrackerIssueRef = (String owner, String repo, String number);

/// Write-side tracker operations backed by GitHub issues.
class GithubTrackerClient {
  /// Creates the client; [execute] defaults to the real sync dispatcher.
  GithubTrackerClient({SyncToolExecute? execute})
      : _execute = execute ?? _defaultExecute;

  final SyncToolExecute _execute;

  /// Whether GitHub tracker operations can run (`SOURCE_GITHUB_TOKEN`
  /// present — Java `getInstance()` returns null without it).
  bool get isConfigured => (PropertyReader().getGithubToken() ?? '').isNotEmpty;

  /// Posts a comment to the issue [key] refers to (Java `postComment`).
  void postComment(String key, String body) => _run(
        key,
        'github_create_comment',
        (owner, repo, number) => {
          'workspace': owner,
          'repository': repo,
          'pullRequestId': number,
          'body': body,
        },
      );

  /// Moves the issue to [status] — done/closed close it, open-ish names
  /// reopen it, anything else lands as a label (Java `moveToStatus`).
  void moveToStatus(String key, String status) => _run(
        key,
        'github_move_issue_to_status',
        (owner, repo, number) => {
          'owner': owner,
          'repo': repo,
          'number': number,
          'statusName': status,
        },
      );

  /// Assigns the issue to [user] (Java `assignTo`).
  void assignTo(String key, String user) => _run(
        key,
        'github_assign_issue',
        (owner, repo, number) => {
          'owner': owner,
          'repo': repo,
          'number': number,
          'user': user,
        },
      );

  /// Adds [label] to the issue (Java `addLabelIfNotExists` — existence
  /// checks belong to the caller, which holds the ticket labels).
  void addLabel(String key, String label) => _run(
        key,
        'github_add_labels',
        (owner, repo, number) => {
          'owner': owner,
          'repo': repo,
          'number': number,
          'labels': [label],
        },
      );

  /// Removes [label] from the issue (Java `deleteLabelInTicket`).
  void removeLabel(String key, String label) => _run(
        key,
        'github_remove_label',
        (owner, repo, number) => {
          'owner': owner,
          'repo': repo,
          'number': number,
          'label': label,
        },
      );

  /// Creates an issue in [project] (`owner/repo`) and returns the
  /// composite key `owner/repo#<number>` (Java `createTicketInProject`
  /// → `GitHubTicket.getCompositeKey()`).
  String createTicket({
    required String project,
    required String summary,
    String description = '',
  }) {
    final parts = project.split('/');
    if (parts.length != 2 || parts.any((p) => p.trim().isEmpty)) {
      throw StateError(
        "createTicket needs an 'owner/repo' project, got: '$project'",
      );
    }
    final raw = _execute('github_create_issue', {
      'owner': parts[0].trim(),
      'repo': parts[1].trim(),
      'title': summary,
      if (description.isNotEmpty) 'body': description,
    });
    final decoded = raw == null ? null : _tryDecode(raw);
    final number = decoded is Map ? decoded['number'] : null;
    if (number == null) {
      throw StateError(
        'github_create_issue returned no issue number: '
        '${raw == null ? 'tool not dispatchable' : _errorOf(raw)}',
      );
    }
    return '${parts[0].trim()}/${parts[1].trim()}#$number';
  }

  /// Dispatches [tool] with the resolved parts of [key] and the args
  /// built by [argsFor]; [StateError] on unresolvable keys or error
  /// envelopes (Java IOException parity).
  void _run(
    String key,
    String tool,
    Map<String, dynamic> Function(String owner, String repo, String number)
        argsFor,
  ) {
    final ref = resolveIssueRef(key);
    if (ref == null) {
      throw StateError(
        "Cannot parse GitHub issue key: '$key'. Expected "
        "'owner/repo#123', 'gh-123', or a bare issue number with the "
        'default repository configured.',
      );
    }
    final (owner, repo, number) = ref;
    final raw = _execute(tool, argsFor(owner, repo, number));
    final error = raw == null
        ? '$tool is not dispatchable in this runtime'
        : _errorOf(raw);
    if (error != null) throw StateError(error);
  }

  /// Resolves [key] to `(owner, repo, number)`:
  /// `owner/repo#42` verbatim; `gh-42` (any case) and bare `42` against
  /// `GITHUB_REPOSITORY`, then `SOURCE_GITHUB_WORKSPACE` +
  /// `SOURCE_GITHUB_REPOSITORY`. `null` when anything is missing.
  TrackerIssueRef? resolveIssueRef(String key) {
    final trimmed = key.trim();
    final composite =
        RegExp(r'^([\w.-]+)/([\w.-]+)#(\d+)$').firstMatch(trimmed);
    if (composite != null) {
      return (
        composite.group(1)!,
        composite.group(2)!,
        composite.group(3)!,
      );
    }
    final bare = RegExp(r'^(?:gh-)?(\d+)$', caseSensitive: false)
        .firstMatch(trimmed)
        ?.group(1);
    if (bare == null) return null;
    final reader = PropertyReader();
    final ghRepo = (reader.getValue('GITHUB_REPOSITORY') ?? '').trim();
    if (ghRepo.contains('/')) {
      final split = ghRepo.split('/');
      return (split[0].trim(), split[1].trim(), bare);
    }
    final owner = reader.getGithubWorkspace()?.trim() ?? '';
    final repo = reader.getGithubRepository()?.trim() ?? '';
    if (owner.isEmpty || repo.isEmpty) return null;
    return (owner, repo, bare);
  }

  /// The `error` field of an `{"error": …}` envelope, else `null`.
  static String? _errorOf(String raw) {
    final decoded = _tryDecode(raw);
    if (decoded is Map && decoded['error'] != null) {
      return decoded['error'].toString();
    }
    return null;
  }

  static dynamic _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  /// The real dispatch entry (fresh reader — config can change between
  /// runs, matching the sync tools' read-per-dispatch contract).
  static String? _defaultExecute(String tool, Map<String, dynamic> args) =>
      SyncToolDispatcher(PropertyReader()).execute(tool, args);
}
