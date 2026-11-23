/// GitLab-issues ticket source for [TeammateJob] — Java `GitLabTrackerClient`
/// / `GitLabTicket` parity (epam/dm.ai#876).
///
/// Supports:
/// - Single-issue or key-list queries (`namespace/project#42`, `gl-42`,
///   `#42`, or bare `42` with a default project configured via
///   `CI_PROJECT_PATH` or `GITLAB_WORKSPACE` + `GITLAB_REPOSITORY`).
/// - Free-text search queries routed through `gitlab_search_issues` on the
///   configured default project.
///
/// Fetched issues hydrate into the standard Teammate ticket shape (`key`,
/// `fields.summary`, `fields.description`, `fields.status.name`,
/// `fields.comment.comments[].author.name`/`.body`/`.created`).
library;

import 'dart:convert';

import '../config/property_reader.dart';
import '../js/sync_tool_dispatcher.dart';
import 'github_ticket_source.dart' show parseIssueKeyTokens;
import 'gitlab_tracker_client.dart';

final RegExp _glExplicitKey = RegExp(
  r'^(?:[\w.-]+(?:/[\w.-]+)+#\d+|gl-\d+)$',
  caseSensitive: false,
);

/// Whether [inputJql] is a GitLab-specific issue reference (`gl-42` or a
/// multi-segment `group/sub/project#42`).
bool looksLikeGitlabQuery(String inputJql) {
  final trimmed = inputJql.trim();
  if (trimmed.isEmpty) return false;
  return parseGitlabIssueKeys(trimmed).isNotEmpty &&
      (trimmed.toLowerCase().contains('gl-') ||
          RegExp(r'[\w.-]+/[\w.-]+/[\w.-]+#\d+').hasMatch(trimmed));
}

/// Parses [query] when it consists solely of comma/whitespace-separated
/// GitLab issue keys (`namespace/project#N` or `gl-N`).
List<String> parseGitlabIssueKeys(String? query) =>
    parseIssueKeyTokens(query, _glExplicitKey);

/// Default [TeammateJob] ticket source for GitLab issues (`DEFAULT_TRACKER=gitlab`).
Future<List<Map<String, dynamic>>> gitlabIssueTicketSource(
  String inputJql, {
  String? Function(String toolName, Map<String, dynamic> args)? execute,
}) async {
  final exec = execute ?? SyncToolDispatcher(PropertyReader()).execute;
  final trimmed = inputJql.trim();
  if (trimmed.isEmpty) return const [];
  final keyTokens = _extractDirectGitlabKeys(trimmed);
  if (keyTokens.isNotEmpty) {
    return [
      for (final token in keyTokens)
        if (_fetchSingleGitlabTicket(token, exec) case final t?) t,
    ];
  }
  final rawSearch = exec('gitlab_search_issues', {'query': trimmed});
  final decoded = _tryDecodeJson(rawSearch);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded.whereType<Map<String, dynamic>>())
      _hydrateGitlabIssueMap(item, exec),
  ];
}

List<String> _extractDirectGitlabKeys(String trimmed) {
  final explicit = parseGitlabIssueKeys(trimmed);
  if (explicit.isNotEmpty) return explicit;
  if (RegExp(r'^#?\d+$').hasMatch(trimmed)) {
    return [trimmed.startsWith('#') ? trimmed.substring(1) : trimmed];
  }
  return const [];
}

Map<String, dynamic>? _fetchSingleGitlabTicket(
  String keyToken,
  String? Function(String, Map<String, dynamic>) exec,
) {
  final ref = GitlabTrackerClient().resolveIssueRef(keyToken);
  final canonicalKey = ref != null ? '${ref.$1}#${ref.$2}' : keyToken;
  final rawIssue = exec('gitlab_get_issue', {'key': canonicalKey});
  final issue = _tryDecodeJson(rawIssue);
  if (issue is! Map<String, dynamic> || issue['error'] != null) return null;
  return _hydrateGitlabIssueMap(issue, exec, fallbackKey: canonicalKey);
}

Map<String, dynamic> _hydrateGitlabIssueMap(
  Map<String, dynamic> issue,
  String? Function(String, Map<String, dynamic>) exec, {
  String? fallbackKey,
}) {
  final key = _canonicalKeyOf(issue, fallbackKey);
  final rawNotes =
      key.isNotEmpty ? exec('gitlab_get_issue_comments', {'key': key}) : null;
  final notesDecoded = _tryDecodeJson(rawNotes);
  final notes = notesDecoded is List ? notesDecoded : const [];
  return hydrateGitlabIssue(issue, notes, key: key);
}

String _canonicalKeyOf(Map<String, dynamic> issue, String? fallbackKey) {
  final refs = issue['references'];
  final full = refs is Map ? (refs['full']?.toString().trim() ?? '') : '';
  if (full.isNotEmpty) return full;
  if (fallbackKey != null && fallbackKey.isNotEmpty) return fallbackKey;
  final iid = issue['iid']?.toString() ?? '';
  if (iid.isEmpty) return '';
  final resolved = GitlabTrackerClient().resolveIssueRef(iid);
  return resolved != null ? '${resolved.$1}#${resolved.$2}' : 'GL-$iid';
}

/// Converts a GitLab issue JSON map and its notes list into the standard
/// Teammate ticket map (`key`, `fields.summary`, `fields.description`,
/// `fields.status.name`, `fields.comment.comments`).
Map<String, dynamic> hydrateGitlabIssue(
  Map<String, dynamic> issue,
  List<dynamic> notes, {
  required String key,
}) =>
    {
      'key': key,
      'fields': {
        'summary': issue['title'] ?? '',
        'description': issue['description'] ?? '',
        'status': {'name': issue['state'] ?? 'opened'},
        'comment': {
          'comments': [
            for (final n in notes.whereType<Map>())
              {
                'author': {
                  'name': (n['author'] is Map)
                      ? ((n['author'] as Map)['username'] ??
                          (n['author'] as Map)['name'])
                      : null,
                },
                'created': n['created_at'],
                'body': n['body'] ?? '',
              },
          ],
        },
      },
    };

dynamic _tryDecodeJson(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}
