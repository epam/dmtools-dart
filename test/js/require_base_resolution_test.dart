import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/cli/run_command_processor.dart';
import 'package:dmtools/src/js/async_job_pool.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// gh-409: relative `require` must resolve against the requiring module's
/// directory (sync + async-pool dispatch), and config action paths must
/// resolve against the config file's directory with a CWD fallback.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dmtools_gh409');
    _seedTree(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('AC1 sync: module require resolves against its own directory', () {
    _expectSyncResolves(tmp.path);
  });

  test('AC1 negative: genuinely missing target still fails cleanly', () {
    _expectMissingFails(tmp.path);
  });

  test(
    'AC1/AC2 async: dispatched fn resolves its declaring module dir',
    () async {
      await _expectAsyncResolves(
        tmp.path,
        'dispatch',
        'asyncEntry',
        runAll: false,
      );
    },
  );

  test(
    'AC1 async: runAsync.all-aggregated dispatch resolves declaring module dir',
    () async {
      await _expectAsyncResolves(
        tmp.path,
        'dispatchAll',
        'asyncEntryAll',
        runAll: true,
      );
    },
  );

  group('AC3 config action paths', () {
    test('rebased to the config directory and runs from another CWD', () {
      _expectConfigRebased(tmp.path);
    });

    test('falls back to CWD-relative path when absent from config dir', () {
      _expectConfigFallback(tmp.path);
    });
  });
}

/// Upstream-style tree: a/js/m.js requires ./common/t.js (only in a/js).
/// The entry lives in a sibling tree so entry-dir probing would fail.
void _seedTree(String root) {
  _write('$root/a/js/m.js', """
var t = require('./common/t.js');
module.exports.run = function (params) { return { value: t.value }; };
""");
  _write(
    '$root/a/js/common/t.js',
    "module.exports = { value: 'trackers-ok' };",
  );
  _write('$root/b/js/entry.js', """
var m = require('../../a/js/m.js');
function action(params) { return m.run(params); }
""");
}

void _expectSyncResolves(String root) {
  final out = const JsJobRunner().runScript(
    scriptPath: '$root/b/js/entry.js',
    jobParams: const {},
  );
  expect(jsonDecode(out!), {'value': 'trackers-ok'});
}

void _expectMissingFails(String root) {
  _write('$root/a/js/bad.js', """
function action(params) { require('./nope/missing.js'); return 1; }
""");
  expect(
    () => const JsJobRunner().runScript(
      scriptPath: '$root/a/js/bad.js',
      jobParams: const {},
    ),
    throwsA(
      predicate(
        (e) => e.toString().contains(
          'Failed to require module: ./nope/missing.js',
        ),
      ),
    ),
  );
}

/// Dispatches a function declared in `a/js/<dispatchName>.js` through the
/// async pool, aggregating via `runAsync.all` when [runAll] is set.
Future<void> _expectAsyncResolves(
  String root,
  String dispatchName,
  String entryName, {
  required bool runAll,
}) async {
  final call = runAll
      ? 'return runAsync.all([job]).wait()[0];'
      : 'return job.wait();';
  _write('$root/a/js/$dispatchName.js', """
module.exports.run = function (params) {
  var job = runAsync(function (x) {
    var inner = require('./common/t.js');
    return inner.value + ':' + x;
  }, 7);
  $call
};
""");
  _write('$root/b/js/$entryName.js', """
var d = require('../../a/js/$dispatchName.js');
function action(params) { return d.run(params); }
""");
  final pool = AsyncJobPool(workers: 2);
  await pool.boot();
  try {
    final out = const JsJobRunner().runScript(
      scriptPath: '$root/b/js/$entryName.js',
      jobParams: const {'parallelWorkers': 2},
      config: JsRunConfig(pool: pool),
    );
    expect(jsonDecode(out!), 'trackers-ok:7');
  } finally {
    pool.dispose();
  }
}

void _expectConfigRebased(String root) {
  final cfgDir = Directory('$root/cfg')..createSync();
  _write('${cfgDir.path}/hooks/pre.js', 'function action(p){return 1;}');
  final cfgFile = File('${cfgDir.path}/agent.json')
    ..writeAsStringSync(
      jsonEncode({'preJSAction': 'hooks/pre.js', 'thenAction': 'hooks/pre.js'}),
    );
  final out = jsonDecode(
    const RunCommandProcessor().process(['run', cfgFile.path]),
  ) as Map<String, dynamic>;
  expect(out['preJSAction'], p.join(cfgDir.path, 'hooks/pre.js'));
  expect(out['thenAction'], p.join(cfgDir.path, 'hooks/pre.js'));
}

void _expectConfigFallback(String root) {
  final cfgDir = Directory('$root/cfg2')..createSync();
  final cfgFile = File('${cfgDir.path}/agent.json')
    ..writeAsStringSync(jsonEncode({'postJSAction': 'only-in-cwd.js'}));
  final out = jsonDecode(
    const RunCommandProcessor().process(['run', cfgFile.path]),
  ) as Map<String, dynamic>;
  expect(out['postJSAction'], 'only-in-cwd.js');
}

void _write(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}
