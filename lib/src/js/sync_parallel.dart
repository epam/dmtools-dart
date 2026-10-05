/// Synchronous bounded worker pool for frozen event-loop contexts
/// (gh-348 — Java `ConfluenceParallel` parity, dm.ai d61a4abd).
///
/// QuickJS `NativeCallable` callbacks freeze the calling isolate's event
/// loop, so `Future`-based parallelism can never complete there. Like
/// [SyncHttpBridge], this pool spawns worker isolates up front (while the
/// event loop is still alive), submits jobs over `SendPort`s (a native,
/// non-blocking send that works from a blocked FFI callback), and parks
/// the caller's OS thread on `Mailbox.take()` until every job answered.
///
/// Semantics mirror the Java helper:
/// - results keep the input order of the job list;
/// - a job that throws yields `null` instead of aborting the others;
/// - the concurrency bound is the worker count (each worker serves one
///   job at a time — sync HTTP blocks the worker thread, so real
///   parallelism needs N busy workers, not N tasks on one loop);
/// - a pool that was never booted reports `ready == false`; callers are
///   expected to fall back to running jobs inline on the calling isolate.
///
/// Boot discipline: [boot] must complete while the event loop is alive
/// (the CLI awaits it at startup, next to `SyncHttpBridge.shared.boot()`).
/// Workers additionally warm their per-isolate [SyncHttpBridge] so their
/// HTTP calls reuse pooled connections instead of spawning one curl
/// process per request.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:native_synchronization/mailbox.dart';
import 'package:native_synchronization/sendable.dart';

import 'sync_http_bridge.dart';

/// Executes one pool job; implemented by the domain that owns the pool.
///
/// Must be synchronous (it runs inside blocked FFI contexts on the
/// calling isolate as the inline fallback and inside worker isolates).
/// Any throw is reported back as a `null` result, never propagated.
typedef SyncWorkerRunner = Map<String, dynamic>? Function(
  String kind,
  Map<String, dynamic> args,
);

/// Registry of named runners: `Isolate.spawn` arguments must be sendable,
/// so the runner function cannot ride the spawn message — the trampoline
/// resolves it here by name instead.
final Map<String, SyncWorkerRunner> _syncRunnerRegistry =
    <String, SyncWorkerRunner>{};

/// Registers [runner] under [name] for [SyncWorkerPool] workers.
///
/// Registration is process-global and idempotent (re-registering [name]
/// replaces the runner); names should be prefixed with the owning domain
/// (e.g. `confluence`).
void registerSyncWorkerRunner(String name, SyncWorkerRunner runner) =>
    _syncRunnerRegistry[name] = runner;

/// One unit of parallel work: [kind] selects the runner's handler,
/// [args] is the handler's argument map, [index] restores input order in
/// the result list.
class SyncParallelJob {
  /// Creates a job identified by [index] of [kind] with handler [args].
  const SyncParallelJob({
    required this.index,
    required this.kind,
    this.args = const <String, dynamic>{},
  });

  /// Position of this job in the submitted list; results are keyed by it.
  final int index;

  /// Handler selector interpreted by the pool's [SyncWorkerRunner].
  final String kind;

  /// Sendable argument map for the handler.
  final Map<String, dynamic> args;
}

/// Spawn message for [_syncPoolWorkerTrampoline]: sendable only.
class _PoolSpawnArgs {
  _PoolSpawnArgs({
    required this.runnerName,
    required this.handshake,
    required this.responses,
    required this.workerName,
  });

  final String runnerName;
  final SendPort handshake;
  final Sendable<Mailbox> responses;
  final String workerName;
}

/// Pool worker body: handshake the inbox port, then serve jobs until
/// shutdown. Every job is answered on the shared response mailbox (the
/// caller is parked in a blocking `Mailbox.take()` and must always wake).
Future<void> _syncPoolWorkerTrampoline(_PoolSpawnArgs args) async {
  await SyncHttpBridge.shared.boot();
  final runner = _syncRunnerRegistry[args.runnerName];
  final inbox = ReceivePort();
  args.handshake.send(inbox.sendPort);
  final responses = args.responses.materialize();
  await for (final message in inbox) {
    if (identical(message, 'shutdown')) return;
    final job = (message as Map).cast<String, dynamic>();
    Map<String, dynamic>? result;
    try {
      result = runner?.call(
        job['kind'] as String,
        (job['args'] as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      result = null; // Java parity: a failing task yields null, not abort.
    }
    responses.put(Uint8List.fromList(
      utf8.encode(jsonEncode(<String, dynamic>{'i': job['i'], 'r': result})),
    ));
  }
}

/// A bounded pool of worker isolates serving synchronous parallel jobs.
class SyncWorkerPool {
  /// Creates a pool whose workers resolve [runnerName] from the
  /// [registerSyncWorkerRunner] registry.
  SyncWorkerPool(
    this.runnerName, {
    this.name = 'sync-worker',
    this.workerCount = 4,
  });

  /// Registry key of the runner serving this pool's jobs.
  final String runnerName;

  /// Worker/thread name prefix (diagnostics).
  final String name;

  /// Number of worker isolates; jobs run concurrently up to this bound.
  final int workerCount;

  final Mailbox _responses = Mailbox();
  final List<SendPort> _inboxes = <SendPort>[];
  Future<void>? _booting;
  var _next = 0;

  /// Whether [boot] completed and [run] can be used.
  bool get ready => _inboxes.isNotEmpty;

  /// Boots [workerCount] worker isolates; idempotent.
  ///
  /// Must complete while the event loop is alive (see the library docs).
  Future<void> boot() =>
      _booting ??= _boot(workerCount < 1 ? 1 : workerCount);

  Future<void> _boot(int workers) async {
    for (var i = 0; i < workers; i++) {
      final handshake = ReceivePort();
      await Isolate.spawn(
        _syncPoolWorkerTrampoline,
        _PoolSpawnArgs(
          runnerName: runnerName,
          handshake: handshake.sendPort,
          responses: _responses.asSendable,
          workerName: '$name-${i + 1}',
        ),
      );
      _inboxes.add(await handshake.first as SendPort);
      handshake.close();
    }
  }

  /// Runs [jobs] across the pool and returns their results in input
  /// order; a job that throws (or an unknown kind) yields `null`.
  ///
  /// Only valid once [ready]; throws [StateError] otherwise — callers
  /// that may run unbooted are expected to check [ready] and fall back to
  /// executing the jobs inline on the calling isolate.
  List<Map<String, dynamic>?> run(List<SyncParallelJob> jobs) {
    if (!ready) {
      throw StateError('SyncWorkerPool "$name" is not booted');
    }
    if (jobs.isEmpty) return const <Map<String, dynamic>>[];
    _submit(jobs);
    return _collect(jobs.length);
  }

  /// Sends every job to a worker inbox, round-robin.
  void _submit(List<SyncParallelJob> jobs) {
    for (final job in jobs) {
      _inboxes[_next].send(<String, dynamic>{
        'i': job.index,
        'kind': job.kind,
        'args': job.args,
      });
      _next = (_next + 1) % _inboxes.length;
    }
  }

  /// Parks this thread until [count] job envelopes arrived and restores
  /// their input order.
  List<Map<String, dynamic>?> _collect(int count) {
    final results = List<Map<String, dynamic>?>.filled(count, null);
    var remaining = count;
    while (remaining > 0) {
      final env =
          jsonDecode(utf8.decode(_responses.take())) as Map<String, dynamic>;
      results[env['i'] as int] = env['r'] as Map<String, dynamic>?;
      remaining--;
    }
    return results;
  }

  /// Stops the workers (test teardown; the CLI hard-exits instead).
  void dispose() {
    for (final inbox in _inboxes) {
      inbox.send('shutdown');
    }
    _inboxes.clear();
    _booting = null;
  }
}
