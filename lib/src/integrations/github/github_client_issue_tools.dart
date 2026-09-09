/// Issue-tracker client methods — Java `GitHubIssues.java` (dm.ai #543).
///
/// Part of the [GithubClient] library so the extension shares private
/// transport access. The tracker tools resolve issue references exactly
/// like Java: explicit `owner`/`repo`/`number` parts, a composite
/// `owner/repo#123` (or bare-number) `key`, then the configured
/// `SOURCE_GITHUB_WORKSPACE` / `SOURCE_GITHUB_REPOSITORY` defaults.
part of 'github_client.dart';

/// A resolved GitHub issue reference: owner + repo + issue number.
class GhIssueRef {
  /// The repository owner (user or organization).
  final String owner;

  /// The repository name.
  final String repo;

  /// The issue number.
  final int number;

  /// Creates a resolved reference.
  const GhIssueRef(this.owner, this.repo, this.number);
}

/// Composite issue-key pattern: `owner/repo#123`.
final RegExp _ghCompositeKey = RegExp(r'^[\w.-]+/[\w.-]+#(\d+)$');

/// Bare issue-number pattern: `123`.
final RegExp _ghBareNumber = RegExp(r'^\d+$');

/// Resolves a GitHub issue reference exactly like Java
/// `GitHubIssues.resolveIssueRef`: a parseable [key] overrides the explicit
/// parts (a composite key fills all three, a bare number only the number);
/// blank parts fall back to the configured defaults; anything still missing
/// throws [ArgumentError] with the Java message.
GhIssueRef resolveGhIssueRef(String? key, String? owner, String? repo,
    int? number) {
  var resolvedOwner = owner;
  var resolvedRepo = repo;
  var resolvedNumber = number;
  final k = key?.trim() ?? '';
  if (k.isNotEmpty) {
    final composite = _ghCompositeKey.firstMatch(k);
    if (composite != null) {
      resolvedNumber = int.parse(composite.group(1)!);
      resolvedOwner = k.substring(0, k.indexOf('/'));
      resolvedRepo = k.substring(k.indexOf('/') + 1, k.indexOf('#'));
    } else if (_ghBareNumber.hasMatch(k)) {
      resolvedNumber = int.parse(k);
    } else {
      throw ArgumentError(
        "Cannot parse GitHub issue key: '$key'. Expected 'owner/repo#123' "
        'or a bare issue number.',
      );
    }
  }
  resolvedOwner = _ghBlankToNull(resolvedOwner) ?? _ghDefaultWorkspace();
  resolvedRepo = _ghBlankToNull(resolvedRepo) ?? _ghDefaultRepository();
  if (resolvedOwner == null || resolvedRepo == null || resolvedNumber == null) {
    throw ArgumentError(
      "Issue reference requires owner/repo/number or a composite key "
      "'owner/repo#123'.",
    );
  }
  return GhIssueRef(resolvedOwner, resolvedRepo, resolvedNumber);
}

/// Resolves the composite project reference `owner/repo` used by
/// `github_create_issue`: an explicit [key] containing `/` wins, blank
/// parts fall back to the configured defaults; `null` when unresolved.
(String, String)? _resolveProjectRef(String? key, String? owner, String? repo) {
  var resolvedOwner = owner;
  var resolvedRepo = repo;
  final k = key?.trim() ?? '';
  if (k.isNotEmpty && k.contains('/')) {
    resolvedOwner = k.substring(0, k.indexOf('/'));
    resolvedRepo = k.substring(k.indexOf('/') + 1);
  }
  resolvedOwner = _ghBlankToNull(resolvedOwner) ?? _ghDefaultWorkspace();
  resolvedRepo = _ghBlankToNull(resolvedRepo) ?? _ghDefaultRepository();
  if (resolvedOwner == null || resolvedRepo == null) return null;
  return (resolvedOwner, resolvedRepo);
}

/// [value] trimmed, or `null` when blank.
String? _ghBlankToNull(String? value) {
  final t = value?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// [value] parsed as an int, or `null` when blank/unparseable.
int? _ghIntOrNull(String? value) {
  final t = _ghBlankToNull(value);
  return t == null ? null : int.tryParse(t);
}

/// Java `BasicGithub.getDefaultWorkspace` — `SOURCE_GITHUB_WORKSPACE`.
String? _ghDefaultWorkspace() =>
    _ghBlankToNull(PropertyReader().getGithubWorkspace());

/// Java `BasicGithub.getDefaultRepository` — `SOURCE_GITHUB_REPOSITORY`.
String? _ghDefaultRepository() =>
    _ghBlankToNull(PropertyReader().getGithubRepository());

/// Tracker-facing issue methods on [GithubClient].
extension GithubIssueTrackerTools on GithubClient {
  /// `github_search_issues` — GET `search/issues?q=...&per_page=100`.
  ///
  /// Java `GitHubIssues.searchIssues`: the query is scoped with
  /// `repo:<workspace>/<repository>` when it has no `repo:` term and the
  /// defaults are configured.
  Future<Map<String, dynamic>> searchIssues(
    String query, [
    String? workspace,
    String? repository,
  ]) async {
    var scopedQuery = query;
    final ws = _ghBlankToNull(workspace) ?? _ghDefaultWorkspace();
    final rp = _ghBlankToNull(repository) ?? _ghDefaultRepository();
    if (!scopedQuery.contains('repo:') && ws != null && rp != null) {
      scopedQuery = 'repo:$ws/$rp $scopedQuery';
    }
    final body = await _http.get(
      'search/issues',
      queryParams: {'q': scopedQuery, 'per_page': '100'},
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `github_reopen_issue` — PATCH `repos/{o}/{r}/issues/{n}` state open.
  Future<Map<String, dynamic>> reopenIssue(
    String? owner,
    String? repo,
    int? number, {
    String? key,
  }) async {
    final ref = resolveGhIssueRef(key, owner, repo, number);
    final response = await _http.patch(
      'repos/${ref.owner}/${ref.repo}/issues/${ref.number}',
      body: jsonEncode({'state': 'open'}),
    );
    return jsonDecode(response) as Map<String, dynamic>;
  }

  /// `github_assign_issue` — POST
  /// `repos/{o}/{r}/issues/{n}/assignees` with the single-element
  /// assignees array.
  Future<Map<String, dynamic>> assignIssue(
    String? owner,
    String? repo,
    int? number,
    String user, {
    String? key,
  }) async {
    final ref = resolveGhIssueRef(key, owner, repo, number);
    final response = await _http.post(
      'repos/${ref.owner}/${ref.repo}/issues/${ref.number}/assignees',
      body: jsonEncode({
        'assignees': [user],
      }),
    );
    return jsonDecode(response) as Map<String, dynamic>;
  }

  /// `github_move_issue_to_status` — close/reopen/label semantics.
  ///
  /// Java `GitHubIssues.moveIssueToStatus`: done-family statuses close,
  /// open-family statuses reopen, anything else is applied as a label.
  /// Returns the issue JSON for close/reopen, or the resulting label array
  /// for the label branch — Java serializes whichever raw payload the
  /// underlying call produced.
  Future<Object> moveIssueToStatus(
    String? owner,
    String? repo,
    int? number,
    String statusName, {
    String? key,
  }) async {
    if (statusName.trim().isEmpty) {
      throw ArgumentError('statusName is required');
    }
    final ref = resolveGhIssueRef(key, owner, repo, number);
    final s = statusName.trim().toLowerCase();
    if (_ghClosedStatuses.contains(s)) {
      return closeIssue(ref.owner, ref.repo, ref.number);
    }
    if (_ghOpenStatuses.contains(s)) {
      return reopenIssue(ref.owner, ref.repo, ref.number);
    }
    return addLabels(ref.owner, ref.repo, ref.number, [statusName.trim()]);
  }
}

/// Statuses that close the issue (Java parity).
const _ghClosedStatuses = {'done', 'closed', 'completed', 'resolved'};

/// Statuses that reopen the issue (Java parity).
const _ghOpenStatuses = {
  'open',
  'reopened',
  'reopen',
  'todo',
  'backlog',
  'in progress',
};
