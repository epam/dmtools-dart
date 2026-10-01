import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/agents/suite_shard_args.dart';
import 'package:dmtools/src/agents/suite_shard_parity.dart';
import 'package:dmtools/src/agents/suite_shard_runner.dart';
import 'package:dmtools/src/agents/suite_sharding.dart';
import 'package:test/test.dart';

/// gh-315 — end-to-end IT for the sharded agents-suite runner on a fixture
/// mini-agents tree (temp dir with `run_all.json` + fake test files).
///
/// The fixture's `testRunner.js` implements the upstream action contract
/// (`testFiles` in → `{success, passed, failed}` out, silent skip on empty
/// files) so every scenario runs hermetically — no dmtools-agents checkout,
/// no network. One extra test runs the REAL unmodified `testRunner.js` (AC2's
/// "through the unmodified testRunner.js" clause) when the agents/ submodule
/// is checked out.
///
/// Covered acceptance hooks:
/// - AC2: `--shard-index/--total-shards` run only the planned subset and
///   write a valid manifest; invalid combos exit non-zero with a message.
/// - AC3: a planned file that is missing or empty fails BEFORE the engine.
/// - AC5: the no-flag serial path passes the identical full `testFiles`
///   list through and keeps the exit contract.
/// - AC6: parity-tool smoke test on the fixture tree (serial vs sharded).
void main() {
  late FixtureTree tree;

  setUp(() {
    tree = FixtureTree();
    tree.addTestFile('js/unit-tests/test_a1.js', ok: true);
    tree.addTestFile('js/unit-tests/test_a2.js', ok: true);
    tree.addTestFile('js/unit-tests/test_b1.js', ok: true);
    tree.addTestFile('js/unit-tests/test_b2.js', ok: true);
    tree.writeRunAll();
  });

  tearDown(() => tree.dispose());

  group('sharded run (AC2)', () {
    test('runs only the planned subset and writes a valid manifest', () {
      final manifestPath =
          '${tree.root.path}/out/manifest-0.json';
      final code = runAgentsSuite(
        SuiteShardArgs.parse([
          tree.root.path,
          '--shard-index', '0',
          '--total-shards', '2',
          '--manifest-out', manifestPath,
        ]),
      );

      expect(code, 0, reason: 'green shard must exit 0');
      final manifest = ShardManifest.fromJson(
        jsonDecode(File(manifestPath).readAsStringSync()) as Map,
      );
      expect(manifest.shard, 0);
      expect(manifest.total, 2);
      expect(manifest.success, isTrue);
      expect(manifest.failed, 0);
      // Round-robin over [a1, a2, b1, b2] with N=2: shard 0 = a1, b1.
      expect(manifest.plannedFiles,
          ['js/unit-tests/test_a1.js', 'js/unit-tests/test_b1.js']);
      expect(manifest.passed, 2, reason: 'only the planned subset may run');
    });

    test('shard 1 gets the complement subset', () {
      final manifestPath =
          '${tree.root.path}/out/manifest-1.json';
      final code = runAgentsSuite(
        SuiteShardArgs.parse([
          tree.root.path,
          '--shard-index', '1',
          '--total-shards', '2',
          '--manifest-out', manifestPath,
        ]),
      );

      expect(code, 0);
      final manifest = ShardManifest.fromJson(
        jsonDecode(File(manifestPath).readAsStringSync()) as Map,
      );
      expect(manifest.passed, 2);
      expect(manifest.plannedFiles,
          ['js/unit-tests/test_a2.js', 'js/unit-tests/test_b2.js']);
    });
  });

  group('invalid flag combos exit non-zero before the engine (AC2)', () {
    final bogusJsPath = 'js/unit-tests/does-not-exist.js';

    List<String> argsWith({
      required String jsPath,
      int? shardIndex,
      int? totalShards,
      String? manifestOut,
      List<String> extra = const [],
    }) {
      tree.setJsPath(jsPath);
      return [
        tree.root.path,
        if (shardIndex != null) ...['--shard-index', '$shardIndex'],
        if (totalShards != null) ...['--total-shards', '$totalShards'],
        if (manifestOut != null) ...['--manifest-out', manifestOut],
        ...extra,
      ];
    }

    // The fixture config points at a runner script that does not exist, so
    // if validation DIDN'T reject the args first, the engine start would
    // fail with a "not found" message instead — the message assertions
    // below discriminate the two paths.
    for (final entry in {
      'index >= total': (index: 2, total: 2, message: '--shard-index'),
      'total < 1': (index: 0, total: 0, message: '--total-shards'),
      'negative index': (index: -1, total: 2, message: '--shard-index'),
      'index without total': (index: 0, total: null, message: '--total-shards'),
      'total without index': (index: null, total: 2, message: '--shard-index'),
      'empty planned shard': (index: 4, total: 5, message: 'empty'),
      'missing --manifest-out': (
        index: 0,
        total: 2,
        message: '--manifest-out'
      ),
    }.entries) {
      test('${entry.key} is rejected', () {
        final out = <String>[];
        final code = runAgentsSuite(
          SuiteShardArgs.parse(
            argsWith(
              jsPath: bogusJsPath,
              shardIndex: entry.value.index,
              totalShards: entry.value.total,
              manifestOut: entry.key == 'missing --manifest-out'
                  ? null
                  : '${tree.root.path}/out/manifest.json',
            ),
          ),
          err: out.add,
        );
        expect(code, isNot(0), reason: 'expected rejection, got output: $out');
        expect(out.join('\n'), contains(entry.value.message));
      });
    }

    test('an unknown flag is rejected', () {
      final out = <String>[];
      final code = runAgentsSuite(
        SuiteShardArgs.parse(argsWith(
          jsPath: bogusJsPath,
          shardIndex: 0,
          totalShards: 2,
          manifestOut: '${tree.root.path}/out/manifest.json',
          extra: ['--shard-quota', '9'],
        )),
        err: out.add,
      );
      expect(code, isNot(0));
      expect(out.join('\n'), contains('unknown'));
    });
  });

  group('pre-flight closes the silent-skip hole (AC3)', () {
    test('a planned EMPTY file fails the shard before the engine runs', () {
      tree.addTestFile('js/unit-tests/test_empty.js', ok: true, empty: true);
      tree.setTestFiles([
        'js/unit-tests/test_a1.js',
        'js/unit-tests/test_empty.js',
      ]);
      final manifestPath = '${tree.root.path}/out/manifest.json';
      final out = <String>[];

      final code = runAgentsSuite(
        SuiteShardArgs.parse([
          tree.root.path,
          '--shard-index', '0',
          '--total-shards', '1',
          '--manifest-out', manifestPath,
        ]),
        err: out.add,
      );

      expect(code, isNot(0), reason: 'empty planned file must red the shard');
      expect(out.join('\n'), contains('test_empty.js'));
      final manifest = ShardManifest.fromJson(
        jsonDecode(File(manifestPath).readAsStringSync()) as Map,
      );
      expect(manifest.success, isFalse);
    });

    test('a planned MISSING file fails the shard before the engine runs',
        () {
      tree.setTestFiles(['js/unit-tests/test_ghost.js']);
      final out = <String>[];

      final code = runAgentsSuite(
        SuiteShardArgs.parse([
          tree.root.path,
          '--shard-index', '0',
          '--total-shards', '1',
          '--manifest-out', '${tree.root.path}/out/manifest.json',
        ]),
        err: out.add,
      );

      expect(code, isNot(0));
      expect(out.join('\n'), contains('test_ghost.js'));
    });

    test('the serial path also fails on a missing file (strictly stricter)',
        () {
      tree.setTestFiles(['js/unit-tests/test_ghost.js']);
      final out = <String>[];

      final code = runAgentsSuite(
        SuiteShardArgs.parse([tree.root.path]),
        err: out.add,
      );

      expect(code, isNot(0));
      expect(out.join('\n'), contains('test_ghost.js'));
    });
  });

  group('serial path (AC5)', () {
    test('passes the identical full testFiles list through and exits 0', () {
      final out = <String>[];
      final code = runAgentsSuite(
        SuiteShardArgs.parse([tree.root.path]),
        out: out.add,
      );

      expect(code, 0);
      // The full list reached the engine: all four files counted as passed.
      expect(out.join('\n'), contains('Agents suite green: 4 passed, 0 failed.'));
      // No manifest on the serial path — sharding is opt-in.
      expect(File('${tree.root.path}/out').existsSync(), isFalse,
          reason: 'serial run must not write shard artifacts');
    });

    test('a red suite keeps the exit contract (non-zero)', () {
      tree.addTestFile('js/unit-tests/test_red.js', ok: false);
      final out = <String>[];

      final code = runAgentsSuite(
        SuiteShardArgs.parse([tree.root.path]),
        err: out.add,
      );

      expect(code, 1);
      expect(out.join('\n'), contains('Agents suite failed'));
    });
  });

  group('sharded run with a failing test file', () {
    test('manifest reports failure and exit code is non-zero', () {
      tree.addTestFile('js/unit-tests/test_red.js', ok: false);
      final manifestPath = '${tree.root.path}/out/manifest.json';
      final out = <String>[];

      final code = runAgentsSuite(
        SuiteShardArgs.parse([
          tree.root.path,
          '--shard-index', '1',
          '--total-shards', '3',
          '--manifest-out', manifestPath,
        ]),
        err: out.add,
      );

      expect(code, 1);
      final manifest = ShardManifest.fromJson(
        jsonDecode(File(manifestPath).readAsStringSync()) as Map,
      );
      // Shard 1 of 3 over [a1, a2, b1, b2, red] = a2, red.
      expect(manifest.plannedFiles,
          ['js/unit-tests/test_a2.js', 'js/unit-tests/test_red.js']);
      expect(manifest.success, isFalse);
      expect(manifest.failed, 1);
    });
  });

  group('the REAL unmodified testRunner.js shards too (AC2)', () {
    test('subset of fixture tests runs green through the real runner', () {
      const agentsPath = 'agents';
      if (!File('$agentsPath/js/unit-tests/testRunner.js').existsSync()) {
        return; // Submodule not checked out.
      }
      final realTree = FixtureTree.fromRealRunner(agentsPath);
      try {
        realTree.addFixtureTestUsingTestApi('js/unit-tests/test_fx_a.js');
        realTree.addFixtureTestUsingTestApi('js/unit-tests/test_fx_b.js');
        realTree.writeRunAll();

        final manifestPath = '${realTree.root.path}/out/manifest.json';
        final code = runAgentsSuite(
          SuiteShardArgs.parse([
            realTree.root.path,
            '--shard-index', '1',
            '--total-shards', '2',
            '--manifest-out', manifestPath,
          ]),
        );

        expect(code, 0);
        final manifest = ShardManifest.fromJson(
          jsonDecode(File(manifestPath).readAsStringSync()) as Map,
        );
        expect(manifest.success, isTrue);
        expect(manifest.plannedFiles, ['js/unit-tests/test_fx_b.js']);
        expect(manifest.passed, 1, reason: 'one fixture test in this shard');
        expect(manifest.failed, 0);
      } finally {
        realTree.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('suite parity tool (AC6)', () {
    test('reports parity on a clean fixture (serial == sharded)', () {
      final report = runShardParity(agentsPath: tree.root.path, totalShards: 2);
      expect(report.ok, isTrue, reason: 'mismatches: ${report.mismatches}');
      expect(report.serialOutcome.passed, 4);
      expect(report.shardOutcomes.map((o) => o.passed), [2, 2]);
    });

    test('flags an order-dependent fixture (outcome differs when split)', () {
      // test_order_b.js throws only when it shares an engine with
      // test_order_a.js — the serial shape. Sharded, both pass: the
      // outcome sets differ and the tool must red the report.
      tree.addTestFile(
        'js/unit-tests/test_order_a.js',
        ok: true,
        content: 'globalThis.__parityCanary = true;',
      );
      tree.addTestFile(
        'js/unit-tests/test_order_b.js',
        ok: true,
        content: 'if (globalThis.__parityCanary) '
            '{ throw new Error("order-dependent: ran after test_order_a.js"); }',
      );
      tree.setTestFiles([
        'js/unit-tests/test_order_a.js',
        'js/unit-tests/test_order_b.js',
      ]);

      final report = runShardParity(agentsPath: tree.root.path, totalShards: 2);
      expect(report.ok, isFalse);
      expect(report.mismatches, isNotEmpty);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// A throwaway mini-agents tree: `js/unit-tests/testRunner.js` (a stand-in
/// implementing the upstream action contract) + `run_all.json` + test files.
class FixtureTree {
  FixtureTree() {
    root.createSync(recursive: true);
    _writeRunnerScript();
  }

  /// Builds the tree around the REAL `testRunner.js` + its base modules
  /// (copied read-only from the checked-out agents/ submodule).
  FixtureTree.fromRealRunner(String agentsPath) {
    root.createSync(recursive: true);
    for (final rel in [
      'js/unit-tests/testRunner.js',
      'js/config.js',
      'js/common/scm.js',
      'js/configLoader.js',
    ]) {
      final src = File('$agentsPath/$rel');
      final dst = File('${root.path}/$rel');
      dst.createSync(recursive: true);
      dst.writeAsStringSync(src.readAsStringSync());
    }
  }

  final Directory root = Directory.systemTemp.createTempSync('agents_fixture_');

  final List<String> _testFiles = [];

  void addTestFile(String relPath, {required bool ok, bool empty = false,
      String? content}) {
    final file = File('${root.path}/$relPath');
    file.createSync(recursive: true);
    if (empty) {
      file.writeAsStringSync('');
    } else {
      file.writeAsStringSync(
          content ?? (ok ? '// passing test file' : 'throw new Error("boom");'));
    }
  }

  /// A fixture test file exercising the REAL testRunner.js global API.
  void addFixtureTestUsingTestApi(String relPath) {
    File('${root.path}/$relPath')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
suite('fixture', function () {
  test('always passes', function () {
    assert.equal(1, 1);
  });
});
''');
  }

  void setTestFiles(List<String> files) => _testFiles
    ..clear()
    ..addAll(files);

  void writeRunAll() {
    if (_testFiles.isEmpty) {
      setTestFiles([
        'js/unit-tests/test_a1.js',
        'js/unit-tests/test_a2.js',
        'js/unit-tests/test_b1.js',
        'js/unit-tests/test_b2.js',
      ]);
    }
    File('${root.path}/js/unit-tests/run_all.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'name': 'JSRunner',
        'params': {
          'jsPath': 'js/unit-tests/testRunner.js',
          'jobParams': {'testFiles': _testFiles},
        },
      }));
  }

  void setJsPath(String jsPath) {
    final configPath = '${root.path}/js/unit-tests/run_all.json';
    if (!File(configPath).existsSync()) {
      writeRunAll();
    }
    final config =
        jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
    (config['params'] as Map<String, dynamic>)['jsPath'] = jsPath;
    File(configPath).writeAsStringSync(jsonEncode(config));
  }

  void _writeRunnerScript() {
    // Minimal stand-in for dmtools-agents testRunner.js — the same
    // action(params) contract: testFiles in, {success, passed, failed} out,
    // silent skip on empty/missing files (the hole the pre-flight closes).
    File('${root.path}/js/unit-tests/testRunner.js')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
function action(params) {
  var p = params.jobParams || params;
  var testFiles = p.testFiles || [];
  var passed = 0, failed = 0;
  for (var i = 0; i < testFiles.length; i++) {
    try {
      var code = file_read({ path: testFiles[i] });
      if (!code || !code.trim()) { continue; }
      eval(code);
      passed++;
    } catch (e) {
      failed++;
    }
  }
  return { success: failed === 0, passed: passed, failed: failed };
}
''');
  }

  void dispose() => root.deleteSync(recursive: true);
}
