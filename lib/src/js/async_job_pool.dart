/// Pre-spawned engine-worker pool behind `runAsync(fn, args)` — parallel
/// JavaScript execution over the synchronous QuickJS bridge
/// (epam/dmtools-dart#224, Option A).
///
/// The transport and lifecycle mechanics live in the `quickjs_runtime`
/// package ([AsyncEnginePool]): worker spawning + handshake, the
/// dispatch/wait mailbox protocol, FIFO backpressure, fire-and-forget
/// envelope caching, and dead-worker completion. This file is the
/// dmtools adapter on top:
///
/// - the worker body ([_dmtoolsWorkerMain], a top-level `Isolate.spawn`
///   entry): per-worker `SyncHttpBridge` (statics are per-isolate, so the
///   worker's HTTP calls never interleave with the main engine's) and a
///   fresh, fully wired engine per job — own tool registry, own require
///   cache ([wireEngine]/[EngineSpec]);
/// - the per-dispatch context: params/working-directory/script-directory
///   of the calling engine run plus a [PropertyReader] overrides snapshot
///   (mirrors Java ThreadLocal overrides);
/// - the host-function helpers ([dispatchAsyncJob]/[waitAsyncJob]) and the
///   `runAsync`/`AsyncJob` prelude used by `JsJobRunner`.
///
/// Each worker is a full parallel engine on its own isolate. QuickJS
/// engines are never shared across isolates — one engine per isolate,
/// always.
///
/// Boot discipline: `bin/dmtools.dart` boots [instance] in `main()`
/// before any JS runs (`Isolate.spawn` cannot progress while the spawning
/// isolate is blocked in an FFI callback); tests boot private pools and
/// must call [dispose] in teardown.
///
/// No timeouts in v1: a dispatched function that never returns blocks its
/// caller forever, exactly like a main-script infinite loop would. See
/// the `quickjs_runtime` `async_engine_pool` docs for the remaining
/// failure-path semantics (dead workers complete their unwaited jobs with
/// an error envelope).
library;

import 'dart:convert';

import 'package:quickjs_runtime/quickjs_runtime.dart';

import '../config/property_reader.dart';
import 'engine_factory.dart';
import 'sync_http_bridge.dart';

export 'package:quickjs_runtime/quickjs_runtime.dart'
    show AsyncJobEnvelope, asyncJobPrelude, asyncWorkerBootstrap;

/// Worker body: warm per-worker HTTP bridge, fresh wired engine per job.
///
/// Top-level on purpose — an `Isolate.spawn` entry cannot capture
/// instance state. Never throws: every job is answered with an envelope.
Future<void> _dmtoolsWorkerMain(AsyncWorkerLink link) async {
  await SyncHttpBridge.shared.boot();
  try {
    while (true) {
      final request = await link.next();
      if (request == null) return; // shutdown
      link.complete(
        AsyncJobEnvelope.fromJson(_runJobOnWorker(link.workerId, request)),
      );
    }
  } finally {
    SyncHttpBridge.shared.dispose(); // this isolate's private HTTP worker
  }
}

/// Runs one dispatched function on a fresh engine — never throws.
Map<String, dynamic> _runJobOnWorker(int workerId, AsyncJobRequest request) {
  final overrides = request.context['overrides'];
  PropertyReader.setOverrides(
    overrides is Map
        ? overrides.map((k, v) => MapEntry('$k', '$v'))
        : <String, String>{},
  );
  final runtime = QuickjsRuntime();
  try {
    final compat = wireEngine(
      runtime,
      EngineSpec(
        context: EngineContext.direct(
          request.context['params'] as Map<String, dynamic>,
        ),
        workingDirectory: request.context['workingDirectory'] as String?,
        scriptDirectory: request.context['scriptDirectory'] as String?,
        consolePrefix: '[jsr:$workerId] ',
      ),
    );
    final result = runAsyncJobOnRuntime(
      runtime,
      jobId: request.jobId,
      fnSource: request.fnSource,
      argsJson: request.argsJson,
    );
    // dispatched fns can register timers; drain them once the job settles
    try {
      compat?.drainTimers();
    } catch (_) {
      // a timer drain failure must not mask the job's own result/error
    }
    return result;
  } catch (e) {
    return AsyncJobEnvelope(
      jobId: request.jobId,
      ok: false,
      error: e.toString(),
    ).toJson();
  } finally {
    runtime.close();
  }
}

/// dmtools pool: [AsyncEnginePool] wired with the dmtools worker body.
///
/// The CLI uses [instance]; tests create private pools and must call
/// [dispose] in teardown so the isolates exit and the test runner ends.
class AsyncJobPool {
  /// Creates a pool that [boot]s [workers] engine isolates.
  AsyncJobPool({this.workers = defaultWorkerCount})
      : _pool = AsyncEnginePool(
          workers: workers,
          workerMain: _dmtoolsWorkerMain,
        );

  /// Default worker count for the CLI pool.
  static const int defaultWorkerCount = 4;

  /// Process-wide pool used by the CLI (`bin/dmtools.dart` boots it).
  static final AsyncJobPool instance = AsyncJobPool();

  /// Number of engine isolates this pool boots.
  final int workers;

  final AsyncEnginePool _pool;

  /// Whether [dispatch] is usable.
  bool get ready => _pool.ready;

  /// Boots the worker isolates; idempotent. Must run while the event loop
  /// is alive.
  Future<void> boot() => _pool.boot();

  /// Dispatches one job to a worker and returns its id.
  ///
  /// Blocks while every worker is busy (FIFO backpressure) or while the
  /// first worker finishes booting. Never called with an unbooted pool by
  /// production wiring: `JsJobRunner` checks [ready] via the `runAsync`
  /// prelude contract and surfaces a JS error instead.
  int dispatch({
    required String fnSource,
    required String argsJson,
    required String scriptDirectory,
    String? workingDirectory,
    required Map<String, dynamic> params,
    Map<String, String> overrides = const {},
  }) {
    return _pool.dispatch(
      fnSource: fnSource,
      argsJson: argsJson,
      context: {
        'scriptDirectory': scriptDirectory,
        'workingDirectory': workingDirectory,
        'params': params,
        'overrides': overrides,
      },
    );
  }

  /// Waits for [jobId] and returns its envelope (blocking).
  ///
  /// Serving from cache makes a late `wait()` on an already-completed
  /// fire-and-forget job work. Waiting twice for the same job throws.
  AsyncJobEnvelope wait(int jobId) => _pool.wait(jobId);

  /// Asks every worker to exit (in-flight jobs finish first) and resets
  /// the pool; a fresh [boot] revives it.
  void dispose() => _pool.dispose();

  /// Kills a worker isolate outright (dead-worker test hook).
  ///
  /// `Isolate.beforeNextEvent` lets the worker unwind — its private HTTP
  /// bridge is disposed by the worker's own `finally`, so the test VM does
  /// not leak the child isolate.
  void killWorkerForTest(int workerId) => _pool.killWorkerForTest(workerId);
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
