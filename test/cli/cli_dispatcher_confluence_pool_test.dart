/// Unit tests for the lazy Confluence worker pool boot in [CliDispatcher]
/// (gh-348 rework): the pool must boot only for commands that can reach a
/// Confluence sync tool — a direct `confluence_*` invocation, or a job run
/// while Confluence is configured (an agent's tool calls execute inside
/// QuickJS host callbacks that block this isolate's event loop, so the
/// boot cannot happen later). Every other command keeps zero pool cost,
/// mirroring the engine-worker pool discipline (gh-241).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;
late List<String> _lines;
late List<String> _errorLines;
late _SeamConfluencePool _pool;
late CliDispatcher _dispatcher;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_cli_conf_pool_');
    PropertyReader.setOverrides({});
    _lines = [];
    _errorLines = [];
    _pool = _SeamConfluencePool();
    _dispatcher = CliDispatcher(
      writer: _lines.add,
      errorWriter: _errorLines.add,
      propertyReader: PropertyReader(basePath: _tmp.path),
      isTty: () => false,
      confluencePool: _pool,
    );
  });
  tearDown(() {
    PropertyReader.clearOverrides();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testDirectToolBoot();
  _testJobRunBoot();
}

/// Confluence credentials without a default space: `confluence_content_by_title`
/// fails fast on the missing space — after the pool boot, with no HTTP.
Map<String, String> _configured() => {
      'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:9',
      'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
      'CONFLUENCE_AUTH_TYPE': 'Basic',
    };

void _testDirectToolBoot() {
  group('direct tool dispatch: lazy Confluence pool boot', () {
    test('a confluence_* tool boots the pool before dispatch', () async {
      PropertyReader.setOverrides(_configured());
      final code = await _dispatcher
          .dispatch(const ['confluence_content_by_title', 'title=x']);
      expect(code, 1); // Default space not set — fails after the boot.
      expect(_lines.last, contains('Default space not set'));
      expect(_pool.booted, 1);
    });

    test('a non-confluence tool never boots the pool', () async {
      PropertyReader.setOverrides(_configured());
      final code = await _dispatcher
          .dispatch(const ['file_read', 'path=/definitely/missing.file']);
      expect(code, 1);
      expect(_pool.booted, 0);
    });

    test('unconfigured confluence tools never boot the pool', () async {
      final code = await _dispatcher
          .dispatch(const ['confluence_content_by_title', 'title=x']);
      expect(code, 1); // Confluence not configured — before any pool use.
      expect(_lines.last, contains('Confluence not configured'));
      expect(_pool.booted, 0);
    });

    test('builtin commands never boot the pool', () async {
      expect(await _dispatcher.dispatch(const ['--version']), 0);
      expect(await _dispatcher.dispatch(const ['--help']), 0);
      expect(_pool.booted, 0);
    });
  });
}

void _testJobRunBoot() {
  group('job runs: lazy Confluence pool boot', () {
    test('a run with Confluence configured boots the pool first', () async {
      PropertyReader.setOverrides(_configured());
      expect(await _runProbeJob(), 0);
      expect(_lines.last, '"ok"');
      expect(_pool.booted, 1);
    });

    test('a run without Confluence config never boots the pool', () async {
      expect(await _runProbeJob(), 0);
      expect(_lines.last, '"ok"');
      expect(_pool.booted, 0);
    });
  });

  group('job runs: Confluence pool boot failure', () {
    test('a failed boot degrades to the inline sequential fallback', () async {
      PropertyReader.setOverrides(_configured());
      _pool.failBoot = true;
      expect(await _runProbeJob(), 0);
      expect(_lines.last, '"ok"');
      expect(_errorLines, hasLength(1));
      expect(_errorLines.single, contains('Confluence worker pool boot'));
    });
  });
}

/// Writes a trivial jsrunner script + job config and dispatches `run`.
Future<int> _runProbeJob() {
  final script = File('${_tmp.path}/conf_pool_probe.js')
    ..writeAsStringSync('function action(params) { return "ok"; }');
  final config = File('${_tmp.path}/conf_pool_job.json')
    ..writeAsStringSync(jsonEncode({
      'name': 'jsrunner',
      'params': {'jsPath': script.path},
    }));
  return _dispatcher.dispatch(['run', config.path]);
}

/// Recording seam over the real pool type: counts boots, optionally fails.
class _SeamConfluencePool extends SyncWorkerPool {
  _SeamConfluencePool() : super(_seamWorkerEntry, name: 'seam', workerCount: 1);

  var booted = 0;
  var failBoot = false;

  @override
  bool get ready => booted > 0;

  @override
  Future<void> boot() async {
    if (failBoot) throw StateError('isolate quota exhausted');
    booted++;
  }
}

/// Top-level seam entry (never spawned — the seam boots without workers).
Future<void> _seamWorkerEntry(SyncWorkerBoot boot) async {}
