import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/agents/suite_sharding.dart';
import 'package:test/test.dart';

/// gh-315 — runner-level sharding of the agents suite (L4).
///
/// Covers the pure half of the sharding design:
/// - [ShardPlanner] partition exactness (AC1): disjoint shards, union equals
///   the input element-for-element, deterministic, N=1 identity, N > len
///   degrades to empty high shards.
/// - [ShardManifest] schema round-trip and [ShardManifestMerger] outcomes
///   (AC4 test hooks): green manifests, red shard, missing file, duplicated
///   file, malformed JSON, shard-count defects — each mapped to a problem.
void main() {
  _plannerPartitionTests();
  _plannerEdgeTests();
  _plannerRealListTests();
  _manifestSchemaTests();
  _mergerGreenTests();
  _mergerDefectTests();
  _mergerPartitionDefectTests();
  _mergerSchemaTests();
}

/// Canonical expected file list for the merge fixtures.
const List<String> mergeFixtureFiles = ['a.js', 'b.js', 'c.js', 'd.js'];

/// Encodes fixture manifests as raw JSON payloads (the artifact form the
/// gate downloads).
List<String> manifestJsons(List<ShardManifest> manifests) =>
    [for (final m in manifests) jsonEncode(m.toJson())];

/// A fully-green manifest covering [planned].
ShardManifest green(
  int shard,
  int total,
  List<String> planned, {
  int passed = 1,
}) =>
    ShardManifest(
      shard: shard,
      total: total,
      plannedFiles: planned,
      success: true,
      passed: passed,
      failed: 0,
    );

List<String> _synthetic(int count) => [
      for (var i = 0; i < count; i++) 'js/unit-tests/test_file$i.js',
    ];

void _plannerPartitionTests() {
  group('ShardPlanner.split (AC1) — partition properties', () {
    test('N=1 reproduces the original list unchanged', () {
      final files = ['b.js', 'a.js', 'c.js'];
      expect(ShardPlanner.split(files, 0, 1), files);
    });

    test('split is deterministic (same input ⇒ same output)', () {
      final files = _synthetic(37);
      for (var n = 1; n <= 5; n++) {
        for (var i = 0; i < n; i++) {
          expect(
            ShardPlanner.split(files, i, n),
            ShardPlanner.split(files, i, n),
            reason: 'shard $i/$n must be a pure function of its inputs',
          );
        }
      }
    });

    test('shards are disjoint and their union equals the input', () {
      for (final len in [0, 1, 2, 3, 7, 92, 200]) {
        final files = _synthetic(len);
        for (var n = 1; n <= len + 3; n++) {
          final union = [
            for (var i = 0; i < n; i++) ...ShardPlanner.split(files, i, n),
          ]..sort();
          expect(union, [...files]..sort(),
              reason: 'len=$len n=$n: union of shards must equal the input');
        }
      }
    });

    test('every file lands in exactly one shard (pos % N assignment)', () {
      final files = _synthetic(10);
      for (var pos = 0; pos < files.length; pos++) {
        final home = pos % 4;
        for (var i = 0; i < 4; i++) {
          expect(
              ShardPlanner.split(files, i, 4).contains(files[pos]), i == home,
              reason: '${files[pos]} must live in shard $home, not $i');
        }
      }
    });

    test('order is stable inside each shard', () {
      final files = _synthetic(12);
      final shard0 = ShardPlanner.split(files, 0, 3);
      expect(shard0, [
        for (var pos = 0; pos < files.length; pos++)
          if (pos % 3 == 0) files[pos],
      ]);
    });

    test('empty input: every shard is empty, N=1 is an identity', () {
      expect(ShardPlanner.split(const [], 0, 1), isEmpty);
      expect(ShardPlanner.split(const [], 0, 4), isEmpty);
    });
  });
}

void _plannerEdgeTests() {
  group('ShardPlanner.split (AC1) — edge shapes', () {
    test('N greater than the file count yields empty high shards', () {
      final files = _synthetic(2);
      expect(ShardPlanner.split(files, 0, 5), hasLength(1));
      expect(ShardPlanner.split(files, 1, 5), hasLength(1));
      expect(ShardPlanner.split(files, 2, 5), isEmpty);
      expect(ShardPlanner.split(files, 4, 5), isEmpty);
    });

    test('round-robin balances the file count across shards', () {
      final files = _synthetic(92);
      final sizes = [
        for (var i = 0; i < 4; i++) ShardPlanner.split(files, i, 4).length,
      ];
      expect(sizes, everyElement(23));
    });
  });
}

void _plannerRealListTests() {
  group('ShardPlanner.split (AC1) — the real run_all.json list', () {
    List<String>? realFiles() {
      const runAllPath = 'agents/js/unit-tests/run_all.json';
      if (!File(runAllPath).existsSync()) return null;
      final config = jsonDecode(File(runAllPath).readAsStringSync()) as Map;
      final jobParams = (config['params'] as Map)['jobParams'] as Map;
      return [for (final f in jobParams['testFiles'] as List) f as String];
    }

    test('partitions exactly (92 entries, N=4)', () {
      final testFiles = realFiles();
      if (testFiles == null) {
        return; // Submodule not checked out — synthetic cases cover the rest.
      }
      expect(testFiles, hasLength(92));
      final shards = [
        for (var i = 0; i < 4; i++) ShardPlanner.split(testFiles, i, 4),
      ];
      final union = [for (final s in shards) ...s];
      // Positional coverage: every input entry (including the upstream
      // duplicate of test_postPRReviewComments.js) lands in exactly one
      // shard — multiset equality, not per-filename uniqueness.
      expect(union.length, testFiles.length,
          reason: 'no file may be lost or duplicated by the split');
      expect([...union]..sort(), [...testFiles]..sort());
      expect(shards.map((s) => s.length), everyElement(23));
    });

    test('split accepts every N in {1..len+}', () {
      final testFiles = realFiles();
      if (testFiles == null) return;
      for (final n in [1, 2, 3, 4, 5, 23, 46, 92, 93, 100]) {
        final union = [
          for (var i = 0; i < n; i++) ...ShardPlanner.split(testFiles, i, n),
        ]..sort();
        expect(union, [...testFiles]..sort(),
            reason: 'N=$n must preserve the multiset of files');
      }
    });
  });
}

void _manifestSchemaTests() {
  group('ShardManifest schema', () {
    test('toJson/fromJson round-trip', () {
      const manifest = ShardManifest(
        shard: 2,
        total: 4,
        plannedFiles: ['js/unit-tests/test_a.js', 'js/unit-tests/test_b.js'],
        success: true,
        passed: 11,
        failed: 0,
      );
      final decoded = ShardManifest.fromJson(
        jsonDecode(jsonEncode(manifest.toJson())) as Map,
      );
      expect(decoded, manifest);
    });

    test('fromJson rejects a missing key', () {
      expect(
        () => ShardManifest.fromJson({
          'shard': 0,
          'total': 2,
          'plannedFiles': <String>[],
          'success': true,
          'passed': 1,
          // failed missing
        }),
        throwsA(isA<ShardManifestException>()),
      );
    });

    test('fromJson rejects a wrong-typed value', () {
      expect(
        () => ShardManifest.fromJson({
          'shard': 'zero',
          'total': 2,
          'plannedFiles': <String>[],
          'success': true,
          'passed': 1,
          'failed': 0,
        }),
        throwsA(isA<ShardManifestException>()),
      );
    });
  });
}

void _mergerGreenTests() {
  group('ShardManifestMerger.merge — green paths (AC4)', () {
    test('green manifests with an exact partition merge ok', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 2, ['a.js', 'c.js'], passed: 7),
          green(1, 2, ['b.js', 'd.js'], passed: 9),
        ]),
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isTrue, reason: 'problems: ${result.problems}');
      expect(result.passedTotal, 16);
      expect(result.failedTotal, 0);
    });

    test('upstream-duplicated expected files still merge ok (multiset)', () {
      // run_all.json currently carries test_postPRReviewComments.js twice;
      // the partition check is a multiset comparison, so the duplicate is
      // expected twice across shards — and red only if covered once.
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 2, ['a.js', 'dup.js']),
          green(1, 2, ['dup.js', 'b.js']),
        ]),
        expectedFiles: ['a.js', 'dup.js', 'dup.js', 'b.js'],
      );
      expect(result.ok, isTrue, reason: 'problems: ${result.problems}');
    });
  });
}

void _mergerDefectTests() {
  group('ShardManifestMerger.merge — defect outcomes (AC4)', () {
    test('a red shard fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: [
          jsonEncode(green(0, 2, ['a.js', 'b.js']).toJson()),
          jsonEncode(
            const ShardManifest(
              shard: 1,
              total: 2,
              plannedFiles: ['c.js', 'd.js'],
              success: false,
              passed: 1,
              failed: 2,
            ).toJson(),
          ),
        ],
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems, hasLength(1));
      expect(result.problems.single, contains('shard 1'));
      expect(result.failedTotal, 2);
    });

    test('failed > 0 on an allegedly green shard fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: [
          jsonEncode(
            const ShardManifest(
              shard: 0,
              total: 1,
              plannedFiles: mergeFixtureFiles,
              success: true,
              passed: 5,
              failed: 3,
            ).toJson(),
          ),
        ],
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.single, contains('failed=3'));
    });

    test('a missing planned file fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 2, ['a.js', 'b.js']),
          green(1, 2, ['c.js']), // d.js dropped — silent-skip shape
        ]),
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('d.js'));
      expect(result.problems.join('\n'), contains('missing'));
    });
  });
}

void _mergerPartitionDefectTests() {
  group('ShardManifestMerger.merge — partition defects (AC4)', () {
    test('a duplicated planned file fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 2, ['a.js', 'b.js', 'a.js']),
          green(1, 2, ['c.js', 'd.js']),
        ]),
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('a.js'));
      expect(result.problems.join('\n'), contains('duplicate'));
    });
  });
}

void _mergerPartitionDefectTests() {
  group('ShardManifestMerger.merge — unexpected-file defect (AC4)', () {
    test('an unexpected file (not in run_all.json) fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 1, ['a.js', 'b.js', 'c.js', 'd.js', 'rogue.js']),
        ]),
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('rogue.js'));
    });
  });
}

void _mergerSchemaTests() {
  group('ShardManifestMerger.merge — manifest-count defects (AC4)', () {
    test('malformed JSON maps to a problem, not a crash', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: ['{not json'],
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems, hasLength(1));
      expect(result.problems.single, contains('parse'));
    });

    test('fewer manifests than total fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 2, mergeFixtureFiles),
        ]),
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('shard 1'));
    });

    test('duplicate shard index fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: manifestJsons([
          green(0, 2, ['a.js', 'b.js']),
          green(0, 2, ['c.js', 'd.js']),
        ]),
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('twice'));
    });

    test('shards disagreeing on total fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: [
          jsonEncode(green(0, 2, ['a.js', 'b.js']).toJson()),
          jsonEncode(green(1, 4, ['c.js', 'd.js']).toJson()),
        ],
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('total'));
    });

    test('an empty manifest list fails the merge', () {
      final result = ShardManifestMerger.merge(
        manifestJsons: [],
        expectedFiles: mergeFixtureFiles,
      );
      expect(result.ok, isFalse);
      expect(result.problems.join('\n'), contains('no manifests'));
    });
  });
}
