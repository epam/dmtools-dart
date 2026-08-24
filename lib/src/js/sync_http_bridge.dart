/// Sync-over-async HTTP bridge: a pooled async [HttpClient] in a worker
/// isolate serving synchronous request calls made from QuickJS
/// `NativeCallable` callbacks, where the main isolate's event loop is frozen
/// and async `Future`s can never complete.
///
/// Java parity motivation: the Java bridge executes blocking HTTP in-process
/// on pooled connections (handshake once, then reuse). The previous Dart
/// transport spawned a curl process per request — fork/exec plus a fresh
/// DNS/TCP/TLS handshake every call, which made agent runs an order of
/// magnitude slower than Java.
///
/// Mechanism (verified by experiment):
/// - `SendPort.send` is a native, non-blocking call — it works from inside a
///   blocked FFI callback, so the caller posts the request directly to the
///   worker's port.
/// - `Mailbox.take()` parks the calling OS thread on a `pthread_cond_wait`
///   (dart:ffi under the hood) — no event loop needed — and the worker's
///   `put()` from its own isolate wakes it.
/// - The worker isolate's event loop runs freely on another VM thread while
///   the main isolate is blocked.
///
/// Boot discipline: `Isolate.spawn` and the port handshake cannot progress
/// while the spawning isolate is blocked, so [boot] must complete while the
/// event loop is still alive (the CLI awaits it before any JS runs). Until
/// [ready], [SyncHttpClient] falls back to the curl transport; a request
/// takes the mailbox route only after the handshake finished, so there is no
/// window in which a request could block forever.
///
/// No isolate ever parks a thread outside an in-flight request — the worker
/// idles on its event loop (interruptible), keeping VM shutdown and test
/// runners responsive.
///
/// ponytail: one in-flight request at a time (the JS thread is serial) and no
/// worker supervision — every worker failure path answers the pending
/// request; add supervision if a hang is ever observed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:native_synchronization/mailbox.dart';
import 'package:native_synchronization/sendable.dart';

import 'sync_http_client.dart';

/// Shared bridge instance used by [SyncHttpClient].
final class SyncHttpBridge {
  SyncHttpBridge._();

  /// Process-wide bridge.
  static final SyncHttpBridge shared = SyncHttpBridge._();

  final Mailbox _responses = Mailbox();
  SendPort? _workerPort;

  /// Whether the worker isolate is running and [request] is usable.
  bool get ready => _workerPort != null;

  /// Boots the HTTP worker isolate and handshakes its port; idempotent.
  ///
  /// Must run to completion while the event loop is alive (see the library
  /// docs); subsequent calls return the same completed future.
  Future<void> boot() => _booting ??= _boot();
  Future<void>? _booting;

  Future<void> _boot() async {
    final handshake = ReceivePort();
    await Isolate.spawn(
      _httpWorkerEntry,
      _WorkerInit(
        handshakeSendPort: handshake.sendPort,
        responses: _responses.asSendable,
      ),
    );
    // The worker replies with its request inbox port; this ReceivePort is
    // no longer needed afterwards.
    _workerPort = await handshake.first as SendPort;
    handshake.close();
  }

  /// Performs one synchronous HTTP request via the worker isolate.
  ///
  /// Only valid once [ready]; transport failures surface as
  /// `SyncHttpResponse(0, message)` exactly like the curl transport.
  SyncHttpResponse request(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) {
    final port = _workerPort!;
    port.send(Uint8List.fromList(utf8.encode(jsonEncode({
      'method': method,
      'url': url,
      'headers': headers,
      'body': body,
    }))));
    final response = utf8.decode(_responses.take(), allowMalformed: true);
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    return SyncHttpResponse(
      decoded['status'] as int,
      decoded['body'] as String,
    );
  }

  /// Stops the worker isolate (test teardown; the CLI hard-exits instead).
  void dispose() {
    _workerPort?.send('shutdown');
    _workerPort = null;
    _booting = null;
  }
}

/// Spawn message for the HTTP worker isolate.
class _WorkerInit {
  _WorkerInit({required this.handshakeSendPort, required this.responses});

  final SendPort handshakeSendPort;
  final Sendable<Mailbox> responses;
}

/// HTTP worker: one pooled async [HttpClient], one request at a time.
///
/// Receives requests on its inbox port (sent from blocked sync contexts —
/// `SendPort.send` needs no event loop on the sender) and answers each via
/// the shared response [Mailbox]. Every failure path answers, so a blocked
/// caller always wakes. The isolate idles on its event loop between
/// requests — no parked threads, VM shutdown stays responsive.
Future<void> _httpWorkerEntry(_WorkerInit init) async {
  final inbox = ReceivePort();
  final responses = init.responses.materialize();
  init.handshakeSendPort.send(inbox.sendPort);
  final client = HttpClient()
    ..maxConnectionsPerHost = 8
    ..connectionTimeout =
        const Duration(seconds: SyncHttpClient.connectTimeoutSeconds)
    ..autoUncompress = false // curl parity: no implicit gzip decoding
    ..findProxy = HttpClient.findProxyFromEnvironment; // http_proxy parity
  await for (final message in inbox) {
    if (message == 'shutdown') return;
    await _serveOne(client, responses, message as Uint8List);
  }
}

/// Executes one request and puts the response envelope.
Future<void> _serveOne(
  HttpClient client,
  Mailbox responses,
  Uint8List message,
) async {
  final req = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
  const budget = Duration(seconds: SyncHttpClient.maxTimeSeconds);
  try {
    final request = await client
        .openUrl(req['method'] as String, Uri.parse(req['url'] as String))
        .timeout(budget);
    request.followRedirects = false; // curl parity: `-s` never follows
    // curl parity: no advertised gzip (autoUncompress is already off) and
    // caller-supplied header names keep their original case (dart would
    // otherwise lowercase them, which breaks case-sensitive peers).
    request.headers.remove(HttpHeaders.acceptEncodingHeader, 'gzip');
    (req['headers'] as Map<String, dynamic>?)?.forEach(
        (k, v) => request.headers.set(k, '$v', preserveHeaderCase: true));
    final body = req['body'] as String?;
    if (body != null) {
      // Fixed-length body (Content-Length, never chunked) — matches curl's
      // `--data-binary` wire format and strict servers that ignore chunked
      // request bodies.
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(budget);
    final bytes = await response
        .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
        .timeout(budget);
    responses.put(Uint8List.fromList(utf8.encode(jsonEncode({
      'status': response.statusCode,
      'body': utf8.decode(bytes.toBytes(), allowMalformed: true),
    }))));
  } on TimeoutException {
    responses.put(Uint8List.fromList(utf8.encode(jsonEncode({
      'status': 0,
      'body':
          'Request timed out after ${SyncHttpClient.maxTimeSeconds}s (--max-time)',
    }))));
  } catch (e) {
    responses.put(Uint8List.fromList(
        utf8.encode(jsonEncode({'status': 0, 'body': e.toString()}))));
  }
}
