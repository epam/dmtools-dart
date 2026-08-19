import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/sync_http_client.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// Unit tests for [SyncHttpClient].
///
/// `buildArgs` and `parseResponse` are tested in isolation (no network).
/// The live-HTTP group starts a Python echo server subprocess — Dart's
/// [HttpServer] runs on the event loop, which is frozen during
/// `Process.runSync('curl', …)`, so a separate process is required.
void main() {
  _testBuildArgs();
  _testRenderHeaderFile();
  _testParseResponse();
  _testIsOk();
  if (hasPython3()) {
    _testLiveHttp();
  }
}

void _testBuildArgs() {
  group('SyncHttpClient.buildArgs', () {
    test('GET: method, URL last, -w flag present', () {
      final args = SyncHttpClient.buildArgs('GET', 'http://ex.com/api');
      expect(args, containsAll(['-s', '-X', 'GET']));
      expect(args[args.indexOf('-w') + 1], '\n%{http_code}');
      expect(args.last, 'http://ex.com/api');
    });

    test('carries connect and total timeouts', () {
      final args = SyncHttpClient.buildArgs('GET', 'http://ex.com/api');
      expect(args[args.indexOf('--connect-timeout') + 1], '10');
      expect(args[args.indexOf('--max-time') + 1], '60');
    });

    test('body referenced via --data-binary @file, never inline', () {
      final args = SyncHttpClient.buildArgs(
        'POST',
        'http://ex.com',
        bodyFile: '/tmp/body.json',
      );
      expect(args[args.indexOf('--data-binary') + 1], '@/tmp/body.json');
      expect(args, isNot(contains('{"k":"v"}')));
      expect(args[args.indexOf('-X') + 1], 'POST');
    });

    test('headers referenced via -H @file, secrets never inline', () {
      final args = SyncHttpClient.buildArgs(
        'GET',
        'http://ex.com',
        headerFile: '/tmp/headers.txt',
      );
      expect(args[args.indexOf('-H') + 1], '@/tmp/headers.txt');
      expect(args, isNot(contains('Bearer tok')));
    });

    test('URL is always the final argument', () {
      final args = SyncHttpClient.buildArgs(
        'POST',
        'http://ex.com/p',
        headerFile: '/tmp/h',
        bodyFile: '/tmp/b',
      );
      expect(args.last, 'http://ex.com/p');
    });

    test('no header/body files omits -H and --data-binary flags', () {
      final args = SyncHttpClient.buildArgs('DELETE', 'http://ex.com');
      expect(args.contains('-H'), isFalse);
      expect(args.contains('--data-binary'), isFalse);
    });
  });
}

/// [SyncHttpClient.renderHeaderFile] — the `-H @file` payload format.
void _testRenderHeaderFile() {
  test('renderHeaderFile writes one "Key: Value" line per header', () {
    final rendered = SyncHttpClient.renderHeaderFile({
      'Authorization': 'Bearer tok',
      'Accept': 'json',
    });
    expect(rendered, 'Authorization: Bearer tok\nAccept: json');
  });
}

void _testParseResponse() {
  group('SyncHttpClient.parseResponse', () {
    test('extracts status code from trailing line', () {
      final resp = SyncHttpClient.parseResponse(_result('{"ok":true}\n200'));
      expect(resp.statusCode, 200);
      expect(resp.body, '{"ok":true}');
    });

    test('preserves newlines inside response body', () {
      final output = '{"a":1,\n"b":2}\n200';
      final resp = SyncHttpClient.parseResponse(_result(output));
      expect(resp.statusCode, 200);
      expect(resp.body, '{"a":1,\n"b":2}');
    });

    test('empty body with 204', () {
      final resp = SyncHttpClient.parseResponse(_result('\n204'));
      expect(resp.statusCode, 204);
      expect(resp.body, isEmpty);
    });

    test('connection failure (000) returns stderr as body', () {
      final resp = SyncHttpClient.parseResponse(
        _result('\n000', stderr: 'Connection refused', exitCode: 7),
      );
      expect(resp.statusCode, 0);
      expect(resp.body, 'curl exit 7: Connection refused');
    });

    test('curl exit 28 (timeout) surfaces a distinct timeout error', () {
      final resp = SyncHttpClient.parseResponse(
        _result('\n000', stderr: 'Operation timed out', exitCode: 28),
      );
      expect(resp.statusCode, 0);
      expect(resp.body, contains('timed out'));
      expect(resp.body, contains('--max-time'));
    });
  });
}

void _testIsOk() {
  group('SyncHttpResponse.isOk', () {
    test('2xx is true, everything else false', () {
      expect(const SyncHttpResponse(200, '').isOk, isTrue);
      expect(const SyncHttpResponse(201, '').isOk, isTrue);
      expect(const SyncHttpResponse(299, '').isOk, isTrue);
      expect(const SyncHttpResponse(300, '').isOk, isFalse);
      expect(const SyncHttpResponse(404, '').isOk, isFalse);
      expect(const SyncHttpResponse(0, '').isOk, isFalse);
    });
  });
}

void _testLiveHttp() {
  _testLiveMethods();
  _testLiveHeadersAndFailures();
}

void _testLiveMethods() {
  group('SyncHttpClient live HTTP methods', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() => server.stop());

    test('GET returns echoed response', () {
      final resp = SyncHttpClient.get('http://127.0.0.1:${server.port}/api/t');
      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body);
      expect(body['method'], 'GET');
      expect(body['path'], '/api/t');
    });

    test('POST sends body to server', () {
      final resp = SyncHttpClient.post(
        'http://127.0.0.1:${server.port}/submit',
        headers: {'Content-Type': 'application/json'},
        body: '{"hello":"world"}',
      );
      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body);
      expect(body['method'], 'POST');
      expect(body['body'], '{"hello":"world"}');
    });

    test('PUT sends body', () {
      final resp = SyncHttpClient.put(
        'http://127.0.0.1:${server.port}/update',
        body: '{"k":1}',
      );
      final body = jsonDecode(resp.body);
      expect(body['method'], 'PUT');
    });

    test('DELETE works', () {
      final resp = SyncHttpClient.delete('http://127.0.0.1:${server.port}/rm');
      final body = jsonDecode(resp.body);
      expect(body['method'], 'DELETE');
    });
  });
}

void _testLiveHeadersAndFailures() {
  group('SyncHttpClient live HTTP headers and failures', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() => server.stop());

    test('custom headers reach the server', () {
      final resp = SyncHttpClient.get(
        'http://127.0.0.1:${server.port}/api',
        headers: {'X-Custom': 'abc123'},
      );
      final body = jsonDecode(resp.body);
      expect(body['headers']['X-Custom'], 'abc123');
    });

    test('connection failure yields status 0', () {
      // Port 1 requires root — very unlikely to have a listener.
      final resp = SyncHttpClient.get('http://127.0.0.1:1/nope');
      expect(resp.statusCode, 0);
      expect(resp.isOk, isFalse);
    });

    test('large body (200KB) avoids the argv size limit via temp file', () {
      final big = 'x' * 200 * 1024;
      final resp = SyncHttpClient.post(
        'http://127.0.0.1:${server.port}/big',
        body: big,
      );
      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body);
      expect((body['body'] as String).length, 200 * 1024);
    });
  });
}

ProcessResult _result(String stdout, {String stderr = '', int exitCode = 0}) =>
    ProcessResult(0, exitCode, stdout, stderr);
