/// Unit tests for the lazy engine-worker pool boot in [CliDispatcher]
/// (gh-241): `AsyncJobPool.instance` must boot only when the resolved job
/// config enables `runAsync` (`parallelWorkers >= 2`), just before the JS
/// run — while the event loop is still alive, before QuickJS host
/// callbacks block the isolate in FFI. Every other command keeps zero
/// pool cost, and a failed boot degrades to the documented unbooted-pool
/// JS error instead of killing the command.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;
late List<String> _lines;
late CliDispatcher _dispatcher;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_cli_pool_');
    PropertyReader.setOverrides({});
    _lines = [];
  });
  tearDown(() {
    PropertyReader.clearOverrides();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testLazyBoot();
  _testBootFailure();
}

CliDispatcher _poolDispatcher(AsyncJobPool pool) => CliDispatcher(
      writer: _lines.add,
      propertyReader: PropertyReader(basePath: _tmp.path),
      isTty: () => false,
      asyncPool: pool,
    );

/// Writes [source] as a jsrunner script with [jobParams] and runs it
/// through [_dispatcher]; returns the exit code.
Future<int> _runPoolJob(String source, Map<String, dynamic> jobParams) {
  final script = File('${_tmp.path}/pool_probe.js')..writeAsStringSync(source);
  final config = File('${_tmp.path}/pool_job.json')
    ..writeAsStringSync(jsonEncode({
      'name': 'jsrunner',
      'params': {
        'jsPath': script.path,
        'jobParams': jobParams,
      },
    }));
  return _dispatcher.dispatch(['run', config.path]);
}

void _testLazyBoot() {
  group('run: lazy engine-worker pool boot (gh-241)', () {
    late AsyncJobPool pool;
    setUp(() {
      pool = AsyncJobPool(workers: 1);
      _dispatcher = _poolDispatcher(pool);
    });
    tearDown(() => pool.dispose());

    test('parallelWorkers >= 2 boots the pool before the JS run', () async {
      expect(
        await _runPoolJob(
          'function action(params) { return typeof runAsync; }',
          const {'parallelWorkers': 2},
        ),
        0,
      );
      expect(_lines.last, '"function"');
      expect(pool.ready, isTrue);
    });

    test('a runAsync dispatch works end-to-end after the lazy boot', () async {
      expect(
        await _runPoolJob(
          '''
function action(params) {
  return runAsync(function (args) { return args.n * 2; }, { n: 21 }).wait();
}
''',
          const {'parallelWorkers': 2},
        ),
        0,
      );
      expect(_lines.last, '42');
    });

    test('parallelWorkers < 2 leaves the pool unbooted', () async {
      expect(
        await _runPoolJob(
          'function action(params) { return typeof runAsync; }',
          const {'parallelWorkers': 1},
        ),
        0,
      );
      expect(_lines.last, '"undefined"');
      expect(pool.ready, isFalse);
    });

    test('non-run commands never boot the pool', () async {
      expect(await _dispatcher.dispatch(['--version']), 0);
      expect(pool.ready, isFalse);
    });
  });
}

void _testBootFailure() {
  group('run: engine-worker pool boot failure (gh-241)', () {
    final errorLines = <String>[];
    setUp(() {
      errorLines.clear();
      _dispatcher = CliDispatcher(
        writer: _lines.add,
        errorWriter: errorLines.add,
        propertyReader: PropertyReader(basePath: _tmp.path),
        isTty: () => false,
        asyncPool: _ExplodingPool(),
      );
    });

    test('a failed boot degrades to the unbooted-pool JS error', () async {
      expect(
        await _runPoolJob(
          '''
function action(params) {
  try {
    runAsync(function () { return 1; }, null);
    return 'no-error';
  } catch (e) {
    return String(e);
  }
}
''',
          const {'parallelWorkers': 2},
        ),
        0,
      );
      expect(_lines.last, contains('not booted'));
    });

    test('the degraded boot is reported on the error channel', () async {
      expect(
        await _runPoolJob(
          'function action(params) { return typeof runAsync; }',
          const {'parallelWorkers': 2},
        ),
        0,
      );
      expect(errorLines, hasLength(1));
      expect(errorLines.single, contains('engine-worker pool boot failed'));
      expect(errorLines.single, contains('isolate quota exhausted'));
      // stdout stays machine-parseable: the runAsync surface is wired
      // (dispatch fails only on first use) and no warning lines mix in.
      expect(_lines, ['"function"']);
    });
  });
}

/// Pool whose [boot] fails — the constrained-environment case (gh-241).
class _ExplodingPool extends AsyncJobPool {
  @override
  Future<void> boot() async => throw StateError('isolate quota exhausted');
}
