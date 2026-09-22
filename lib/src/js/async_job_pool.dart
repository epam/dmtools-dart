/// Pre-spawned engine-worker pool behind `runAsync(fn, args)` — parallel
/// JavaScript execution over the synchronous QuickJS bridge
/// (epam/dmtools-dart#224, Option A).
///
/// Each worker is a full parallel engine on its own isolate (own
/// `QuickjsRuntime` per job, own tool registry, own require cache, own
/// `SyncHttpBridge` — statics are per-isolate, so the worker's HTTP calls
/// never interleave with the main engine's). QuickJS engines are never
/// shared across isolates — one engine per isolate, always.
///
/// Mechanism (mirrors the proven [SyncHttpBridge] pattern):
/// - `boot()` runs while the main event loop is alive: it spawns the worker
///   isolates and handshakes their inbox ports. `Isolate.spawn` cannot
///   progress while the spawning isolate is blocked in an FFI callback, so
///   the CLI boots the pool in `main()` before any JS runs; tests boot a
///   private pool in `setUpAll`.
/// - `dispatch()` (`__jsrDispatchHost`) is called from JS on the main
///   engine — i.e. from inside a blocked FFI callback. `SendPort.send` is
///   a native non-blocking call, so it works there.
/// - `wait()` (`__jsrWaitHost`) parks the calling OS thread on a
///   `Mailbox.take()` (native pthread condvar — no event loop needed) until
///   the worker puts the job envelope. The worker's isolate runs freely on
///   another VM thread while the main engine is blocked.
///
/// Backpressure: there are exactly `workers` engines. `dispatch` claims an
/// idle worker; when all workers are busy it blocks (FIFO) on the oldest
/// busy worker's completion — jobs queue by dispatch order. There are no
/// timeouts in v1: a dispatched function that never returns blocks its
/// caller forever, exactly like a main-script infinite loop would.
///
/// Failure paths: a worker answers every dispatched job (`ok:false` + error
/// text on any failure, JS exception or host-tool error alike); a worker
/// isolate that exits is marked dead by an exit listener and its undis-
/// patched jobs are completed with an error envelope. Residual gap (v1): a
/// `wait()` already parked on a dead worker's mailbox still blocks.
///
/// Fire-and-forget jobs are legal: completed envelopes nobody waited for
/// are cached and served if `wait()` comes later, and `dispose()` asks the
/// workers to exit (they finish any in-flight job first).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:native_synchronization/mailbox.dart';
import 'package:native_synchronization/sendable.dart';

import '../config/property_reader.dart';
import 'async_prelude.dart';
import 'engine_factory.dart';
import 'package:quickjs_runtime/quickjs_runtime.dart';
import 'sync_http_bridge.dart';

/// Completion envelope for one dispatched job.
class AsyncJobEnvelope {
  /// Creates an envelope.
  const AsyncJobEnvelope({
    required this.jobId,
    required this.ok,
    this.resultJson,
    this.error,
  });

  /// Parses an envelope from its worker JSON shape.
  factory AsyncJobEnvelope.fromJson(Map<String, dynamic> json) {
    return AsyncJobEnvelope(
      jobId: json['jobId'] as int,
      ok: json['ok'] as bool,
      resultJson: json['resultJson'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Pool-assigned job id.
  final int jobId;

  /// Whether the function ran to completion without throwing.
  final bool ok;

  /// JSON-encoded return value of the dispatched function.
  final String? resultJson;

  /// Error text when [ok] is false.
  final String? error;

  /// The decoded return value (raw string if it was not valid JSON).
  Object? get decodedResult {
    final raw = resultJson;
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  /// JSON transport shape (worker → pool).
  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'ok': ok,
        'resultJson': resultJson,
        'error': error,
      };
}

/// Lifecycle state of one worker (main-side view).
enum _WorkerState { booting, idle, busy, dead }

class _Worker {
  _Worker({
    required this.id,
    required this.isolate,
    required this.sendPort,
    required this.doneBox,
  });

  final int id;
  final Isolate isolate;
  final SendPort sendPort;
  final Mailbox doneBox;
  _WorkerState state = _WorkerState.booting;
}

class _PendingJob {
  _PendingJob({required this.workerId});

  final int workerId;
}

/// Spawn message for a worker isolate.
class _WorkerInit {
  _WorkerInit({
    required this.workerId,
    required this.handshake,
    required this.doneBox,
  });

  final int workerId;
  final SendPort handshake;
  final Sendable<Mailbox> doneBox;
}

/// Pool of engine-worker isolates serving `runAsync` dispatches.
///
/// The CLI uses [instance]; tests create private pools and must call
/// [dispose] in teardown so the isolates exit and the test runner ends.
class AsyncJobPool {
  /// Creates a pool that [boot]s [workers] engine isolates.
  AsyncJobPool({this.workers = defaultWorkerCount});

  /// Default worker count for the CLI pool.
  static const int defaultWorkerCount = 4;

  /// Process-wide pool used by the CLI (`bin/dmtools.dart` boots it).
  static final AsyncJobPool instance = AsyncJobPool();

  static final Uint8List _readyMessage = utf8.encode('ready');

  /// Number of engine isolates this pool boots.
  final int workers;

  final _workers = <_Worker>[];
  final _jobs = <int, _PendingJob>{};
  final _completed = <int, AsyncJobEnvelope>{};
  ReceivePort? _exitPort;
  Future<void>? _booting;
  bool _booted = false;
  int _nextJobId = 0;

  /// Whether [dispatch] is usable.
  bool get ready => _booted;

  /// Boots the worker isolates; idempotent (later calls return the first
  /// boot's future). Must run while the event loop is alive.
  Future<void> boot() => _booting ??= _boot();

  Future<void> _boot() async {
    final exitPort = ReceivePort()..listen(_onWorkerExit);
    _exitPort = exitPort;
    for (var i = 0; i < workers; i++) {
      final handshake = ReceivePort();
      final doneBox = Mailbox();
      final isolate = await Isolate.spawn(
        _workerEntry,
        _WorkerInit(
          workerId: i,
          handshake: handshake.sendPort,
          doneBox: doneBox.asSendable,
        ),
      );
      isolate.addOnExitListener(exitPort.sendPort, response: i);
      final port = await handshake.first as SendPort;
      handshake.close();
      _workers.add(
        _Worker(id: i, isolate: isolate, sendPort: port, doneBox: doneBox),
      );
    }
    _booted = true;
  }

  /// Dispatches one job to a worker and returns its id.
  ///
  /// Blocks while every worker is busy (FIFO backpressure — see the library
  /// docs) or while the first worker finishes booting. Never called with an
  /// unbooted pool by production wiring: `JsJobRunner` checks [ready] via
  /// the `runAsync` prelude contract and surfaces a JS error instead.
  int dispatch({
    required String fnSource,
    required String argsJson,
    required String scriptDirectory,
    String? workingDirectory,
    required Map<String, dynamic> params,
    Map<String, String> overrides = const {},
  }) {
    if (!_booted) {
      throw StateError('JS worker pool is not booted');
    }
    final worker = _acquireWorker();
    final jobId = _nextJobId++;
    _jobs[jobId] = _PendingJob(workerId: worker.id);
    worker.sendPort.send(
      jsonEncode({
        'jobId': jobId,
        'fnSource': fnSource,
        'argsJson': argsJson,
        'scriptDirectory': scriptDirectory,
        'workingDirectory': workingDirectory,
        'params': params,
        'overrides': overrides,
      }),
    );
    return jobId;
  }

  /// Waits for [jobId] and returns its envelope (blocking).
  ///
  /// Serving from cache makes a late `wait()` on an already-completed
  /// fire-and-forget job work. Waiting twice for the same job throws.
  AsyncJobEnvelope wait(int jobId) {
    final cached = _completed.remove(jobId);
    if (cached != null) {
      _jobs.remove(jobId);
      return cached;
    }
    final pending = _jobs[jobId];
    if (pending == null) {
      throw StateError('Unknown or already-waited async job id $jobId');
    }
    final worker = _workerById(pending.workerId);
    while (true) {
      final envelope = _takeEnvelope(worker);
      if (envelope.jobId == jobId) {
        _jobs.remove(jobId);
        return envelope;
      }
      _completed[envelope.jobId] = envelope;
    }
  }

  /// Asks every worker to exit (in-flight jobs finish first) and resets the
  /// pool; a fresh [boot] revives it.
  void dispose() {
    for (final worker in _workers) {
      if (worker.state != _WorkerState.dead) {
        worker.sendPort.send('shutdown');
      }
    }
    _workers.clear();
    _jobs.clear();
    _completed.clear();
    _exitPort?.close();
    _exitPort = null;
    _booted = false;
    _booting = null;
  }

  /// Claims a worker for [dispatch], draining completed jobs as needed.
  _Worker _acquireWorker() {
    if (_workers.isEmpty) {
      throw StateError('JS worker pool has no workers');
    }
    for (final worker in _workers) {
      _settleWorker(worker);
      if (worker.state == _WorkerState.idle) return _claim(worker);
    }
    // Saturated: block on the oldest busy worker's completion (FIFO).
    final busy = _workers.where((w) => w.state == _WorkerState.busy).toList();
    if (busy.isEmpty) {
      throw StateError('JS worker pool has no live workers');
    }
    final envelope = _takeEnvelope(busy.first);
    _completed[envelope.jobId] = envelope;
    return _claim(busy.first);
  }

  /// Kills a worker isolate outright (dead-worker test hook).
  ///
  /// [IsolateBeforeNextEvent] lets the worker unwind — its private HTTP
  /// bridge is disposed by the worker's own `finally`, so the test VM does
  /// not leak the child isolate.
  void killWorkerForTest(int workerId) {
    _workerById(workerId).isolate.kill(priority: Isolate.beforeNextEvent);
  }

  void _settleWorker(_Worker worker) {
    if (worker.state == _WorkerState.booting) {
      final message = utf8.decode(worker.doneBox.take());
      if (message != 'ready') {
        throw StateError('Unexpected worker message: $message');
      }
      worker.state = _WorkerState.idle;
    }
  }

  AsyncJobEnvelope _takeEnvelope(_Worker worker) {
    final raw = utf8.decode(worker.doneBox.take());
    final envelope = AsyncJobEnvelope.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    worker.state = _WorkerState.idle;
    return envelope;
  }

  _Worker _claim(_Worker worker) {
    worker.state = _WorkerState.busy;
    return worker;
  }

  _Worker _workerById(int id) => _workers.firstWhere((w) => w.id == id);

  /// Exit listener: marks the worker dead and completes its undispatched
  /// jobs with an error envelope (delivered when the event loop can run).
  void _onWorkerExit(dynamic message) {
    if (message is! int || _exitPort == null) return;
    final worker = _workerById(message);
    worker.state = _WorkerState.dead;
    _jobs.removeWhere((jobId, job) {
      if (job.workerId != worker.id) return false;
      _completed[jobId] = AsyncJobEnvelope(
        jobId: jobId,
        ok: false,
        error: 'JS worker ${worker.id} exited unexpectedly',
      );
      return true;
    });
  }

  /// Worker isolate entry: handshake, private HTTP bridge, ready, job loop.
  ///
  /// Every failure path of a job answers the pool's envelope mailbox, so a
  /// blocked `wait()` always wakes. The isolate idles on its event loop
  /// between jobs.
  static Future<void> _workerEntry(_WorkerInit init) async {
    final inbox = ReceivePort();
    final doneBox = init.doneBox.materialize();
    init.handshake.send(inbox.sendPort);
    await SyncHttpBridge.shared.boot(); // per-isolate HTTP bridge
    doneBox.put(_readyMessage);
    try {
      await for (final message in inbox) {
        if (message == 'shutdown') return;
        doneBox.put(utf8
            .encode(jsonEncode(_executeJob(init.workerId, message as String))));
      }
    } finally {
      SyncHttpBridge.shared.dispose(); // this isolate's private HTTP worker
    }
  }

  /// Runs one dispatched function on a fresh engine — never throws.
  static Map<String, dynamic> _executeJob(int workerId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, dynamic>;
    final jobId = request['jobId'] as int;
    final overrides = request['overrides'];
    PropertyReader.setOverrides(
      overrides is Map
          ? overrides.map((k, v) => MapEntry('$k', '$v'))
          : <String, String>{},
    );
    final runtime = QuickjsRuntime();
    try {
      wireEngine(
        runtime,
        EngineSpec(
          directParams: request['params'] as Map<String, dynamic>?,
          workingDirectory: request['workingDirectory'] as String?,
          scriptDirectory: request['scriptDirectory'] as String?,
          consolePrefix: '[jsr:$workerId] ',
        ),
      );
      runtime.eval(asyncWorkerBootstrap, filename: '<jsr_worker_bootstrap>');
      final errors = <String?>[];
      final result = runtime.eval(
        '__jsrCall(${jsonEncode(request['fnSource'])}, '
        '${jsonEncode(request['argsJson'])})',
        filename: '<jsr_job>',
        errMsg: errors,
      );
      return AsyncJobEnvelope(
        jobId: jobId,
        ok: errors.isEmpty,
        resultJson: result,
        error: errors.isEmpty ? null : errors.first,
      ).toJson();
    } catch (e) {
      return AsyncJobEnvelope(
        jobId: jobId,
        ok: false,
        error: e.toString(),
      ).toJson();
    } finally {
      runtime.close();
    }
  }
}

/// `__jsrDispatchHost` implementation: parses the JS call, snapshots the
/// current overrides, dispatches, and answers with the JSON job id — or a
/// `{'__jsError': …}` sentinel the prelude rethrows.
String dispatchAsyncJob(
  AsyncJobPool pool,
  String argsJson, {
  required String scriptDirectory,
  String? workingDirectory,
  required Map<String, dynamic> params,
}) {
  try {
    final args = jsonDecode(argsJson);
    if (args is! List || args.length < 2 || args[0] is! String) {
      return jsonEncode({
        '__jsError': 'runAsync expects (function, args) — '
            'got ${args is List ? args.length : 'non-array'} arguments',
      });
    }
    final second = args[1];
    final jobId = pool.dispatch(
      fnSource: args[0] as String,
      argsJson: second is String ? second : jsonEncode(second),
      scriptDirectory: scriptDirectory,
      workingDirectory: workingDirectory,
      params: params,
      overrides: PropertyReader.getOverrides(),
    );
    return jsonEncode(jobId);
  } catch (e) {
    return jsonEncode({'__jsError': 'runAsync dispatch failed: $e'});
  }
}

/// `__jsrWaitHost` implementation: blocks on the pool until [argsJson]'s
/// job completes, then answers with the JS envelope JSON — or a
/// `{'__jsError': …}` sentinel.
String waitAsyncJob(AsyncJobPool pool, String argsJson) {
  try {
    final id = jsonDecode(argsJson);
    if (id is! int) {
      return jsonEncode({'__jsError': 'AsyncJob.wait expects a job id'});
    }
    final envelope = pool.wait(id);
    return jsonEncode({
      'ok': envelope.ok,
      'result': envelope.decodedResult,
      'error': envelope.error,
    });
  } catch (e) {
    return jsonEncode({'__jsError': 'AsyncJob.wait failed: $e'});
  }
}
