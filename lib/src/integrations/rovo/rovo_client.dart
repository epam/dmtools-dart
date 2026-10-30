/// High-level Atlassian Rovo MCP client — ports the Java `RovoMcpClient`
/// `@MCPTool` catalog (`rovo_search`, `rovo_summarize`, `rovo_context`,
/// `rovo_ask`).
///
/// Sends JSON-RPC 2.0 `tools/call` requests over HTTP POST to Atlassian's
/// remote MCP server (`https://mcp.atlassian.com/v2/mcp`).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'rovo_http_client.dart';

/// Exception thrown when the Rovo MCP endpoint returns an HTTP 403 or
/// indicates that Agentic search is not enabled for the user or site.
class RovoForbiddenException implements Exception {
  /// Description of the forbidden / unsupported agentic search error.
  final String message;

  /// Creates a [RovoForbiddenException] with [message].
  const RovoForbiddenException(this.message);

  @override
  String toString() => 'RovoForbiddenException: $message';
}

/// Atlassian Rovo MCP methods exposed to the MCP tool runtime.
class RovoClient {
  /// Remote MCP tool name for semantic and agentic search.
  static const String remoteToolSearch = 'search';

  /// Remote MCP tool name for Confluence page retrieval and AI summary.
  static const String remoteToolConfluenceContent = 'getConfluenceContent';

  /// Remote MCP tool name for cross-product graph context.
  static const String remoteToolGraphContext = 'getGraphContext';

  /// Standard semantic search mode.
  static const String modeStandard = 'STANDARD';

  /// Agentic search mode with cited answers.
  static const String modeAgentic = 'AGENTIC';

  /// Detail level requesting an AI-generated summary of a Confluence page.
  static const String detailAiSummary = 'ai_summary';

  final RovoHttpClient _http;
  int _requestId = 0;

  /// Creates a client backed by [_http].
  RovoClient(this._http);

  /// `rovo_search` — semantic natural-language search in `STANDARD` mode.
  Future<String> rovoSearch({
    required String query,
    String? cloudId,
    String? targetApp,
    int? limit,
  }) {
    _requireNonBlank(query, 'query');
    final args = <String, dynamic>{
      'query': query.trim(),
      'mode': modeStandard,
    };
    _putCloudIdIfPresent(args, cloudId);
    if (!_isBlank(targetApp)) args['targetApp'] = targetApp!.trim();
    if (limit != null && limit > 0) args['limit'] = limit;
    return callRemoteTool(remoteToolSearch, args);
  }

  /// `rovo_summarize` — calls `getConfluenceContent` with `detail=ai_summary`.
  Future<String> rovoSummarize({
    required String contentId,
    String? cloudId,
  }) {
    _requireNonBlank(contentId, 'contentId');
    final args = <String, dynamic>{
      'contentId': contentId.trim(),
      'detail': detailAiSummary,
    };
    _putCloudIdIfPresent(args, cloudId);
    return callRemoteTool(remoteToolConfluenceContent, args);
  }

  /// `rovo_context` — calls `getGraphContext` for an Atlassian object.
  Future<String> rovoContext({
    required String objectType,
    required String identifier,
    String? cloudId,
  }) {
    _requireNonBlank(objectType, 'objectType');
    _requireNonBlank(identifier, 'identifier');
    final args = <String, dynamic>{
      'objectType': objectType.trim(),
      'identifier': identifier.trim(),
    };
    _putCloudIdIfPresent(args, cloudId);
    return callRemoteTool(remoteToolGraphContext, args);
  }

  /// `rovo_ask` — calls `search` in `AGENTIC` mode, falling back to
  /// `STANDARD` search when Agentic search returns 403 or is not enabled.
  Future<String> rovoAsk({
    required String question,
    String? cloudId,
  }) async {
    _requireNonBlank(question, 'question');
    final args = <String, dynamic>{
      'query': question.trim(),
      'mode': modeAgentic,
    };
    _putCloudIdIfPresent(args, cloudId);
    try {
      return await callRemoteTool(remoteToolSearch, args);
    } on RovoForbiddenException {
      return rovoSearch(query: question, cloudId: cloudId);
    } on DioException catch (e) {
      if (_isForbiddenDioError(e)) {
        return rovoSearch(query: question, cloudId: cloudId);
      }
      rethrow;
    }
  }

  /// Sends a JSON-RPC 2.0 `tools/call` request for [toolName] with [arguments].
  Future<String> callRemoteTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final payload = buildJsonRpcRequest(
      id: ++_requestId,
      toolName: toolName,
      arguments: arguments,
    );
    final rawResponse = await _http.post('', body: jsonEncode(payload));
    return unwrapJsonRpcResponse(rawResponse);
  }

  /// Builds a JSON-RPC 2.0 `tools/call` request envelope.
  static Map<String, dynamic> buildJsonRpcRequest({
    required int id,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) =>
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'method': 'tools/call',
        'params': <String, dynamic>{
          'name': toolName,
          'arguments': arguments,
        },
      };

  /// Unwraps a JSON-RPC 2.0 or SSE `data:` response from the Rovo MCP server.
  ///
  /// Throws [RovoForbiddenException] if the JSON-RPC error or tool result
  /// indicates HTTP 403 or that Agentic search is not enabled.
  static String unwrapJsonRpcResponse(String rawResponse) {
    final trimmed = _extractJsonPayload(rawResponse);
    if (!trimmed.startsWith('{')) return rawResponse;
    final envelope = _tryDecodeObject(trimmed);
    if (envelope == null) return rawResponse;
    final error = envelope['error'];
    if (error != null) _throwForJsonRpcError(error);
    final result = envelope['result'];
    return result is Map<String, dynamic>
        ? _unwrapResultMap(result)
        : (result != null ? jsonEncode(result) : rawResponse);
  }

  static Map<String, dynamic>? _tryDecodeObject(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Never _throwForJsonRpcError(Object error) {
    final errorStr = error is String ? error : jsonEncode(error);
    final map =
        error is Map<String, dynamic> ? error : const <String, dynamic>{};
    final code = map['code'] is int ? map['code'] as int : 0;
    final message = (map['message'] as String?) ?? errorStr;
    if (code == 403 || isAgenticNotEnabledMessage(errorStr)) {
      throw RovoForbiddenException(message);
    }
    throw StateError('Rovo MCP JSON-RPC error ($code): $message');
  }

  static String _unwrapResultMap(Map<String, dynamic> result) {
    final isError = result['isError'] == true;
    final content = result['content'];
    final extracted = content is List ? _extractContentText(content) : '';
    if (isError) {
      final msg = extracted.isNotEmpty ? extracted : jsonEncode(result);
      _throwForToolError(msg);
    }
    return extracted.isNotEmpty ? extracted : jsonEncode(result);
  }

  static Never _throwForToolError(String message) {
    if (isAgenticNotEnabledMessage(message)) {
      throw RovoForbiddenException(message);
    }
    throw StateError('Rovo MCP tool error: $message');
  }

  static String _extractContentText(List<dynamic> content) =>
      content.map(_itemToText).join('\n');

  static String _itemToText(dynamic item) {
    if (item is Map<String, dynamic>) {
      final text = item['text'];
      return text is String ? text : jsonEncode(item);
    }
    return '$item';
  }

  static String _extractJsonPayload(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty || trimmed.startsWith('{')) return trimmed;
    for (final line in trimmed.split(RegExp(r'\r?\n')).reversed) {
      final candidate = _sseDataLine(line.trim());
      if (candidate != null) return candidate;
    }
    return trimmed;
  }

  static String? _sseDataLine(String line) {
    if (!line.startsWith('data:')) return null;
    final candidate = line.substring('data:'.length).trim();
    return candidate.startsWith('{') ? candidate : null;
  }

  /// Checks whether [text] indicates HTTP 403 or disabled Agentic search.
  static bool isAgenticNotEnabledMessage(String? text) {
    if (text == null || text.isEmpty) return false;
    final lower = text.toLowerCase();
    return lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('agentic search is not enabled');
  }

  static bool _isForbiddenDioError(DioException e) =>
      e.response?.statusCode == 403 ||
      isAgenticNotEnabledMessage(e.response?.data?.toString()) ||
      isAgenticNotEnabledMessage(e.message);

  void _putCloudIdIfPresent(Map<String, dynamic> args, String? cloudId) {
    final resolved =
        !_isBlank(cloudId) ? cloudId!.trim() : _http.defaultCloudId;
    if (resolved != null && resolved.trim().isNotEmpty) {
      args['cloudId'] = resolved.trim();
    }
  }

  static void _requireNonBlank(String value, String name) {
    if (_isBlank(value)) throw ArgumentError('$name must not be blank');
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
