part of 'jira_sync_tools.dart';

/// Connection config for the sync Jira executors.
typedef _JiraSyncConfig = ({
  String basePath,
  String baseUrl,
  Map<String, String> headers
});

/// Media type for JSON request/response bodies.
const _jsonContentType = 'application/json';

/// Decodes [body] as JSON, returning it verbatim when it does not parse.
dynamic _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return body;
  }
}

/// Unwraps the message inside a `{"error": …}` envelope.
String _errorOf(String errorEnvelope) =>
    _asStr((_tryDecode(errorEnvelope) as Map?)?['error']);

/// GETs a JSON object, returning `null` on failure or non-object body.
Map<String, dynamic>? _getJson(_JiraSyncConfig config, String url) {
  final result = _getJsonOrError(url, config);
  return result is Map<String, dynamic> ? result : null;
}

/// GET for callers that must distinguish transport failure from an empty
/// result: the decoded map, or an error [String] (status / malformed body).
Object _getJsonOrError(String url, _JiraSyncConfig config) {
  final resp = SyncHttpClient.get(url, headers: config.headers);
  if (!resp.isOk) {
    final decoded = _tryDecode(resp.body);
    final detail = decoded is Map ? _asStr(decoded['error']) : '';
    return 'fetch failed: HTTP ${resp.statusCode}'
        '${detail.isEmpty ? '' : ': $detail'}';
  }
  try {
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {/* fall through to the malformed-body error */}
  return 'fetch failed: malformed JSON response';
}

/// POSTs [body] to [url] and returns the result string.
String _postBody(_JiraSyncConfig config, String url, String body) =>
    _bodyOrError(
      SyncHttpClient.post(url, headers: config.headers, body: body),
    );

/// PUTs [body] to [url] and returns the result string.
String _putBody(_JiraSyncConfig config, String url, String body) =>
    _bodyOrError(
      SyncHttpClient.put(url, headers: config.headers, body: body),
    );

/// Returns the 2xx body verbatim, or the body re-encoded as a JSON string
/// when it is not valid JSON.
///
/// Java parity (`GenericRequest.execute`): a 2xx body that is empty (204
/// No Content) or plain text reaches the JS layer as the raw string —
/// `""` for 204, the text otherwise. Re-encoding non-JSON bodies keeps
/// the QuickJS JSON boundary yielding that same JS string. Failures
/// (curl exit, non-2xx status) become `{"error": …}`.
String _bodyOrError(SyncHttpResponse resp) {
  if (resp.statusCode == 0) return _err('HTTP request failed: ${resp.body}');
  if (!resp.isOk) return _err(_failureDetail('HTTP ${resp.statusCode}', resp));
  if (_tryDecode(resp.body) == resp.body) return jsonEncode(resp.body);
  return resp.body;
}

/// Formats a failure message with a short body snippet.
String _failureDetail(String reason, SyncHttpResponse resp) {
  final snippet =
      resp.body.length > 120 ? resp.body.substring(0, 120) : resp.body;
  return '$reason: $snippet';
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

/// Encodes a JSON error result string.
String _err(String message) => jsonEncode({'error': message});
