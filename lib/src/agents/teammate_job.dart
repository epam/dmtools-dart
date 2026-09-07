/// Teammate job — Dart port of Java `Teammate` (`teammate/Teammate.java`),
/// ticket-driven mode only: the job selects tickets by `inputJql`, prepares
/// the `input/<ticketKey>/` context folder, and delegates each ticket to
/// [CliAgent] under the hood.
///
/// Scope note (port decision): Java Teammate's internal AI-processing branch
/// (`ContextOrchestrator` + `RequestDecompositionAgent` + LLM providers) is
/// intentionally not ported — the dmtools-agents Teammate configs run with
/// `skipAIProcessing: true` and let the CLI agent do the AI work via
/// `cliCommands`. Everything the configs actually use is ported:
/// ticket selection, the CI-run trace comment, and the full CliAgent
/// lifecycle (preJSAction → input folder → preCliJSAction → cliCommands →
/// postJSAction → reset).
library;

import '../config/property_reader.dart';
import '../js/job_runner.dart';
import '../js/sync_tool_dispatcher.dart';
import 'dart:convert';

import 'cli_agent.dart';
import 'cli_agent_params.dart';

/// Fetches the hydrated tickets for [inputJql]: each ticket is a raw tracker
/// JSON map with at least `key` and `fields` (comments included).
typedef TeammateTicketSource = Future<List<Map<String, dynamic>>> Function(
    String inputJql);

/// Posts a trace/status comment to [key] (Jira comment parity).
typedef TeammateCommentPoster = Future<void> Function(String key, String body);

/// Ticket-driven Teammate job.
///
/// Runs one [CliAgent] per ticket resolved from `params.inputJql`:
/// - empty/missing `inputJql` → no-op success (Java: "skipping ticket
///   processing");
/// - each ticket becomes the [CliAgentParams] context id, so the input
///   folder is `input/<ticketKey>/`;
/// - `ciRunUrl` + enabled comments post the Java trace comment
///   (`[<agentId>] Processing started. CI Run: <url>`).
class TeammateJob {
  /// Creates the job from the raw `params` block of a Teammate config.
  ///
  /// - [ticketSource] — ticket lookup; defaults to the Jira sync tools
  ///   (search → get_ticket → get_comments hydration).
  /// - [commentPoster] — comment sink for the CI-run trace comment; defaults
  ///   to `jira_post_comment`.
  TeammateJob({
    required this.params,
    this.workingDirectory,
    this.ticketSource,
    this.commentPoster,
    this.propertyReader,
    this.jsRunner,
  });

  /// Raw params from the job config (the `params` block).
  final Map<String, dynamic> params;

  /// Working-directory override forwarded to each [CliAgent].
  final String? workingDirectory;

  /// Ticket lookup override (tests inject fakes; default: Jira sync tools).
  final TeammateTicketSource? ticketSource;

  /// Comment sink override (tests inject fakes; default: `jira_post_comment`).
  final TeammateCommentPoster? commentPoster;

  /// Property reader forwarded to each [CliAgent].
  final PropertyReader? propertyReader;

  /// JS runner forwarded to each [CliAgent].
  final JsJobRunner? jsRunner;

  /// Runs the job and returns `{'success': …, 'results': […]}` where each
  /// result item carries `ticket`, plus the [CliAgent] result fields.
  Future<Map<String, dynamic>> run() async {
    final inputJql = (params['inputJql'] as String?)?.trim() ?? '';
    if (inputJql.isEmpty) {
      // Java Teammate: "No TrackerClient … and no inputJql provided —
      // skipping ticket processing" → empty result list.
      return const {'success': true, 'results': []};
    }
    final source = ticketSource ?? jiraTicketSource;
    final tickets = await source(inputJql);
    final results = <Map<String, dynamic>>[];
    for (final ticket in tickets) {
      final key = _ticketKey(ticket);
      if (key == null || key.isEmpty) {
        results.add({
          'ticket': null,
          'success': false,
          'error': 'search result without a ticket key',
        });
        continue;
      }
      await _postTraceComment(key);
      final agent = CliAgent(
        params: _paramsForTicket(key),
        workingDirectory: workingDirectory,
        ticketData: ticket,
        propertyReader: propertyReader,
        jsRunner: jsRunner,
      );
      final result = await agent.run();
      results.add(
          {'ticket': key, 'success': result['success'] == true, ...result});
    }
    final ok = results.isNotEmpty && results.every((r) => r['success'] == true);
    return {'success': ok, 'results': results};
  }

  /// Per-ticket [CliAgentParams]: the shared config with `metadata.contextId`
  /// pinned to the ticket key (Java Teammate's input folder is
  /// `input/<ticketKey>/`).
  CliAgentParams _paramsForTicket(String key) {
    final p = CliAgentParams.fromJson(params);
    p.metadata = {...?p.metadata, 'contextId': key};
    return p;
  }

  /// Posts the CI-run trace comment when `ciRunUrl` is set and comments are
  /// enabled (`alwaysPostComments` or non-`none` `outputType`).
  Future<void> _postTraceComment(String key) async {
    final ciRunUrl = (params['ciRunUrl'] as String?)?.trim() ?? '';
    if (ciRunUrl.isEmpty || !_shouldPostComments) return;
    final poster = commentPoster ?? _jiraCommentPoster;
    await poster(
        key,
        '${_agentNamePrefix()}'
        'Processing started. CI Run: $ciRunUrl');
  }

  /// Java `AbstractJob.shouldPostComments`: `alwaysPostComments` wins, else
  /// comments are on when `outputType` is not `none`.
  bool get _shouldPostComments {
    if (params['alwaysPostComments'] == true) return true;
    final outputType = (params['outputType'] as String?)?.trim().toLowerCase();
    return outputType != null && outputType.isNotEmpty && outputType != 'none';
  }

  /// Java `AbstractJob.agentNamePrefix`: `[<contextId>|<agentId>] ` or `''`.
  String _agentNamePrefix() {
    final md = params['metadata'];
    if (md is Map) {
      final contextId = md['contextId'];
      if (contextId is String && contextId.isNotEmpty) return '[$contextId] ';
      final agentId = md['agentId'];
      if (agentId is String && agentId.isNotEmpty) return '[$agentId] ';
    }
    return '';
  }

  /// Extracts the ticket key from a raw search/get result map.
  String? _ticketKey(Map<String, dynamic> ticket) {
    final key = ticket['key'];
    return key is String ? key : null;
  }
}

/// Default [TeammateTicketSource]: Jira sync tools — `jira_search_by_jql`
/// for the keys, then `jira_get_ticket` + `jira_get_comments` hydration so
/// the input folder carries the full ticket text and comments
/// (Java `TicketContext.prepareContext` parity).
Future<List<Map<String, dynamic>>> jiraTicketSource(String inputJql) async {
  final dispatcher = SyncToolDispatcher(PropertyReader());
  final raw = dispatcher.execute('jira_search_by_jql', {
    'jql': inputJql,
    'fields': ['summary', 'status', 'priority', 'labels'],
  });
  final keys = extractTicketKeys(raw);
  return [
    for (final key in keys)
      hydrateTicket(
        rawTicket: dispatcher.execute('jira_get_ticket', {'key': key}),
        rawComments: dispatcher.execute('jira_get_comments', {'key': key}),
        key: key,
      ),
  ];
}

Future<void> _jiraCommentPoster(String key, String body) async {
  final dispatcher = SyncToolDispatcher(PropertyReader());
  dispatcher.execute('jira_post_comment', {'key': key, 'comment': body});
}

/// Merges a raw ticket payload and a raw comments payload into one ticket
/// map whose `fields.comments` carries the comments (the shape
/// `TicketInputContextBuilder` consumes). Falls back to `{'key': key}`
/// when [rawTicket] does not decode.
Map<String, dynamic> hydrateTicket({
  String? rawTicket,
  String? rawComments,
  required String key,
}) {
  final ticket = _decodeMap(rawTicket) ?? {'key': key};
  final comments = decodeCommentsPayload(rawComments);
  if (comments == null && ticket['fields'] is! Map) return ticket;
  final fields = Map<String, dynamic>.from(
    ticket['fields'] as Map<String, dynamic>? ?? const {},
  );
  if (comments != null) fields['comment'] = {'comments': comments};
  ticket['fields'] = fields;
  return ticket;
}

/// Decodes a search-result payload into ticket keys. Accepts both a bare
/// issues array (`[{key, …}, …]`) and the paged map (`{issues: […]}`) —
/// the two shapes Jira search returns across API versions.
List<String> extractTicketKeys(String? raw) {
  final decoded = decodeJsonPayload(raw);
  if (decoded is List) {
    return decoded.map(_mapKey).whereType<String>().toList();
  }
  if (decoded is Map) {
    final issues = decoded['issues'];
    if (issues is List) return issues.map(_mapKey).whereType<String>().toList();
  }
  return const [];
}

/// Returns the `key` of [value] when it is a map with a string key.
String? _mapKey(dynamic value) {
  if (value is Map<String, dynamic>) return value['key'] as String?;
  if (value is Map) return value['key'] as String?;
  return null;
}

/// Decodes a comments payload: either `{comments: […]}` (the raw Jira
/// issue-comment response) or a bare array.
List<dynamic>? decodeCommentsPayload(String? raw) {
  final decoded = decodeJsonPayload(raw);
  if (decoded is Map && decoded['comments'] is List) {
    return decoded['comments'] as List;
  }
  if (decoded is List) return decoded;
  return null;
}

/// Decodes a JSON payload string, returning `null` for empty or malformed
/// input (network bodies are best-effort — Java treats undecodable bodies
/// the same way by failing the search, which the dispatcher surfaces).
dynamic decodeJsonPayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? _decodeMap(String? raw) {
  final decoded = decodeJsonPayload(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return decoded.cast<String, dynamic>();
  return null;
}
