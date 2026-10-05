import 'dart:io';
import 'dart:isolate';

import 'package:dmtools/src/js/sync_parallel.dart';
import 'package:native_synchronization/mailbox.dart';
import 'package:test/test.dart';

/// A [SyncWorkerRunner] for the pool mechanics tests: sleeps the requested
/// duration (so concurrency assertions can observe overlap) and throws
/// when asked to (so failure semantics can be asserted).
Map<String, dynamic>? _sleepRunner(String kind, Map<String, dynamic> args) {
  if (kind != 'sleep') return null;
  final ms = args['ms'] as int? ?? 0;
  if (ms > 0) sleep(Duration(milliseconds: ms));
  if (args['fail'] == true) throw StateError('boom');
  return <String, dynamic>{'slept': ms};
}

/// Test pool worker entry ([Isolate.spawn] target — top-level on purpose).
Future<void> _sleepWorkerEntry(SyncWorkerBoot boot) =>
    serveSyncWorker(boot, _sleepRunner);

/// Pool mechanics tests mirroring the Java `ConfluenceParallelTest`
/// (dm.ai d61a4abd) — order preservation, failure isolation, bounded
/// concurrency — plus the boot/dispose lifecycle.
void main() {
  group('SyncWorkerPool', () {
    _poolSemanticsTests();
    _poolLifecycleTests();
  });
}

void _poolSemanticsTests() {
  group('semantics', () {
    late SyncWorkerPool pool;

    tearDown(() => pool.dispose());

    test('keeps input order and yields null for failed tasks', () async {
      pool = SyncWorkerPool(_sleepWorkerEntry, name: 'order', workerCount: 3);
      await pool.boot();
      final results = pool.run(<SyncParallelJob>[
        _sleepJob(0, 200),
        _sleepJob(1, 10),
        _sleepJob(2, 0, fail: true),
        _sleepJob(3, 50),
        _sleepJob(4, 20),
      ]);
      // Input order survives even though shorter jobs finish first, and
      // the failing job degrades to null instead of aborting the others
      // (Java `ConfluenceParallel.map` contract).
      expect(results, <Map<String, dynamic>?>[
        <String, dynamic>{'slept': 200},
        <String, dynamic>{'slept': 10},
        null,
        <String, dynamic>{'slept': 50},
        <String, dynamic>{'slept': 20},
      ]);
    });

    test('runs tasks concurrently but not above the worker bound', () async {
      pool = SyncWorkerPool(_sleepWorkerEntry, name: 'bound', workerCount: 3);
      await pool.boot();
      final watch = Stopwatch()..start();
      pool.run(List<SyncParallelJob>.generate(6, (i) => _sleepJob(i, 400)));
      watch.stop();
      // Six 400ms jobs on three workers: two waves (~800ms) — clearly
      // concurrent (sequential would be 2400ms) and clearly bounded.
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(400));
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });
}

void _poolLifecycleTests() {
  group('lifecycle', () {
    late SyncWorkerPool pool;

    tearDown(() => pool.dispose());

    test('empty input returns an empty result', () async {
      pool = SyncWorkerPool(_sleepWorkerEntry, name: 'empty', workerCount: 2);
      await pool.boot();
      expect(pool.run(const <SyncParallelJob>[]), isEmpty);
    });

    test('run before boot throws and inline callers check ready', () async {
      pool = SyncWorkerPool(_sleepWorkerEntry, name: 'cold', workerCount: 1);
      expect(pool.ready, isFalse);
      expect(
        () => pool.run(<SyncParallelJob>[_sleepJob(0, 0)]),
        throwsStateError,
      );
    });

    test('a null-returning runner degrades every job to null', () async {
      pool = SyncWorkerPool(_voidWorkerEntry, name: 'void', workerCount: 1);
      await pool.boot();
      expect(pool.run(<SyncParallelJob>[_sleepJob(0, 0)]), <dynamic>[null]);
    });

    test('the shutdown sentinel terminates the worker isolate', () async {
      // Regression guard for the rework review (gh-348): the sentinel used
      // to be skipped via `continue`, so `dispose()` leaked every worker
      // (and its per-isolate SyncHttpBridge HTTP worker) forever.
      final probe = _ShutdownProbe();
      await Isolate.spawn(_shutdownProbeWorkerEntry, probe.spawnMessage);
      final inbox = await probe.handshake.first as SendPort;
      // A live job round-trips first (the worker is up and serving).
      final reply = Mailbox();
      inbox.send(<String, dynamic>{
        'i': 0,
        'kind': 'sleep',
        'args': <String, dynamic>{'ms': 0},
        'reply': reply.asSendable,
      });
      expect(reply.take(), isNotNull);
      // The sentinel must END the serve loop (mirror of
      // SyncHttpBridge._httpWorkerEntry), not be skipped as foreign
      // traffic — the probe signals when serveSyncWorker returns.
      inbox.send('shutdown');
      await probe.done.first.timeout(_workerExitGrace);
    }, timeout: _shutdownTestTimeout);

    test('dispose() lets the pool boot fresh workers again', () async {
      pool = SyncWorkerPool(_sleepWorkerEntry, name: 'reboot', workerCount: 1);
      await pool.boot();
      expect(
        pool.run(<SyncParallelJob>[_sleepJob(0, 0)]),
        <Map<String, dynamic>?>[
          <String, dynamic>{'slept': 0},
        ],
      );
      pool.dispose();
      expect(pool.ready, isFalse);
      await pool.boot();
      expect(pool.ready, isTrue);
      expect(
        pool.run(<SyncParallelJob>[_sleepJob(0, 0)]),
        <Map<String, dynamic>?>[
          <String, dynamic>{'slept': 0},
        ],
      );
    });

    test('a failed boot is not cached — the next boot() retries', () async {
      pool =
          SyncWorkerPool(_badHandshakeWorkerEntry, name: 'bad', workerCount: 1);
      final first = pool.boot();
      await expectLater(first, throwsA(anything));
      expect(pool.ready, isFalse);
      // The dead future must not be served again: a fresh attempt is made
      // (and fails the same way, the entry stays broken). With the failure
      // cached, `boot()` handed back the identical errored future forever.
      final second = pool.boot();
      expect(identical(first, second), isFalse,
          reason: 'boot() must retry after a failed boot');
      await expectLater(second, throwsA(anything));
    }, timeout: _shutdownTestTimeout);
  });
}

/// One `sleep` job: [index] position, [ms] duration, optional failure.
SyncParallelJob _sleepJob(int index, int ms, {bool fail = false}) =>
    SyncParallelJob(
      index: index,
      kind: 'sleep',
      args: <String, dynamic>{'ms': ms, if (fail) 'fail': true},
    );

/// Entry whose runner answers `null` for everything (unknown-kind
/// coverage without a registered runner).
Future<void> _voidWorkerEntry(SyncWorkerBoot boot) =>
    serveSyncWorker(boot, (kind, args) => null);

/// Grace period for the worker-exit assertions; the test-level timeout
/// below fails the case before the 30s suite default on a regression.
const _workerExitGrace = Duration(seconds: 4);
const _shutdownTestTimeout = Timeout(Duration(seconds: 10));

/// Spawn payload of the shutdown probe: the worker's handshake reply port
/// and the port signalling that [serveSyncWorker] returned.
typedef _ShutdownProbeMessage = ({SendPort handshake, SendPort done});

class _ShutdownProbe {
  final handshake = ReceivePort();
  final done = ReceivePort();

  _ShutdownProbeMessage get spawnMessage =>
      (handshake: handshake.sendPort, done: done.sendPort);
}

/// Probe worker entry: serves exactly like a pool worker, then signals
/// [serveSyncWorker]'s return — reached only when the shutdown sentinel
/// (or a closed inbox) ends the serve loop.
Future<void> _shutdownProbeWorkerEntry(_ShutdownProbeMessage probe) async {
  await serveSyncWorker(
    SyncWorkerBoot(handshake: probe.handshake),
    _sleepRunner,
  );
  probe.done.send('exited');
}

/// Entry that breaks the boot handshake (sends a non-`SendPort`), so
/// `_boot` fails with a cast error — the deterministic boot-failure case.
Future<void> _badHandshakeWorkerEntry(SyncWorkerBoot boot) async {
  boot.handshake.send(42);
}
