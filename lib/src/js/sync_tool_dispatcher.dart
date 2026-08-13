/// Dispatches MCP tool calls using synchronous HTTP (curl subprocess).
///
/// This is the `executeToolViaJava` implementation for real agent scripts.
/// It builds integration clients on the fly from [PropertyReader] config,
/// makes blocking HTTP calls via [SyncHttpClient], and returns JSON results.
///
/// Supported tools (initial set, per the sync-dispatch phase plan):
/// - Jira: `jira_get_ticket`, `jira_post_comment`, `jira_search_by_jql`,
///   `jira_add_label`, `jira_remove_label`, `jira_move_to_status`
/// - GitHub: `github_get_pr`, `github_create_comment`
///
/// URL shapes and headers mirror the async [JiraHttpClient] /
/// [GithubHttpClient] transports (`/rest/api/latest`, `X-Atlassian-Token`,
/// Bearer auth, …) so both paths hit the same endpoints.
library;

import 'dart:convert';

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import '../integrations/jira/jira_utils.dart';
import 'sync_http_client.dart';

/// Connection config for a sync integration: base URL plus auth headers.
typedef SyncIntegrationConfig = ({String baseUrl, Map<String, String> headers});

/// Executor for a sync tool call: receives resolved [config] and [args].
typedef SyncToolFn = String Function(
  SyncIntegrationConfig,
  Map<String, dynamic>,
);

/// Routes tool calls to integration clients over synchronous HTTP.
class SyncToolDispatcher {
  final PropertyReader _reader;

  /// Creates a dispatcher reading integration config from [reader].
  SyncToolDispatcher(this._reader);

  /// Jira tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _jiraFns = {
    'jira_get_ticket': _jiraGetTicket,
    'jira_post_comment': _jiraPostComment,
    'jira_search_by_jql': _jiraSearchByJql,
    'jira_add_label': _jiraAddLabel,
    'jira_remove_label': _jiraRemoveLabel,
    'jira_move_to_status': _jiraMoveToStatus,
  };

  /// GitHub tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _githubFns = {
    'github_get_pr': _githubGetPr,
    'github_create_comment': _githubCreateComment,
  };

  /// Executes a tool call. Returns a JSON result string, or `null` when no
  /// integration matches the tool name (caller falls back to an error).
  String? execute(String toolName, Map<String, dynamic> args) {
    if (toolName.startsWith('jira_')) {
      return _dispatch(toolName, args, _jiraFns, _jiraConfig, 'Jira');
    }
    if (toolName.startsWith('github_')) {
      return _dispatch(toolName, args, _githubFns, _githubConfig, 'GitHub');
    }
    return null;
  }

  /// Resolves [toolName] against [fns], checks config, then dispatches.
  String _dispatch(
    String toolName,
    Map<String, dynamic> args,
    Map<String, SyncToolFn> fns,
    SyncIntegrationConfig? Function() configFn,
    String integration,
  ) {
    final fn = fns[toolName];
    if (fn == null) return _err('Unsupported $integration tool: $toolName');
    final config = configFn();
    if (config == null) return _err('$integration not configured');
    return fn(config, args);
  }

  // ── Config builders ─────────────────────────────────────────────────────

  /// Builds Jira config, or `null` when base path / auth is missing.
  SyncIntegrationConfig? _jiraConfig() {
    final basePath = _reader.getJiraBasePath();
    if (basePath == null || basePath.isEmpty) return null;
    final token = _reader.getJiraLoginPassToken();
    if (token == null || token.isEmpty) return null;
    final authType = _reader.getJiraAuthType() ?? 'Basic';
    return (
      baseUrl: '$basePath/rest/api/latest',
      headers: {
        'Authorization': '$authType $token',
        'X-Atlassian-Token': 'nocheck',
        'Content-Type': 'application/json',
      },
    );
  }

  /// Builds GitHub config, or `null` when the token is missing.
  SyncIntegrationConfig? _githubConfig() {
    final token = _reader.getGithubToken();
    if (token == null || token.isEmpty) return null;
    return (
      baseUrl: _reader.getGithubBasePath(),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      },
    );
  }

  // ── Jira tools ──────────────────────────────────────────────────────────

  /// `jira_get_ticket` — GET `issue/{key}?fields={fields}`.
  String _jiraGetTicket(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    final url = '${config.baseUrl}/issue/${_asStr(args['key'])}'
        '?fields=${Uri.encodeQueryComponent(_joinFields(args['fields']))}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `jira_post_comment` — POST `issue/{key}/comment`.
  String _jiraPostComment(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final body = jsonEncode({'body': _asStr(args['comment'])});
    final url = '${config.baseUrl}/issue/${_asStr(args['key'])}/comment';
    return _postBody(config, url, body);
  }

  /// `jira_search_by_jql` — GET `search/jql?jql={jql}&fields={fields}`.
  ///
  /// Single page (no cursor pagination); the first page covers the common
  /// agent-script case of scanning a bounded result set.
  String _jiraSearchByJql(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final url = '${config.baseUrl}/search/jql'
        '?jql=${Uri.encodeQueryComponent(_asStr(args['jql']))}'
        '&fields=${Uri.encodeQueryComponent(_joinFields(args['fields']))}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `jira_add_label` — fetches labels, appends, PUTs the full set.
  String _jiraAddLabel(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    final key = _asStr(args['key']);
    final labels = _fetchLabels(config, key);
    final label = _asStr(args['label']);
    if (!labels.contains(label)) labels.add(label);
    return _putLabels(config, key, labels);
  }

  /// `jira_remove_label` — fetches labels, removes, PUTs the full set.
  String _jiraRemoveLabel(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final key = _asStr(args['key']);
    final labels = _fetchLabels(config, key)..remove(_asStr(args['label']));
    return _putLabels(config, key, labels);
  }

  /// `jira_move_to_status` — finds the transition, then POSTs it.
  String _jiraMoveToStatus(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final key = _asStr(args['key']);
    final status = _asStr(args['status']);
    final transitions = _fetchTransitions(config, key);
    final id = matchTransitionId(transitions, status);
    if (id == null) return _err('No transition found for status: $status');
    return _postBody(
        config,
        '${config.baseUrl}/issue/$key/transitions',
        jsonEncode({
          'transition': {'id': id},
        }));
  }

  /// Fetches the current labels list for [key]; empty list on failure.
  List<String> _fetchLabels(SyncIntegrationConfig config, String key) {
    final decoded =
        _getJson(config, '${config.baseUrl}/issue/$key?fields=labels');
    if (decoded == null) return [];
    final fields = decoded['fields'] as Map<String, dynamic>? ?? {};
    return List<String>.from(fields['labels'] as List? ?? []);
  }

  /// PUTs the full labels set via `update.labels[].set`.
  String _putLabels(
      SyncIntegrationConfig config, String key, List<String> labels) {
    final body = jsonEncode({
      'update': {
        'labels': [
          {'set': labels},
        ],
      },
    });
    return _putBody(config, '${config.baseUrl}/issue/$key', body);
  }

  /// Fetches the transitions list for [key]; empty list on failure.
  List<Map<String, dynamic>> _fetchTransitions(
    SyncIntegrationConfig config,
    String key,
  ) {
    final decoded =
        _getJson(config, '${config.baseUrl}/issue/$key/transitions');
    if (decoded == null) return [];
    final list = decoded['transitions'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ── GitHub tools ────────────────────────────────────────────────────────

  /// `github_get_pr` — GET `repos/{owner}/{repo}/pulls/{number}`.
  String _githubGetPr(SyncIntegrationConfig config, Map<String, dynamic> args) {
    final url = '${config.baseUrl}/repos/${_asStr(args['owner'])}'
        '/${_asStr(args['repo'])}/pulls/${_asInt(args['number'])}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `github_create_comment` — POST `repos/{o}/{r}/issues/{n}/comments`.
  String _githubCreateComment(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final url = '${config.baseUrl}/repos/${_asStr(args['owner'])}'
        '/${_asStr(args['repo'])}/issues/${_asInt(args['number'])}/comments';
    return _postBody(config, url, jsonEncode({'body': _asStr(args['body'])}));
  }

  // ── Shared HTTP helpers ─────────────────────────────────────────────────

  /// GETs a JSON object, returning `null` on failure or non-object body.
  Map<String, dynamic>? _getJson(SyncIntegrationConfig config, String url) {
    final resp = SyncHttpClient.get(url, headers: config.headers);
    if (!resp.isOk) return null;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // fall through
    }
    return null;
  }

  /// POSTs [body] to [url] and returns the result string.
  String _postBody(SyncIntegrationConfig config, String url, String body) =>
      _bodyOrError(
          SyncHttpClient.post(url, headers: config.headers, body: body));

  /// PUTs [body] to [url] and returns the result string.
  String _putBody(SyncIntegrationConfig config, String url, String body) =>
      _bodyOrError(
          SyncHttpClient.put(url, headers: config.headers, body: body));

  /// Returns the response body, or an error JSON when curl failed.
  String _bodyOrError(SyncHttpResponse resp) {
    if (resp.statusCode == 0) return _err('HTTP request failed: ${resp.body}');
    return resp.body;
  }

  /// Joins a `fields` argument (list or comma string) into a query value.
  ///
  /// Defaults to `*navigable` (the Java `JiraClient` default).
  String _joinFields(dynamic fields) {
    if (fields == null) return '*navigable';
    if (fields is String) return fields;
    if (fields is List) return fields.cast<String>().join(',');
    return '*navigable';
  }

  /// Coerces a loosely-typed JS argument to a string.
  String _asStr(dynamic value) => value?.toString() ?? '';

  /// Coerces a loosely-typed JS argument to an int.
  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Encodes a JSON error result string.
  String _err(String message) => jsonEncode({'error': message});
}
