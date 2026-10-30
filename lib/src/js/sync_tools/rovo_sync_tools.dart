/// Synchronous Atlassian Rovo MCP tool executors for the JS tool bridge.
///
/// Public counterpart for the dispatcher: each handler resolves its config
/// from [PropertyReader], performs blocking HTTP via [SyncHttpClient], and
/// returns the JSON-RPC unwrapped result string. Tool names and parameters
/// port the Java `RovoMcpClient` `@MCPTool` methods (`rovo_search`,
/// `rovo_summarize`, `rovo_context`, `rovo_ask`).
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../integrations/rovo/rovo_client.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Resolved Rovo sync configuration: MCP URL, headers, and default cloud ID.
typedef _RovoConf = ({
  String url,
  Map<String, String> headers,
  String? defaultCloudId,
});

/// Atlassian Rovo MCP executors: `rovo_*` tool name → result string.
class RovoSyncTools {
  final PropertyReader _reader;
  final SyncHttpResponse Function(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) _post;
  int _requestId = 0;

  /// Creates Rovo sync tooling reading config from [reader].
  ///
  /// [post] overrides the HTTP POST transport for unit tests; production code
  /// uses [SyncHttpClient.post].
  RovoSyncTools(
    this._reader, {
    SyncHttpResponse Function(
      String url, {
      Map<String, String>? headers,
      String? body,
    })? post,
  }) : _post = post ?? SyncHttpClient.post;

  /// Tool executors keyed by canonical MCP tool name.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'rovo_search': _search,
        'rovo_summarize': _summarize,
        'rovo_context': _context,
        'rovo_ask': _ask,
      };

  /// Dispatches a `rovo_*` tool call, returning a JSON error for unknown tools.
  String dispatch(String toolName, Map<String, dynamic> args) {
    final fn = handlers[toolName];
    if (fn == null) return syncErr('Unsupported Rovo tool: $toolName');
    return fn(args);
  }

  _RovoConf? _config() {
    final token = _reader.getRovoLoginPassToken();
    if (token == null || token.trim().isEmpty) return null;
    final authType = _reader.getRovoAuthType();
    final trimmed = token.trim();
    final lower = trimmed.toLowerCase();
    final authValue =
        (lower.startsWith('basic ') || lower.startsWith('bearer '))
            ? trimmed
            : '$authType $trimmed';
    return (
      url: _reader.getRovoMcpUrl(),
      headers: {
        'Authorization': authValue,
        'Accept': 'application/json, text/event-stream',
        'Content-Type': syncJsonContentType,
      },
      defaultCloudId: _reader.getRovoCloudId(),
    );
  }

  String _search(Map<String, dynamic> args) =>
      syncWithConfig(_config(), 'Rovo not configured', (c) {
        final query = syncAsStr(args['query']).trim();
        if (query.isEmpty) return syncErr('query must not be blank');
        return _executeSearch(c, query, args);
      });

  String _executeSearch(
    _RovoConf c,
    String query,
    Map<String, dynamic> args,
  ) {
    final toolArgs = <String, dynamic>{
      'query': query,
      'mode': RovoClient.modeStandard,
    };
    _putCloudId(toolArgs, syncAsStr(args['cloudId']), c.defaultCloudId);
    final targetApp = syncAsStr(args['targetApp']).trim();
    if (targetApp.isNotEmpty) toolArgs['targetApp'] = targetApp;
    final limit = syncAsInt(args['limit']);
    if (limit > 0) toolArgs['limit'] = limit;
    return _callRemote(c, RovoClient.remoteToolSearch, toolArgs);
  }

  String _summarize(Map<String, dynamic> args) =>
      syncWithConfig(_config(), 'Rovo not configured', (c) {
        final contentId = syncAsStr(args['contentId']).trim();
        if (contentId.isEmpty) return syncErr('contentId must not be blank');
        final toolArgs = <String, dynamic>{
          'contentId': contentId,
          'detail': RovoClient.detailAiSummary,
        };
        _putCloudId(toolArgs, syncAsStr(args['cloudId']), c.defaultCloudId);
        return _callRemote(
          c,
          RovoClient.remoteToolConfluenceContent,
          toolArgs,
        );
      });

  String _context(Map<String, dynamic> args) =>
      syncWithConfig(_config(), 'Rovo not configured', (c) {
        final objectType = syncAsStr(args['objectType']).trim();
        final identifier = syncAsStr(args['identifier']).trim();
        if (objectType.isEmpty) return syncErr('objectType must not be blank');
        if (identifier.isEmpty) return syncErr('identifier must not be blank');
        final toolArgs = <String, dynamic>{
          'objectType': objectType,
          'identifier': identifier,
        };
        _putCloudId(toolArgs, syncAsStr(args['cloudId']), c.defaultCloudId);
        return _callRemote(c, RovoClient.remoteToolGraphContext, toolArgs);
      });

  String _ask(Map<String, dynamic> args) =>
      syncWithConfig(_config(), 'Rovo not configured', (c) {
        final question = syncAsStr(args['question']).trim();
        if (question.isEmpty) return syncErr('question must not be blank');
        final toolArgs = <String, dynamic>{
          'query': question,
          'mode': RovoClient.modeAgentic,
        };
        _putCloudId(toolArgs, syncAsStr(args['cloudId']), c.defaultCloudId);
        try {
          return _callRemote(c, RovoClient.remoteToolSearch, toolArgs);
        } on RovoForbiddenException {
          return _executeSearch(c, question, args);
        }
      });

  String _callRemote(
    _RovoConf c,
    String toolName,
    Map<String, dynamic> toolArgs,
  ) {
    final payload = RovoClient.buildJsonRpcRequest(
      id: ++_requestId,
      toolName: toolName,
      arguments: toolArgs,
    );
    final resp = _post(c.url, headers: c.headers, body: jsonEncode(payload));
    return _unwrapResponse(resp);
  }

  static String _unwrapResponse(SyncHttpResponse resp) {
    if (resp.statusCode == 0) {
      return syncErr('HTTP request failed: ${resp.body}');
    }
    if (resp.statusCode == 403 ||
        RovoClient.isAgenticNotEnabledMessage(resp.body)) {
      throw RovoForbiddenException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    if (!resp.isOk) {
      return syncErr('HTTP ${resp.statusCode}: ${resp.body}');
    }
    return RovoClient.unwrapJsonRpcResponse(resp.body);
  }

  static void _putCloudId(
    Map<String, dynamic> toolArgs,
    String cloudId,
    String? defaultCloudId,
  ) {
    final resolved =
        cloudId.trim().isNotEmpty ? cloudId.trim() : defaultCloudId;
    if (resolved != null && resolved.trim().isNotEmpty) {
      toolArgs['cloudId'] = resolved.trim();
    }
  }
}
