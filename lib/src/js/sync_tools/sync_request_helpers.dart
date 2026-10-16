/// Shared request/parse helpers for the sync tool executors.
///
/// Every `*_sync_tools.dart` executor talks to its API through
/// [SyncHttpClient] (curl subprocess) and coerces loosely-typed JS tool
/// arguments; these helpers hold the parts that are identical across
/// integrations so each executor file carries only its
/// integration-specific logic.
library;

import 'dart:convert';
import 'dart:io';

import '../sync_http_client.dart';

/// Media type for JSON request/response bodies.
const syncJsonContentType = 'application/json';

/// Coerces a loosely-typed JS argument to a string.
String syncAsStr(dynamic value) => value?.toString() ?? '';

/// Coerces a loosely-typed JS argument to an int (`0` when unparseable).
int syncAsInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Whether [value] is `null` or whitespace-only.
bool syncIsBlank(dynamic value) => syncAsStr(value).trim().isEmpty;

/// Decodes [body] as JSON, returning it verbatim when it does not parse.
dynamic syncTryDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return body;
  }
}

/// Returns the response body, or a JSON error when curl itself failed.
String syncBodyOrError(SyncHttpResponse resp) {
  if (resp.statusCode == 0) {
    return syncErr('HTTP request failed: ${resp.body}');
  }
  return resp.body;
}

/// POSTs [body] to [url] and returns the result string.
String syncPostJson(Map<String, String> headers, String url, String body) =>
    syncBodyOrError(SyncHttpClient.post(url, headers: headers, body: body));

/// Runs one curl request with headers (and optional body/output files)
/// staged in a private temp dir.
///
/// Covers the shapes [SyncHttpClient] does not expose: binary
/// `--data-binary @file` uploads, `-F` multipart uploads, and `-o` file
/// downloads — with the same timeouts and header-file hygiene as the
/// shared client.
SyncHttpResponse syncCurlStaged(
  String method,
  String url, {
  required Map<String, String> headers,
  String? dataBinaryFile,
  String? multipartFile,
  String? outputFile,
}) {
  final dir = Directory.systemTemp.createTempSync('dmtools_sync_curl_');
  try {
    final headerFile = File('${dir.path}/headers')
      ..writeAsStringSync(SyncHttpClient.renderHeaderFile(headers),
          flush: true);
    final args = [
      '-s',
      '-X',
      method,
      '-w',
      '\n%{http_code}',
      '--connect-timeout',
      '${SyncHttpClient.connectTimeoutSeconds}',
      '--max-time',
      '${SyncHttpClient.maxTimeSeconds}',
      '-H',
      '@${headerFile.path}',
      if (dataBinaryFile != null) ...['--data-binary', '@$dataBinaryFile'],
      if (multipartFile != null) ...['-F', 'file=@$multipartFile'],
      if (outputFile != null) ...['-o', outputFile],
      url,
    ];
    return SyncHttpClient.parseResponse(
      Process.runSync('curl', args, stdoutEncoding: utf8),
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Encodes a JSON error result string.
String syncErr(String message) => jsonEncode({'error': message});

/// Runs [fetch] with a resolved sync config, or reports [notConfigured]
/// when the integration's config is incomplete.
String syncWithConfig<T>(
  T? config,
  String notConfigured,
  String Function(T config) fetch,
) {
  if (config == null) return syncErr(notConfigured);
  return fetch(config);
}
