/// GitHub Issues backend for tracker-shaped `jira_*` tool calls.
///
/// Routing rule (explicit and opt-in): a tracker call routes to GitHub
/// Issues only when the ticket key matches `gh-<number>` **and** Jira is
/// not configured (no `JIRA_BASE_PATH` or no Jira auth token — the same
/// conditions under which the Jira executors report
/// `{"error": "Jira not configured"}`). Any real Jira config keeps the
/// current Jira behavior — zero regression for Java-parity environments.
/// The keyless `jira_search_by_jql` routes whenever Jira is unconfigured
/// (its only alternative is the config error). One line is logged at
/// dispatch: `tracker: gh-50 → github issues`.
///
/// Routing table (`gh-N` → GitHub Issues on the tracker repo):
///
/// | `jira_*` call            | GitHub routing                                        |
/// |--------------------------|-------------------------------------------------------|
/// | `jira_get_ticket`        | GET issue → Jira-shaped ticket (`key`, `fields.summary`/`description`/`labels`/`status.name`) |
/// | `jira_get_comments`      | GET issue comments → `{comments: [...]}` (Jira shape) |
/// | `jira_post_comment`      | POST issue comment                                    |
/// | `jira_add_label`         | POST issue labels                                     |
/// | `jira_remove_label`      | DELETE issue label (absent label = success)           |
/// | `jira_move_to_status`    | label `status:<name>`; Done-ish names close the issue, Open-ish names reopen it |
/// | `jira_search_by_jql`     | best-effort: key/labels/status/assignee filters only; an honest "unsupported JQL" error otherwise |
///
/// Status mapping for `jira_move_to_status` (normalized lowercase):
/// Done-ish — done, closed, resolved, complete, completed, fixed, merged —
/// also PATCHes the issue `state: closed`; Open-ish — open, reopened, todo,
/// backlog, new, in progress, in development, ready for development,
/// in review, review, ready for review — PATCHes `state: open` on a closed
/// issue. Every other name is label-only. A `status:<name>` label wins over
/// the open/closed state when `jira_get_ticket` derives `status.name`.
///
/// The tracker repo resolves from `DMTOOLS_TRACKER_REPO`, then
/// `GITHUB_REPOSITORY`, then `SOURCE_GITHUB_REPOSITORY` (`owner/repo`
/// form). Auth and transport reuse the `github_*` sync stack
/// (`SOURCE_GITHUB_TOKEN`, [SyncHttpClient]) — no new auth path.
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Tracker-shaped `jira_*` ticket tools eligible for GitHub routing.
const _routableKeyTools = {
  'jira_get_ticket',
  'jira_get_comments',
  'jira_post_comment',
  'jira_add_label',
  'jira_remove_label',
  'jira_move_to_status',
};

/// `gh-<number>` ticket key shape (lowercase, digits only).
final _ghKeyPattern = RegExp(r'^gh-(\d+)$');

/// Status names that close the issue (normalized lowercase).
const _doneStatuses = {
  'done',
  'closed',
  'resolved',
  'complete',
  'completed',
  'fixed',
  'merged',
};

/// Status names that reopen a closed issue (normalized lowercase).
const _openStatuses = {
  'open',
  'reopened',
  'todo',
  'backlog',
  'new',
  'in progress',
  'in development',
  'ready for development',
  'in review',
  'review',
  'ready for review',
};

/// Connection config for one routed GitHub Issues call.
typedef _GhRouteConfig = ({
  String baseUrl,
  Map<String, String> headers,
  String repoSeg,
});

/// Parsed best-effort JQL filters for the GitHub issues list endpoint.
class _JqlFilters {
  /// Matched `labels`/`label` clause values.
  final List<String> labels = [];

  /// GitHub issue `state` query derived from a `status` clause.
  String state = 'all';

  /// Matched `assignee` clause value.
  String? assignee;
}

/// Routes tracker-shaped `jira_*` calls to GitHub Issues when the opt-in
/// rule matches (see the library doc for the routing table).
class TrackerGitHubRouter {
  /// Creates a router; [logger] receives the one-line dispatch log
  /// (defaults to [print]).
  const TrackerGitHubRouter({void Function(String line)? logger})
      : _logger = logger;

  final void Function(String line)? _logger;

  /// The issue number digits of a `gh-<number>` ticket key, else `null`.
  static String? ghIssueNumber(dynamic key) {
    if (key is! String) return null;
    return _ghKeyPattern.firstMatch(key)?.group(1);
  }

  /// Routes [toolName] to GitHub Issues when the opt-in rule matches;
  /// returns `null` to fall through to the normal Jira execution path.
  String? maybeRoute(String toolName, Map<String, dynamic> args) {
    final number = ghIssueNumber(args['key']);
    final isSearch = toolName == 'jira_search_by_jql';
    if (!isSearch &&
        (number == null || !_routableKeyTools.contains(toolName))) {
      return null;
    }
    final reader = PropertyReader();
    if (_jiraConfigured(reader)) return null;
    _log(number != null
        ? 'tracker: gh-$number → github issues'
        : 'tracker: $toolName → github issues');
    final config = _githubConfig(reader);
    if (config is String) {
      return syncErr('GitHub tracker routing unavailable: $config');
    }
    final gh = config as _GhRouteConfig;
    return isSearch
        ? _searchByJql(gh, args)
        : _routeKeyTool(toolName, number!, gh, args);
  }

  void _log(String line) => (_logger ?? print)(line);

  /// Jira counts as configured exactly when the Jira sync executors would
  /// not report "Jira not configured" (base path plus an auth token).
  bool _jiraConfigured(PropertyReader reader) {
    final basePath = reader.getJiraBasePath();
    if (basePath == null || basePath.isEmpty) return false;
    final token = reader.getJiraLoginPassToken();
    return token != null && token.isNotEmpty;
  }

  /// GitHub config for the routed call, or — as an error-message
  /// `String` — the exact missing piece: `SOURCE_GITHUB_TOKEN is not
  /// configured`, or the tracker-repo failure with the offending value
  /// (`tracker repo … is not configured or malformed: "<value>"`), so
  /// run logs say which env var to fix.
  Object _githubConfig(PropertyReader reader) {
    final token = reader.getGithubToken();
    if (token == null || token.isEmpty) {
      return 'SOURCE_GITHUB_TOKEN is not configured';
    }
    final repo = reader.getValue('DMTOOLS_TRACKER_REPO') ??
        reader.getValue('GITHUB_REPOSITORY') ??
        reader.getGithubRepository();
    final seg = _repoSegment(repo);
    if (seg == null) {
      return 'tracker repo (DMTOOLS_TRACKER_REPO / GITHUB_REPOSITORY, '
          'owner/repo form) is not configured or malformed: "$repo"';
    }
    return (
      baseUrl: reader.getGithubBasePath(),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': syncJsonContentType,
      },
      repoSeg: seg,
    );
  }

  /// The `owner/repo` segment of a repo env value, or `null` when the
  /// value is not in `owner/repo` form.
  static String? _repoSegment(String? repo) {
    if (repo == null) return null;
    final parts = repo.split('/');
    if (parts.length != 2 || parts.any((p) => p.trim().isEmpty)) return null;
    return '${parts[0].trim()}/${parts[1].trim()}';
  }

  /// Dispatches a routed ticket tool to its GitHub Issues mapping.
  String _routeKeyTool(
    String toolName,
    String number,
    _GhRouteConfig c,
    Map<String, dynamic> args,
  ) =>
      switch (toolName) {
        'jira_get_ticket' =>
          _withIssue(c, number, (i) => jsonEncode(_ticketFromIssue(i))),
        'jira_get_comments' => _getComments(c, number),
        'jira_post_comment' =>
          _postComment(c, number, syncAsStr(args['comment'])),
        'jira_add_label' => _addLabel(c, number, syncAsStr(args['label'])),
        'jira_remove_label' =>
          _removeLabel(c, number, syncAsStr(args['label'])),
        'jira_move_to_status' =>
          _moveToStatus(c, number, syncAsStr(args['status'])),
        _ => syncErr('Unsupported tracker tool: $toolName'),
      };

  String _issueUrl(_GhRouteConfig c, String number) =>
      '${c.baseUrl}/repos/${c.repoSeg}/issues/$number';

  /// `jira_get_comments` — issue comments in the Jira `{comments: [...]}`
  /// envelope so scripts reading `comment.comments` work unchanged.
  String _getComments(_GhRouteConfig c, String number) {
    final list = _listOrError(
      c,
      '${_issueUrl(c, number)}/comments?per_page=100',
      'comments for gh-$number',
    );
    if (list is String) return list;
    return jsonEncode({
      'comments': [
        for (final comment in list as List)
          if (comment is Map<String, dynamic>) _commentFromJson(comment),
      ],
    });
  }

  /// `jira_post_comment` — POST an issue comment; returns the created
  /// comment in the Jira comment shape.
  String _postComment(_GhRouteConfig c, String number, String body) {
    final resp =
        _postJson(c, '${_issueUrl(c, number)}/comments', {'body': body});
    if (!resp.isOk) return _respError(resp);
    final created = _tryDecode(resp.body);
    if (created is! Map<String, dynamic>) {
      return syncErr('unexpected GitHub comment payload for gh-$number');
    }
    return jsonEncode(_commentFromJson(created));
  }

  /// `jira_add_label` — POST the labels array; returns the updated labels.
  String _addLabel(_GhRouteConfig c, String number, String label) {
    final resp = _postJson(c, '${_issueUrl(c, number)}/labels', {
      'labels': [label],
    });
    return resp.isOk ? resp.body : _respError(resp);
  }

  /// `jira_remove_label` — DELETE the label; an absent label (404) is a
  /// success, matching Jira's set-based label update semantics.
  String _removeLabel(_GhRouteConfig c, String number, String label) {
    final resp = _deleteLabel(c, number, label);
    if (resp.statusCode == 404) return jsonEncode('');
    return resp.isOk ? jsonEncode('') : _respError(resp);
  }

  /// `jira_move_to_status` — swap the `status:*` label, then close/reopen
  /// the issue for Done-ish/Open-ish names (see the library doc).
  String _moveToStatus(_GhRouteConfig c, String number, String status) =>
      _withIssue(
        c,
        number,
        (issue) => _moveIssue(c, number, status, issue),
      );

  /// Label swap + state sync for [_moveToStatus] once the issue is loaded.
  String _moveIssue(
    _GhRouteConfig c,
    String number,
    String status,
    Map<String, dynamic> issue,
  ) {
    final stale =
        _labelNames(issue['labels']).where((l) => l.startsWith('status:'));
    // Best-effort: a failed stale-label delete must not block the move —
    // the new status label is what matters.
    for (final label in stale) {
      _deleteLabel(c, number, label);
    }
    final added = _postJson(c, '${_issueUrl(c, number)}/labels', {
      'labels': ['status:$status'],
    });
    if (!added.isOk) return _respError(added);
    return _syncIssueState(c, number, status, syncAsStr(issue['state']));
  }

  /// Closes/reopens the issue when [status] is Done-ish/Open-ish; any
  /// other name leaves the issue state untouched.
  String _syncIssueState(
    _GhRouteConfig c,
    String number,
    String status,
    String currentState,
  ) {
    final normalized = status.trim().toLowerCase();
    final target = _doneStatuses.contains(normalized)
        ? 'closed'
        : _openStatuses.contains(normalized)
            ? 'open'
            : null;
    if (target == null || target == currentState) return jsonEncode('');
    final resp = SyncHttpClient.patch(
      _issueUrl(c, number),
      headers: c.headers,
      body: jsonEncode({'state': target}),
    );
    return resp.isOk ? jsonEncode('') : _respError(resp);
  }

  /// `jira_search_by_jql` — best-effort GitHub routing. Supports
  /// `key = gh-N` / `key in (gh-N, …)` and AND-ed `labels`/`status`/
  /// `assignee` equality or `in` filters; anything else gets an honest
  /// unsupported-JQL error instead of a silently wrong result.
  String _searchByJql(_GhRouteConfig c, Map<String, dynamic> args) {
    final jql = syncAsStr(args['jql']).trim();
    final numbers = _keyNumbers(jql);
    if (numbers != null) return _ticketsByNumbers(c, numbers);
    final parsed = _parseJqlFilters(jql);
    if (parsed is String) return syncErr(parsed);
    final filters = parsed as _JqlFilters;
    final query = [
      if (filters.labels.isNotEmpty)
        'labels=${filters.labels.map(Uri.encodeQueryComponent).join(',')}',
      'state=${filters.state}',
      if (filters.assignee != null)
        'assignee=${Uri.encodeQueryComponent(filters.assignee!)}',
      'per_page=100',
    ].join('&');
    final list = _listOrError(
        c, '${c.baseUrl}/repos/${c.repoSeg}/issues?$query', 'issues list');
    if (list is String) return list;
    return jsonEncode([
      for (final issue in list as List)
        if (issue is Map<String, dynamic> && issue['pull_request'] == null)
          _ticketFromIssue(issue),
    ]);
  }

  /// The issue numbers of a `key = gh-N` / `key in (gh-N, …)` JQL filter,
  /// or `null` when the JQL carries no key filter.
  static List<String>? _keyNumbers(String jql) {
    final single =
        RegExp(r'key\s*=\s*gh-(\d+)', caseSensitive: false).firstMatch(jql);
    if (single != null) return [single.group(1)!];
    final inClause =
        RegExp(r'key\s+in\s*\(([^)]*)\)', caseSensitive: false).firstMatch(jql);
    if (inClause == null) return null;
    return [
      for (final m in RegExp(r'gh-(\d+)').allMatches(inClause.group(1)!))
        m.group(1)!,
    ];
  }

  /// Fetches issues by number, returning the bare ticket array (the
  /// `jira_search_by_jql` JS contract).
  String _ticketsByNumbers(_GhRouteConfig c, List<String> numbers) {
    final tickets = <Map<String, dynamic>>[];
    for (final number in numbers) {
      final issue = _issueOrError(c, number);
      if (issue is String) return issue;
      tickets.add(_ticketFromIssue(issue as Map<String, dynamic>));
    }
    return jsonEncode(tickets);
  }

  /// Parses AND-ed `field = value` / `field in (…)` clauses into GitHub
  /// issue-list filters. Returns an error message string for anything
  /// outside the supported key/labels/status/assignee surface.
  static Object _parseJqlFilters(String jql) {
    final filters = _JqlFilters();
    if (jql.isEmpty) return filters;
    for (final clause
        in jql.split(RegExp(r'\s+and\s+', caseSensitive: false))) {
      final m = RegExp('^\\s*([A-Za-z]+)\\s*(=|in)\\s*(.+?)\\s*\$')
          .firstMatch(clause);
      if (m == null) return _unsupportedJql(jql);
      final values = _clauseValues(m.group(3)!);
      final error = _applyClause(filters, m.group(1)!.toLowerCase(), values);
      if (error != null) return _unsupportedJql(jql);
    }
    return filters;
  }

  static String _unsupportedJql(String jql) => 'unsupported JQL for GitHub '
      'tracker routing: "$jql" (supported filters: key, labels, status, '
      'assignee — = or in, AND-ed)';

  /// Applies one parsed clause to [filters]; returns non-null when the
  /// field is outside the supported surface.
  static String? _applyClause(
    _JqlFilters filters,
    String field,
    List<String> values,
  ) {
    final value = values.isEmpty ? '' : values.first;
    switch (field) {
      case 'labels' || 'label':
        filters.labels.addAll(values);
        return null;
      case 'status':
        filters.state = _stateForStatus(value);
        return null;
      case 'assignee':
        return _applyAssignee(filters, value);
      default:
        return 'unsupported field: $field';
    }
  }

  /// Applies an `assignee` clause; `currentUser()` is unsupported (the
  /// token owner is not necessarily the intended assignee).
  static String? _applyAssignee(_JqlFilters filters, String value) {
    if (value.isEmpty || value == 'currentUser()') {
      return 'unsupported assignee value';
    }
    filters.assignee = value;
    return null;
  }

  /// Splits a clause value (`'a'` or `(a, b)`) into bare values.
  static List<String> _clauseValues(String raw) {
    var value = raw.trim();
    if (value.startsWith('(') && value.endsWith(')')) {
      value = value.substring(1, value.length - 1);
    }
    return [
      for (final part in value.split(','))
        if (part.trim().isNotEmpty) _unquote(part.trim()),
    ];
  }

  static String _unquote(String value) {
    if (value.length >= 2 &&
        (value.startsWith("'") && value.endsWith("'") ||
            value.startsWith('"') && value.endsWith('"'))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Maps a status filter value to the GitHub issue `state` query.
  static String _stateForStatus(String status) {
    final normalized = status.trim().toLowerCase();
    if (_doneStatuses.contains(normalized)) return 'closed';
    if (_openStatuses.contains(normalized)) return 'open';
    return 'all';
  }

  // ── HTTP helpers ─────────────────────────────────────────────────────

  /// Runs [fn] with the issue map for [number]; an error envelope short-
  /// circuits when the fetch or decode fails.
  String _withIssue(
    _GhRouteConfig c,
    String number,
    String Function(Map<String, dynamic>) fn,
  ) {
    final issue = _issueOrError(c, number);
    return issue is String ? issue : fn(issue as Map<String, dynamic>);
  }

  /// The issue map for [number], or an error-envelope string on failure.
  Object _issueOrError(_GhRouteConfig c, String number) {
    final what = 'issue for gh-$number';
    final result = _getJson(c, _issueUrl(c, number), what);
    if (result is Map<String, dynamic> || result is String) return result;
    return syncErr('unexpected GitHub $what payload');
  }

  /// The decoded JSON list at [url], or an error-envelope string.
  Object _listOrError(_GhRouteConfig c, String url, String what) {
    final result = _getJson(c, url, what);
    if (result is List || result is String) return result;
    return syncErr('unexpected GitHub $what payload');
  }

  /// GETs [url] and decodes the body; transport, non-2xx, and decode
  /// failures surface as an error-envelope string.
  Object _getJson(_GhRouteConfig c, String url, String what) {
    final resp = SyncHttpClient.get(url, headers: c.headers);
    if (!resp.isOk) return _respError(resp);
    return _tryDecode(resp.body) ?? syncErr('unexpected GitHub $what payload');
  }

  /// POSTs a JSON payload to [url].
  SyncHttpResponse _postJson(_GhRouteConfig c, String url, Object payload) =>
      SyncHttpClient.post(url, headers: c.headers, body: jsonEncode(payload));

  /// DELETEs one label from the issue.
  SyncHttpResponse _deleteLabel(
          _GhRouteConfig c, String number, String label) =>
      SyncHttpClient.delete(
        '${_issueUrl(c, number)}/labels/${Uri.encodeComponent(label)}',
        headers: c.headers,
      );

  // ── Payload mapping ──────────────────────────────────────────────────

  /// Maps a GitHub issue to the Jira ticket shape agent scripts consume:
  /// `key` plus `fields.summary` / `fields.description` / `fields.labels`
  /// / `fields.status.name`. A `status:<name>` label wins over the raw
  /// open/closed state for `status.name`.
  static Map<String, dynamic> _ticketFromIssue(Map<String, dynamic> issue) {
    final labels = _labelNames(issue['labels']);
    String? statusLabel;
    for (final label in labels) {
      if (label.startsWith('status:')) {
        statusLabel = label.substring('status:'.length);
        break;
      }
    }
    return {
      'key': 'gh-${issue['number']}',
      'fields': {
        'summary': issue['title'] ?? '',
        'description': issue['body'] ?? '',
        'labels': labels,
        'status': {
          'name': statusLabel ?? (issue['state'] == 'closed' ? 'Done' : 'Open'),
        },
        'issuetype': {'name': 'Issue'},
      },
    };
  }

  /// Maps a GitHub issue comment to the Jira comment shape (`body`,
  /// `author.displayName`, `created`, `updated`).
  static Map<String, dynamic> _commentFromJson(Map<String, dynamic> c) => {
        'id': c['id']?.toString(),
        'body': c['body'] ?? '',
        'author': {
          'displayName': (c['user'] as Map?)?['login'] ?? '',
        },
        'created': c['created_at'],
        'updated': c['updated_at'],
      };

  /// Label names from a GitHub `labels` payload (string or object entries).
  static List<String> _labelNames(dynamic raw) => [
        for (final label in (raw is List ? raw : const []))
          if (label is String)
            label
          else if (label is Map && label['name'] != null)
            label['name'].toString(),
      ];

  static dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Failure envelope for a non-2xx (or failed curl) response.
  static String _respError(SyncHttpResponse resp) => resp.statusCode == 0
      ? syncErr('HTTP request failed: ${resp.body}')
      : syncErr('HTTP ${resp.statusCode}: ${_snippet(resp.body)}');

  static String _snippet(String body) =>
      body.length <= 200 ? body : '${body.substring(0, 200)}…';
}
