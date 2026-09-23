import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/async_job_pool.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// Cross-runtime conformance: `test/fixtures/cross_runtime_conformance.js`
/// is byte-identical with the epam/dm.ai Java test resource and the
/// quickjs_runtime fixture. QuickJS (this test, through the real product
/// wiring — [JsJobRunner], the dmtools worker pool, and the opt-in
/// `nodeCompat` layer installed by `wireEngine` on the main engine AND
/// worker engines) and GraalJS (`JsCrossRuntimeConformanceTest` in
/// dm.ai) must produce the identical result.
///
/// The worker adapter builds a fresh engine per job, so dispatched
/// functions see `require('path')` and `TextEncoder` exactly like the
/// main script does.
void main() {
  late AsyncJobPool pool;

  setUp(() async {
    pool = AsyncJobPool(workers: 2);
    await pool.boot();
  });

  tearDown(() => pool.dispose());

  const expected = <String, dynamic>{
    'globalAlias': true,
    'processType': 'object',
    'envIsObject': true,
    'cwdIsString': true,
    'joined': 'a/b/c.txt',
    'baseName': 'z.md',
    'assertOk': true,
    'formatted': 'answer=42',
    'utf8ByteLen': 10,
    'utf8RoundTrip': true,
    'base64': true,
    'clockIsNumber': true,
    'uuidShape': true,
    'randomFilled': true,
    'cloneDeep': true,
    'stubGuards': true,
    'parallel': {
      'sum': 5050,
      'workerBase': 'parallel.js',
      'workerUtf8': 4,
      'allValues': ['first', 'second'],
    },
  };

  test('conformance script produces the identical cross-runtime result', () {
    final runner = JsJobRunner();
    final result = runner.runScript(
      scriptPath:
          File('test/fixtures/cross_runtime_conformance.js').absolute.path,
      jobParams: const {'parallelWorkers': 2, 'nodeCompat': true},
      config: JsRunConfig(pool: pool),
    );
    final decoded = jsonDecode(result!) as Map<String, dynamic>;
    expect(decoded, equals(expected));
  });

  test('knobs off: the same script fails (no runAsync, no console)', () {
    final runner = JsJobRunner();
    expect(
      () => runner.runScript(
        scriptPath:
            File('test/fixtures/cross_runtime_conformance.js').absolute.path,
        jobParams: const {},
        config: JsRunConfig(pool: pool),
      ),
      throwsA(anything),
    );
  });
}
