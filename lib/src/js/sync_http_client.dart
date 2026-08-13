/// Synchronous HTTP client using curl subprocess.
///
/// Used by the JS tool bridge for making blocking HTTP calls within
/// [NativeCallable] callbacks, where Dart's event loop is not running and
/// async [Future]s (e.g. dio requests) can never complete. Each call spawns a
/// curl process (~10-50ms overhead) — acceptable for agent scripts making
/// tool calls.
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
  /// headers, body) can be verified without spawning curl.
  static List<String> buildArgs(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) {
    final args = ['-s', '-X', method, '-w', '\n%{http_code}'];
    headers?.forEach((k, v) {
      args.addAll(['-H', '$k: $v']);
    });
    if (body != null) {
      args.addAll(['-d', body]);
    }
    args.add(url);
    return args;
  }

  /// Parses a curl [ProcessResult] into a [SyncHttpResponse].
  ///
  /// The `-w '\n%{http_code}'` flag appends the status code as the final line
  /// of stdout. When curl fails to connect (status code `000`), stderr is
  /// returned as the body for diagnostics.
  static SyncHttpResponse parseResponse(ProcessResult result) {
    final output = result.stdout as String;
    final lines = output.split('\n');
    final statusCode = int.tryParse(lines.removeLast().trim()) ?? 0;
    final responseBody = lines.join('\n');
    if (statusCode == 0) {
      final stderr = result.stderr as String;
      return SyncHttpResponse(0, stderr.isEmpty ? responseBody : stderr);
    }
    return SyncHttpResponse(statusCode, responseBody);
  }

  static SyncHttpResponse _request(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) {
    final args = buildArgs(method, url, headers: headers, body: body);
    final result = Process.runSync('curl', args, stdoutEncoding: utf8);
    return parseResponse(result);
  }
}
