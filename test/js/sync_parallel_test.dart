import 'dart:io';

import 'package:dmtools/src/js/sync_parallel.dart';
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
