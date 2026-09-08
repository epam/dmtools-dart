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
  return markers.any(t.contains);
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

  /// Search + hydrate the issues matching [query].
  Future<List<Map<String, dynamic>>> fetch(String query) async {
    final effective = expandEnvRefs(query, _env).trim();
    if (effective.isEmpty) return const [];
    final repo = _resolveRepo(effective);
    final searchPath =
        '/search/issues?per_page=50&q=${Uri.encodeQueryComponent(effective)}';
    final search = await _getJson(searchPath);
    final items = (search['items'] as List?)?.cast<Map>() ?? const [];
    final tickets = <Map<String, dynamic>>[];
    for (final item in items) {
      final coords = _issueCoords(item, repo);
      if (coords == null) continue;
      final (apiBase, numberStr) = coords;
      final number = int.parse(numberStr);
      final issue = await _getJson('$apiBase/issues/$number');
      final comments = await _getJson('$apiBase/issues/$number/comments');
      tickets.add(_toTicket(issue, comments, number));
    }
    return tickets;
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

  /// Extracts the REST base (`/repos/owner/name`) and the issue number
  /// from a search item (falls back to the resolved repo for older
  /// payloads that omit `repository_url`).
  (String, String)? _issueCoords(Map item, String repo) {
    final number = item['number'];
    if (number is! int) return null;
    final url = item['repository_url'] as String?;
    final match = url == null
        ? null
        : RegExp(r'/repos/([\w.-]+/[\w.-]+)$').firstMatch(url);
    final base = match == null ? '/repos/$repo' : '/repos/${match.group(1)}';
    return (base, '$number');
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
