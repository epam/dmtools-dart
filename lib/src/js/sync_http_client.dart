/// Synchronous HTTP client for the JS tool bridge.
///
/// Primary transport is [SyncHttpBridge] — a pooled async `HttpClient` in a
/// worker isolate, served synchronously over native mailboxes (Java-bridge
/// performance profile: TLS handshake once, then connection reuse). Until
/// the bridge has booted (it must complete while the event loop is alive;
/// the CLI awaits it at startup), requests fall back to the curl subprocess
/// transport below.
///
/// Security/robustness properties of the curl fallback:
/// - Every request carries `--connect-timeout`/`--max-time` so a hung
///   endpoint cannot freeze the isolate inside a QuickJS callback forever.
/// - Headers and bodies travel in 0700-mode temp files (`-H @file`,
///   `--data-binary @file`), never in the process argument list — auth
///   tokens stay invisible to `ps` and large payloads cannot hit the OS
///   argv size limit (`E2BIG`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_http_bridge.dart';

/// Response from a sync HTTP request.
class SyncHttpResponse {
  /// The HTTP status code (`0` when the transport failed).
  final int statusCode;

  /// The response body text (UTF-8 decoded).
  final String body;

  /// Creates a response with [statusCode] and [body].
  const SyncHttpResponse(this.statusCode, this.body);

  /// Whether the request succeeded (2xx status code).
  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// Synchronous HTTP client: pooled-isolate transport with a curl fallback.
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
      _dispatch('GET', url, headers: headers);

  /// Performs a synchronous POST request.
  static SyncHttpResponse post(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) =>
      _dispatch('POST', url, headers: headers, body: body);

  /// Performs a synchronous PUT request.
  static SyncHttpResponse put(
    String url, {
    Map<String, String>? headers,
    String? body,
  }) =>
      _dispatch('PUT', url, headers: headers, body: body);

  /// Performs a synchronous DELETE request.
  static SyncHttpResponse delete(String url, {Map<String, String>? headers}) =>
      _dispatch('DELETE', url, headers: headers);

  /// Routes a request through the pooled-isolate bridge when booted, the
  /// curl subprocess otherwise. The fallback also kicks [SyncHttpBridge.boot]
  /// so later requests (after any event-loop turn) use the pool.
  static SyncHttpResponse _dispatch(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) {
    final bridge = SyncHttpBridge.shared;
    if (!bridge.ready) {
      unawaited(bridge.boot());
      return _curlRequest(method, url, headers: headers, body: body);
    }
    return bridge.request(method, url, headers: headers, body: body);
  }

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

  /// Curl fallback transport: stages headers/body in a 0700 temp dir and
  /// spawns curl (`Process.runSync`) — used before the isolate bridge has
  /// booted, and kept as the reference transport for the staged-binary
  /// helpers in `sync_request_helpers.dart`.
  static SyncHttpResponse _curlRequest(
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
