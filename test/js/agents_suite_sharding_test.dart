import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/agents_suite.dart';
import 'package:test/test.dart';

void main() {
  resolveShardCountTests();
  chunkCountForTests();
  planChunksTests();
  primePreludeJsTests();
  invocationsForTests();
  copyAgentTreeTests();
  copyAgentTreeGitRefTests();
  rebaseTests();
  shardOutcomeTests();
  agentsSuiteReportTests();
  agentsSuiteReportFailureTests();
  runChunkQueueTests();
}

void resolveShardCountTests() {
  group('resolveShardCount', () {
    test('env override wins when a positive integer', () {
      expect(resolveShardCount('3', processors: 10), 3);
      expect(resolveShardCount(' 16 ', processors: 4), 16);
    });

    test('garbage, zero and negative overrides fall back to the auto value',
        () {
      expect(resolveShardCount(null, processors: 4), 4);
      expect(resolveShardCount('', processors: 4), 4);
      expect(resolveShardCount('yes', processors: 4), 4);
      expect(resolveShardCount('0', processors: 4), 4);
      expect(resolveShardCount('-4', processors: 4), 4);
    });

    test('auto value caps at 8 and floors at 1', () {
      expect(resolveShardCount(null, processors: 64), 8);
      expect(resolveShardCount(null, processors: 4), 4);
      expect(resolveShardCount(null, processors: 1), 1);
      expect(resolveShardCount(null, processors: 0), 1);
      expect(resolveShardCount(null, processors: -2), 1);
    });
  });
}

void chunkCountForTests() {
  group('chunkCountFor', () {
    test('scales with workers but never exceeds the file count', () {
      expect(chunkCountFor(94, 8), 94);
      expect(chunkCountFor(200, 8), 96);
      expect(chunkCountFor(10, 1), 10);
    });

    test('floors at one chunk for degenerate inputs', () {
      expect(chunkCountFor(0, 8), 0);
      expect(chunkCountFor(5, 0), 5);
      expect(chunkCountFor(5, -3), 5);
    });
  });
}

void planChunksTests() {
  group('planChunks', () {
    test('empty input plans no chunks', () {
      expect(planChunks(const [], 4, (_) => 1), isEmpty);
    });

    test('chunk count below one yields a single all-counted chunk', () {
      final chunks = planChunks(['a', 'b', 'c'], 0, (_) => 1);
      expect(chunks, hasLength(1));
      expect(chunks[0].primeFiles, isEmpty);
      expect(chunks[0].countedFiles, ['a', 'b', 'c']);
    });

    test('chunk count above the file count yields one file per chunk', () {
      final chunks = planChunks(['a', 'b'], 8, (_) => 1);
      expect(chunks.map((c) => c.countedFiles), [
        ['a'],
        ['b'],
      ]);
    });

    test('chunks are contiguous, ordered and cover every file exactly once',
        () {
      final files = List.generate(20, (i) => 'f$i.js');
      final chunks = planChunks(files, 6, (f) => 1);
      expect(chunks, hasLength(6));
      final counted = [for (final c in chunks) ...c.countedFiles];
      expect(counted, files); // order + coverage + no duplicates lost
      // Each chunk's prime prefix is exactly the counted files of all
      // earlier chunks (contiguity — what makes priming serial-exact).
      var prefix = <String>[];
      for (final c in chunks) {
        expect(c.primeFiles, prefix);
        expect(c.countedFiles, isNotEmpty);
        prefix = [...prefix, ...c.countedFiles];
      }
    });

    test('is deterministic for identical input', () {
      final files = List.generate(10, (i) => 'f$i.js');
      final a = planChunks(files, 4, (f) => f.length);
      final b = planChunks(files, 4, (f) => f.length);
      expect(a.map((c) => c.countedFiles), b.map((c) => c.countedFiles));
    });

    test('weights move boundaries toward equal weight shares', () {
      // One heavy file then nine tiny ones: the first chunk must be the
      // heavy file alone, later chunks split the tiny tail.
      final files = ['heavy.js', ...List.generate(9, (i) => 't$i.js')];
      final chunks =
          planChunks(files, 5, (f) => f.startsWith('heavy') ? 100 : 1);
      expect(chunks.first.countedFiles, ['heavy.js']);
      expect(chunks.first.primeFiles, isEmpty);
      final tail = [for (final c in chunks.skip(1)) ...c.countedFiles];
      expect(tail, files.skip(1).toList());
    });
  });
}

void primePreludeJsTests() {
  group('primePreludeJs', () {
    test('embeds the suite file list and prime count', () {
      final js = primePreludeJs(['a.js', 'b.js'], 1);
      expect(js, contains(jsonEncode(['a.js', 'b.js'])));
      expect(js, contains('var primeCount = 1;'));
      expect(js, contains('if (seen > primeCount) restore();'));
    });
  });
}

void invocationsForTests() {
  group('invocationsFor', () {
    test('composes testFiles as prime + counted and keeps other jobParams', () {
      final config = AgentsSuiteConfig(
        jsPath: 'js/unit-tests/testRunner.js',
        jobParams: {
          'testFiles': ['a.js', 'b.js'],
          'ticket': 'TS-1'
        },
        testFiles: ['a.js', 'b.js'],
      );
      const chunks = [
        ShardChunk(primeFiles: [], countedFiles: ['a.js']),
        ShardChunk(primeFiles: ['a.js'], countedFiles: ['b.js']),
      ];
      final invocations = invocationsFor(
        agentsPath: '/agents',
        config: config,
        chunks: chunks,
      );
      expect(invocations, hasLength(2));
      expect(invocations[0].jobParams['testFiles'], ['a.js']);
      expect(invocations[1].jobParams['testFiles'], ['a.js', 'b.js']);
      expect(invocations[1].jobParams['ticket'], 'TS-1');
      expect(invocations[1].scriptPath, '/agents/js/unit-tests/testRunner.js');
      expect(invocations[1].workingDirectory, '/agents');
      expect(invocations[1].total, 2);
      expect(invocations[1].index, 1);
      expect(
        invocations[1].preludeCode,
        primePreludeJs(['a.js', 'b.js'], 1),
      );
    });
  });
}

void copyAgentTreeTests() {
  group('copyAgentTree', () {
    test(
        'copies files and nested dirs; .git becomes an absolute gitfile '
        'ref; .dart_tool/symlinks skipped', () async {
      final src = await Directory.systemTemp.createTemp('copy-src-');
      final dst = await Directory.systemTemp.createTemp('copy-dst-');
      addTearDown(() async {
        await src.delete(recursive: true);
        await dst.delete(recursive: true);
      });
      File('${src.path}/run_all.json').writeAsStringSync('{}');
      File('${src.path}/js/a.js').createSync(recursive: true);
      File('${src.path}/js/unit/b.js').createSync(recursive: true);
      Directory('${src.path}/.git/objects').createSync(recursive: true);
      File('${src.path}/.git/HEAD').writeAsStringSync('ref');
      Directory('${src.path}/.dart_tool/pkg').createSync(recursive: true);
      Link('${src.path}/js/link.js').createSync('${src.path}/js/a.js');

      copyAgentTree(src.path, dst.path);

      expect(File('${dst.path}/run_all.json').readAsStringSync(), '{}');
      expect(File('${dst.path}/js/a.js').existsSync(), isTrue);
      expect(File('${dst.path}/js/unit/b.js').existsSync(), isTrue);
      // .git is a one-line redirect to the original metadata, not a copy.
      final gitRef = File('${dst.path}/.git');
      expect(gitRef.existsSync(), isTrue);
      expect(gitRef.readAsStringSync(), 'gitdir: ${src.path}/.git\n');
      expect(Directory('${dst.path}/.git').existsSync(), isFalse);
      expect(Directory('${dst.path}/.dart_tool').existsSync(), isFalse);
      expect(File('${dst.path}/js/link.js').existsSync(), isFalse);
    });

    test('empty source directory copies as an empty tree', () async {
      final src = await Directory.systemTemp.createTemp('copy-empty-');
      final dst = await Directory.systemTemp.createTemp('copy-empty-dst-');
      addTearDown(() async {
        await src.delete(recursive: true);
        await dst.delete(recursive: true);
      });
      copyAgentTree(src.path, dst.path);
      expect(Directory(dst.path).listSync(), isEmpty);
    });
  });
}

void copyAgentTreeGitRefTests() {
  group('copyAgentTree git refs', () {
    test('resolves a relative submodule gitfile to an absolute gitdir',
        () async {
      final src = await Directory.systemTemp.createTemp('copy-sub-');
      final dst = await Directory.systemTemp.createTemp('copy-sub-dst-');
      addTearDown(() async {
        await src.delete(recursive: true);
        await dst.delete(recursive: true);
      });
      File('${src.path}/.git')
          .writeAsStringSync('gitdir: ../.git/modules/agents\n');

      copyAgentTree(src.path, dst.path);

      expect(
        File('${dst.path}/.git').readAsStringSync(),
        'gitdir: ${src.path}/../.git/modules/agents\n',
      );
    });
  });
}

void rebaseTests() {
  group('rebasePath', () {
    test('re-bases the root itself and everything under it', () {
      expect(rebasePath('/a/agents', '/a/agents', '/tmp/c'), '/tmp/c');
      expect(
        rebasePath('/a/agents/js/x.js', '/a/agents', '/tmp/c'),
        '/tmp/c/js/x.js',
      );
    });

    test('leaves unrelated and sibling-prefix paths alone', () {
      expect(rebasePath('/a/agents-x/js', '/a/agents', '/tmp/c'), isNull);
      expect(rebasePath('js/relative.js', '/a/agents', '/tmp/c'), isNull);
      expect(rebasePath('/elsewhere/x', '/a/agents', '/tmp/c'), isNull);
    });
  });

  group('rebaseJobParams', () {
    test('re-bases absolute strings nested in maps and lists', () {
      final params = <String, dynamic>{
        'jsPath': 'js/unit-tests/testRunner.js',
        'root': '/a/agents',
        'cfg': {
          'path': '/a/agents/configs/c.json',
          'other': '/keep/me',
          'list': ['/a/agents/x', 'rel.js', 7],
        },
      };
      final out = rebaseJobParams(params, '/a/agents', '/tmp/c');
      expect(out['jsPath'], 'js/unit-tests/testRunner.js');
      expect(out['root'], '/tmp/c');
      expect(out['cfg']['path'], '/tmp/c/configs/c.json');
      expect(out['cfg']['other'], '/keep/me');
      expect(out['cfg']['list'], ['/tmp/c/x', 'rel.js', 7]);
    });
  });
}

void shardOutcomeTests() {
  group('ShardOutcome', () {
    test('parses well-formed results', () {
      const outcome = ShardOutcome(
        index: 0,
        result: '{"success":true,"passed":12,"failed":0}',
      );
      expect(outcome.malformed, isFalse);
      expect(outcome.passed, 12);
      expect(outcome.failed, 0);
    });

    test(
        'null, non-object, invalid-JSON and non-integer results are '
        'malformed', () {
      expect(const ShardOutcome.crashed(0, 'boom').malformed, isTrue);
      expect(const ShardOutcome(index: 0, result: '"just a string"').malformed,
          isTrue);
      expect(const ShardOutcome(index: 0, result: 'garbage').malformed, isTrue);
      expect(
        const ShardOutcome(index: 0, result: '{"passed":"12","failed":0}')
            .malformed,
        isTrue,
      );
      // Crash outcomes contribute no counts.
      expect(const ShardOutcome.crashed(0, 'boom').passed, 0);
      expect(const ShardOutcome.crashed(0, 'boom').failed, 0);
    });
  });
}

ShardOutcome _ok(int index, int passed) => ShardOutcome(
      index: index,
      result: '{"success":true,"passed":$passed,"failed":0}',
    );

void agentsSuiteReportTests() {
  group('AgentsSuiteReport', () {
    test('sums green shards into a green report with exit code 0', () {
      final report = AgentsSuiteReport.fromShards([_ok(0, 10), _ok(1, 15)]);
      expect(report.success, isTrue);
      expect(report.passed, 25);
      expect(report.failed, 0);
      expect(report.exitCode, 0);
    });

    test('a red shard fails the run but keeps the sums', () {
      final red = ShardOutcome(
        index: 1,
        result: '{"success":false,"passed":7,"failed":4}',
      );
      final report = AgentsSuiteReport.fromShards([_ok(0, 10), red]);
      expect(report.success, isFalse);
      expect(report.passed, 17);
      expect(report.failed, 4);
      expect(report.exitCode, 1);
    });

    test('toJson keeps the serial Result: shape', () {
      final report = AgentsSuiteReport.fromShards([_ok(0, 10)]);
      expect(jsonEncode(report.toJson()),
          '{"success":true,"passed":10,"failed":0}');
    });
  });
}

void agentsSuiteReportFailureTests() {
  group('AgentsSuiteReport failures', () {
    test('one malformed shard fails the whole run', () {
      final report = AgentsSuiteReport.fromShards(
        [_ok(0, 10), const ShardOutcome(index: 1, result: 'garbage')],
      );
      expect(report.success, isFalse);
      expect(report.malformedShards, [1]);
      expect(report.exitCode, 1);
    });

    test('one crashed shard fails the whole run', () {
      final report = AgentsSuiteReport.fromShards(
        [_ok(0, 10), const ShardOutcome.crashed(1, 'isolate died')],
      );
      expect(report.success, isFalse);
      expect(report.crashedShards, [1]);
      expect(report.exitCode, 1);
    });

    test('zero total passes never reports success', () {
      final report = AgentsSuiteReport.fromShards([_ok(0, 0)]);
      expect(report.success, isFalse);
      expect(report.exitCode, 1);
      expect(AgentsSuiteReport.fromShards([]).success, isFalse);
    });
  });

  group('diagnostics helpers', () {
    test('shardDiagnostics describes crashed and malformed chunks', () {
      const outcomes = [
        ShardOutcome(index: 0, result: '{"passed":1,"failed":0}'),
        ShardOutcome.crashed(1, 'isolate died'),
        ShardOutcome(index: 2, result: 'garbage'),
      ];
      final text = shardDiagnostics(outcomes);
      expect(text, contains('Chunk 2 crashed: isolate died'));
      expect(text, contains('Chunk 3 returned a malformed result: garbage'));
      expect(text.endsWith('\n'), isTrue);
    });

    test('shardDiagnostics is empty for well-formed chunks', () {
      const outcomes = [
        ShardOutcome(index: 0, result: '{"passed":1,"failed":2}'),
      ];
      expect(shardDiagnostics(outcomes), '');
    });

    test('failureSummary carries the totals', () {
      final report = AgentsSuiteReport.fromShards(
        [const ShardOutcome.crashed(0, 'boom')],
      );
      expect(
        failureSummary(report),
        '0 passed, 0 failed, 1 crashed, 0 malformed chunks.',
      );
    });
  });
}

ShardInvocation _invocation(int index, int total) => ShardInvocation(
      index: index,
      total: total,
      scriptPath: 's.js',
      jobParams: const {},
      workingDirectory: '.',
      preludeCode: '',
    );

void runChunkQueueTests() {
  group('runChunkQueue', () {
    test('returns outcomes in chunk order regardless of completion order',
        () async {
      final chunks = List.generate(4, (i) => _invocation(i, 4));
      // Later chunks finish first (reverse delays).
      final outcomes = await runChunkQueue(chunks, (chunk) async {
        await Future<void>.delayed(
          Duration(milliseconds: 40 * (4 - chunk.index)),
        );
        return ShardOutcome(
          index: chunk.index,
          result: '{"success":true,"passed":${chunk.index},"failed":0}',
        );
      }, concurrency: 4);
      expect([for (final o in outcomes) o.index], [0, 1, 2, 3]);
      expect([for (final o in outcomes) o.passed], [0, 1, 2, 3]);
    });

    test('never runs more chunks concurrently than the limit', () async {
      var inFlight = 0;
      var peak = 0;
      final chunks = List.generate(6, (i) => _invocation(i, 6));
      await runChunkQueue(chunks, (chunk) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight--;
        return ShardOutcome(
          index: chunk.index,
          result: '{"passed":1,"failed":0}',
        );
      }, concurrency: 2);
      expect(peak, 2);
    });

    test('concurrency below one runs serially and still finishes', () async {
      var inFlight = 0;
      var peak = 0;
      final chunks = List.generate(3, (i) => _invocation(i, 3));
      final outcomes = await runChunkQueue(chunks, (chunk) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return ShardOutcome(
          index: chunk.index,
          result: '{"passed":1,"failed":0}',
        );
      }, concurrency: 0);
      expect(peak, 1);
      expect(outcomes, hasLength(3));
    });
  });
}
