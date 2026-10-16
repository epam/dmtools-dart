/// GitHub-issues ticket source for [TeammateJob] — lets `inputJql` carry a
/// GitHub search query so the issues-driven flow reuses the exact Teammate
/// mechanism (override `inputJql` in a child config, the job fetches the
/// tickets, builds `input/<contextId>/`, and runs the agent):
///
/// ```json
/// {"params": {"inputJql": "repo:${GITHUB_REPOSITORY} is:issue is:open label:bug"}}
/// ```
///
/// `${VAR}` refs expand from the process environment (`GITHUB_REPOSITORY`
/// is set by GitHub Actions; locally fall back to an explicit value or a
/// `repo:` qualifier in the query itself). Detection is
/// [looksLikeGithubQuery] — anything with GitHub search tokens routes to
/// this source, everything else stays Jira JQL (Java parity).
///
/// A single issue is addressed directly — no search round-trip:
///
/// ```json
/// {"params": {"inputJql": "repo:owner/name#42"}}
/// ```
///
/// `#42` and `GH-42` also work when `GITHUB_REPOSITORY` is set — the form
/// an issue-triggered workflow passes after resolving
/// `github.event.issue.number`.
///
/// The fetched issues hydrate into the same raw-tracker shape the Jira
/// source produces (`key`, `fields.summary`, `fields.description`,
/// `fields.status.name`, `fields.comment.comments[].author.displayName`
/// /`.body`/`.created`) — `TicketInputContextBuilder` is shape-agnostic.
library;

import 'dart:convert';
import 'dart:io';

import '../config/property_reader.dart';
import '../integrations/github/github_http_client.dart';

/// Whether [inputJql] is a GitHub search query rather than Jira JQL.
bool looksLikeGithubQuery(String inputJql) {
  final t = inputJql.toLowerCase();
  const markers = [
    'is:issue',
    'is:pr',
    'repo:',
    'label:',
    'assignee:',
    'state:',
    'type:issue',
  ];
  if (markers.any(t.contains)) return true;
  // Direct-issue forms: `repo:o/r#42`, `#42`, `gh-42`, `42`.
  return RegExp(
    r'^(repo:[\w./-]+#\d+|#\d+|gh-\d+|\d+)$',
    caseSensitive: false,
  ).hasMatch(inputJql.trim());
}

/// Expands `${VAR}` refs from [env] (defaults to the process environment);
/// unresolved names become empty strings.
String expandEnvRefs(String query, [Map<String, String>? env]) {
  final source = env ?? Platform.environment;
  return query.replaceAllMapped(
    RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'),
    (m) => source[m.group(1)] ?? '',
  );
}

/// Fetches GitHub issues matching a search query and hydrates them into
/// the Teammate ticket shape.
///
/// [getJson] is overridable for tests; the default issues a bearer-authed
/// REST call through [GithubHttpClient] (`SOURCE_GITHUB_TOKEN` /
/// `GITHUB_TOKEN` — the same credentials the rest of the machine uses).
class GithubIssueSource {
  /// Creates the source; [getJson] performs an authenticated GET against
  /// api.github.com and decodes the JSON body.
  GithubIssueSource({
    Future<Map<String, dynamic>> Function(String path)? getJson,
    Map<String, String>? env,
  })  : _getJson = getJson ?? _defaultGetJson,
        _env = env ?? Platform.environment;

  final Future<Map<String, dynamic>> Function(String path) _getJson;
  final Map<String, String> _env;

  /// Search + hydrate the issues matching [query]. A single-issue form
  /// (`repo:o/r#42`, `#42`, `GH-42`, `42` — see [_parseSingleIssue]) skips
  /// the search round-trip and fetches the issue directly.
  Future<List<Map<String, dynamic>>> fetch(String query) async {
    final effective = expandEnvRefs(query, _env).trim();
    if (effective.isEmpty) return const [];
    final single = _parseSingleIssue(effective);
    if (single != null) return [await _fetchIssue(single.$1, single.$2)];
    final repo = _resolveRepo(effective);
    final searchPath =
        '/search/issues?per_page=50&q=${Uri.encodeQueryComponent(effective)}';
    final search = await _getJson(searchPath);
    final items = (search['items'] as List?)?.cast<Map>() ?? const [];
    final tickets = <Map<String, dynamic>>[];
    for (final item in items) {
      final coords = _issueCoords(item, repo);
      if (coords == null) continue;
      tickets.add(await _fetchIssue(coords.$1, int.parse(coords.$2)));
    }
    return tickets;
  }

  /// Single-issue forms with their repo resolved: `repo:owner/name#42`
  /// carries the repo inline; `#42`, `GH-42` and bare `42` resolve against
  /// `GITHUB_REPOSITORY` (a failure when unset — the number alone is
  /// ambiguous). Returns `null` when [effective] is a search query.
  (String, int)? _parseSingleIssue(String effective) {
    final inline = RegExp(r'^repo:([\w.-]+/[\w.-]+)#(\d+)$')
        .firstMatch(effective)
        ?.groups(const [1, 2]);
    if (inline != null) return (inline[0]!, int.parse(inline[1]!));
    final bare =
        RegExp(r'^(?:#|[Gg][Hh]-)?(\d+)$').firstMatch(effective)?.group(1);
    if (bare == null) return null;
    final repo = _env['GITHUB_REPOSITORY'];
    if (repo == null || !repo.contains('/')) {
      throw StateError(
        'inputJql "$effective" needs the GITHUB_REPOSITORY env '
        '(or the repo:owner/name#<number> form)',
      );
    }
    return (repo, int.parse(bare));
  }

  /// Issue + comments hydration for one issue number.
  Future<Map<String, dynamic>> _fetchIssue(String repo, int number) async {
    final issue = await _getJson('/repos/$repo/issues/$number');
    final comments = await _getJson('/repos/$repo/issues/$number/comments');
    return _toTicket(issue, comments, number);
  }

  /// Repo qualifier resolution: explicit `repo:owner/name` in the query,
  /// else the `GITHUB_REPOSITORY` env (`owner/name`), else a failure —
  /// an unqualified search would fan out across every repository.
  String _resolveRepo(String effective) {
    final match = RegExp(r'repo:([\w.-]+/[\w.-]+)').firstMatch(effective);
    if (match != null) return match.group(1)!;
    final fromEnv = _env['GITHUB_REPOSITORY'];
    if (fromEnv != null && fromEnv.contains('/')) return fromEnv;
    throw StateError(
      'GitHub inputJql needs a repo:owner/name qualifier or the '
      'GITHUB_REPOSITORY env — query: "$effective"',
    );
  }

  /// Extracts the repo (`owner/name`) and the issue number from a search
  /// item (falls back to the resolved repo for older payloads that omit
  /// `repository_url`).
  (String, String)? _issueCoords(Map item, String repo) {
    final number = item['number'];
    if (number is! int) return null;
    final url = item['repository_url'] as String?;
    final match = url == null
        ? null
        : RegExp(r'/repos/([\w.-]+/[\w.-]+)$').firstMatch(url);
    return (match?.group(1) ?? repo, '$number');
  }

  /// Maps the issue + comments payloads into the raw-tracker shape
  /// `TicketInputContextBuilder` consumes.
  Map<String, dynamic> _toTicket(
    Map<String, dynamic> issue,
    Map<String, dynamic> comments,
    int number,
  ) {
    final rawComments =
        (comments as Map?)?['comments'] is List ? comments : const {};
    return {
      'key': 'GH-$number',
      'fields': {
        'summary': issue['title'],
        'description': issue['body'] ?? '',
        'status': {'name': issue['state']},
        if (issue['labels'] is List)
          'labels': [
            for (final l in (issue['labels'] as List).cast<Map>())
              {'name': l['name']},
          ],
        'comment': {
          'comments': [
            for (final c
                in (rawComments['comments'] as List? ?? const []).cast<Map>())
              {
                'author': {'displayName': (c['user'] as Map?)?['login']},
                'created': c['created_at'],
                'body': c['body'],
              },
          ],
        },
      },
    };
  }

  static Future<Map<String, dynamic>> _defaultGetJson(String path) async {
    final client = GithubHttpClient(PropertyReader());
    final body = await client.get(path);
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

/// [TeammateTicketSource]-shaped default for GitHub `inputJql` queries.
Future<List<Map<String, dynamic>>> githubIssueTicketSource(
  String inputJql,
) async {
  return GithubIssueSource().fetch(inputJql);
}
