/// Synchronous HTTP client using curl subprocess.
///
/// Used by the JS tool bridge for making blocking HTTP calls within
/// [NativeCallable] callbacks, where Dart's event loop is not running and
/// async [Future]s (e.g. dio requests) can never complete. Each call spawns a
/// curl process (~10-50ms overhead) — acceptable for agent scripts making
/// tool calls.
///
/// Security/robustness properties:
/// - Every request carries `--connect-timeout`/`--max-time` so a hung
///   endpoint cannot freeze the isolate inside a QuickJS callback forever.
/// - Headers and bodies travel in 0700-mode temp files (`-H @file`,
///   `--data-binary @file`), never in the process argument list — auth
///   tokens stay invisible to `ps` and large payloads cannot hit the OS
///   argv size limit (`E2BIG`).
library;

import 'dart:convert';
import 'dart:io';

/// Response from a sync HTTP request.
class SyncHttpResponse {
  /// The HTTP status code (`0` when curl failed to obtain a response).
  final int statusCode;

  /// The response body text (UTF-8 decoded).
  final String body;

  /// Creates a response with [statusCode] and [body].
  const SyncHttpResponse(this.statusCode, this.body);

  /// Whether the request succeeded (2xx status code).
  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// Synchronous HTTP client backed by `curl` subprocess calls.
class SyncHttpClient {
  /// curl exit code for `--max-time` / `--connect-timeout` expiry.
  static const _curlExitTimedOut = 28;

  /// Connect-phase budget in seconds (mirrors the 10s reviewer ask; Java
  /// `JiraClient` allows 60s, but a hung TCP connect is worthless inside a
  /// frozen event loop, so the sync path fails fast).
  static const connectTimeoutSeconds = 10;

  /// Total request budget in seconds (connect + transfer), matching the Java
  /// client's 60s read timeout.
  static const maxTimeSeconds = 60;

  /// Performs a synchronous GET request.
  static SyncHttpResponse get(String url, {Map<String, String>? headers}) =>
      _request('GET', url, headers: headers);

  /// Performs a synchronous POST request.
  static SyncHttpResponse post(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) =>
      _request('POST', url, headers: headers, body: body);

  /// Performs a synchronous PUT request.
  static SyncHttpResponse put(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) =>
      _request('PUT', url, headers: headers, body: body);

  /// Performs a synchronous DELETE request.
  static SyncHttpResponse delete(String url, {Map<String, String>? headers}) =>
      _request('DELETE', url, headers: headers);

  /// Builds the curl argument list for a request.
  ///
  /// Exposed for unit testing so the argument construction (method, URL,
  /// timeouts, file references) can be verified without spawning curl.
  /// Headers and the body are referenced by file path only — see the
  /// library docs.
  static List<String> buildArgs(
    String method,
    String url, {
    String? headerFile,
    String? bodyFile,
  }) {
    final args = [
      '-s',
      '-X',
      method,
      '-w',
      '\n%{http_code}',
      '--connect-timeout',
      '$connectTimeoutSeconds',
      '--max-time',
      '$maxTimeSeconds',
    ];
    if (headerFile != null) args.addAll(['-H', '@$headerFile']);
    if (bodyFile != null) args.addAll(['--data-binary', '@$bodyFile']);
    args.add(url);
    return args;
  }

  /// Renders a header map as a `-H @file` payload (one `Key: Value` line
  /// per header).
  static String renderHeaderFile(Map<String, String>? headers) =>
      (headers ?? const <String, String>{})
          .entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');

  /// Parses a curl [ProcessResult] into a [SyncHttpResponse].
  ///
  /// The `-w '\n%{http_code}'` flag appends the status code as the final line
  /// of stdout. When curl fails to connect (status code `000`), stderr is
  /// returned as the body for diagnostics; curl exit 28 (timeout expiry) is
  /// surfaced as a distinct timeout error.
  static SyncHttpResponse parseResponse(ProcessResult result) {
    if (result.exitCode == _curlExitTimedOut) {
      return SyncHttpResponse(
        0,
        'Request timed out after ${maxTimeSeconds}s (--max-time)',
      );
    }
    final output = result.stdout as String;
    final lines = output.split('\n');
    final statusCode = int.tryParse(lines.removeLast().trim()) ?? 0;
    final responseBody = lines.join('\n');
    if (statusCode == 0) {
      final stderr = result.stderr as String;
      final diag = stderr.isEmpty ? responseBody : stderr;
      if (result.exitCode != 0) {
        return SyncHttpResponse(0, 'curl exit ${result.exitCode}: $diag');
      }
      return SyncHttpResponse(0, diag);
    }
    return SyncHttpResponse(statusCode, responseBody);
  }

  /// Runs curl for a request, staging headers/body in a 0700 temp dir.
  static SyncHttpResponse _request(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) {
    final dir = Directory.systemTemp.createTempSync('dmtools_sync_');
    try {
      String? headerFile;
      if (headers != null && headers.isNotEmpty) {
        headerFile = _stageFile(dir, 'headers', renderHeaderFile(headers));
      }
      String? bodyFile;
      if (body != null) {
        bodyFile = _stageFile(dir, 'body', body);
      }
      final args = buildArgs(
        method,
        url,
        headerFile: headerFile,
        bodyFile: bodyFile,
      );
      final result = Process.runSync('curl', args, stdoutEncoding: utf8);
      return parseResponse(result);
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  /// Writes [content] to a file inside the private temp [dir].
  static String _stageFile(Directory dir, String name, String content) {
    final file = File('${dir.path}/$name');
    file.writeAsStringSync(content, flush: true);
    return file.path;
  }
}
