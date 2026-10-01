/// gh-315 — runner-level sharding of the agents suite (L4): the pure,
/// IO-free half.
///
/// - [ShardPlanner] — deterministic round-robin split of the suite's test
///   file list (`files[pos]` → shard `pos % N`). Pure: same inputs always
///   produce the same shards; shards are disjoint and their union equals
///   the input element-for-element; `N = 1` reproduces the list unchanged.
/// - [ShardManifest] — the inter-job protocol between a `agents-suite`
///   matrix shard and the `agents-gate` merge job: parsed, never evaled.
/// - [ShardManifestMerger] — the merge assertion: every shard green, and
///   the multiset of planned files equals the canonical `run_all.json`
///   list exactly (a lost or duplicated file is red, not a silent green).
library;

import 'dart:convert';

/// The suite's test-file list split into CI matrix shards.
///
/// Round-robin (`pos % N`) rather than contiguous slices: order stays
/// stable and uneven per-file costs (`test_smAgent.js` alone emits about
/// half the suite's log volume) spread across shards instead of piling
/// into one. No count is hardcoded — everything derives from the
/// `run_all.json` list per run.
class ShardPlanner {
  const ShardPlanner._();

  /// Returns the file subset assigned to [shardIndex] of [totalShards].
  ///
  /// Total for every `N >= 1` and any input list (empty shards for
  /// `shardIndex >= length`); rejecting an empty shard is the runner's
  /// job, not the planner's.
  static List<String> split(
    List<String> files,
    int shardIndex,
    int totalShards,
  ) =>
      [
        for (var pos = 0; pos < files.length; pos++)
          if (pos % totalShards == shardIndex) files[pos],
      ];
}

/// A suite-shard manifest: what one `agents-suite` matrix shard planned
/// and what the unmodified `testRunner.js` reported for it.
///
/// Upstream's own result object (`success`/`passed`/`failed`) is carried
/// verbatim; the merge job sums and verifies. Machine-written JSON from
/// our runner — treated as data by the gate, never evaled.
class ShardManifest {
  /// Creates a manifest.
  const ShardManifest({
    required this.shard,
    required this.total,
    required this.plannedFiles,
    required this.success,
    required this.passed,
    required this.failed,
  });

  /// Zero-based index of this shard.
  final int shard;

  /// Total shard count the shard ran with.
  final int total;

  /// The exact file subset the shard planned to run (pre-flight verified).
  final List<String> plannedFiles;

  /// Upstream result: `success` from `testRunner.js`.
  final bool success;

  /// Upstream result: `passed` test count.
  final int passed;

  /// Upstream result: `failed` test count.
  final int failed;

  /// Decodes a manifest, failing with [ShardManifestException] on any
  /// schema violation (missing key, wrong type) — the gate treats schema
  /// drift as a red defect, not as best-effort data.
  factory ShardManifest.fromJson(Map<dynamic, dynamic> json) {
    return ShardManifest(
      shard: _intOf(json, 'shard'),
      total: _intOf(json, 'total'),
      plannedFiles: _filesOf(json),
      success: _boolOf(json, 'success'),
      passed: _intOf(json, 'passed'),
      failed: _intOf(json, 'failed'),
    );
  }

  /// Encodes the manifest for the artifact upload.
  Map<String, dynamic> toJson() => {
        'shard': shard,
        'total': total,
        'plannedFiles': List<String>.of(plannedFiles),
        'success': success,
        'passed': passed,
        'failed': failed,
      };

  @override
  bool operator ==(Object other) =>
      other is ShardManifest &&
      other.shard == shard &&
      other.total == total &&
      other.success == success &&
      other.passed == passed &&
      other.failed == failed &&
      _listEquals(other.plannedFiles, plannedFiles);

  @override
  int get hashCode => Object.hash(shard, total, success, passed, failed);

  static int _intOf(Map<dynamic, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw ShardManifestException('manifest field "$key" must be an int');
  }

  static bool _boolOf(Map<dynamic, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    throw ShardManifestException('manifest field "$key" must be a bool');
  }

  static List<String> _filesOf(Map<dynamic, dynamic> json) {
    final value = json['plannedFiles'];
    if (value is List && value.every((e) => e is String)) {
      return [for (final e in value) e as String];
    }
    throw ShardManifestException(
      'manifest field "plannedFiles" must be a list of strings',
    );
  }

  static bool _listEquals(List<String> a, List<String> b) =>
      a.length == b.length &&
      [
        for (var i = 0; i < a.length; i++) a[i] == b[i],
      ].every((same) => same);
}

/// Thrown when a manifest does not satisfy the inter-job schema.
class ShardManifestException implements Exception {
  /// Creates an exception with a [message] naming the violation.
  const ShardManifestException(this.message);

  /// The schema violation description.
  final String message;

  @override
  String toString() => message;
}

/// Outcome of [ShardManifestMerger.merge]: a merge is green only with zero
/// problems; the totals are informational (badge/log material).
class ShardMergeResult {
  /// Creates a merge result.
  const ShardMergeResult({
    required this.problems,
    required this.passedTotal,
    required this.failedTotal,
  });

  /// Every defect found (parse, schema, red shard, partition) — empty when
  /// the merge is green.
  final List<String> problems;

  /// Sum of `passed` over all parsed manifests.
  final int passedTotal;

  /// Sum of `failed` over all parsed manifests.
  final int failedTotal;

  /// Whether the merge passed all assertions.
  bool get ok => problems.isEmpty;
}

/// The `agents-gate` merge assertion over downloaded shard manifests.
///
/// Red on: malformed JSON, schema violations, shard-count defects (missing
/// or duplicated shard), any red shard, and partition defects — the union
/// of `plannedFiles` must equal the canonical `run_all.json` list as a
/// multiset (missing file ⇒ red, duplicated file ⇒ red, extra file ⇒ red).
class ShardManifestMerger {
  const ShardManifestMerger._();

  /// Merges raw manifest payloads ([manifestJsons], the downloaded
  /// artifacts, parsed — never evaled) against [expectedFiles], the
  /// canonical `testFiles` list.
  static ShardMergeResult merge({
    required List<String> manifestJsons,
    required List<String> expectedFiles,
  }) {
    final problems = <String>[];
    final manifests = <ShardManifest>[];
    for (var i = 0; i < manifestJsons.length; i++) {
      try {
        final decoded = jsonDecode(manifestJsons[i]);
        manifests.add(ShardManifest.fromJson(decoded));
      } catch (e) {
        problems.add('manifest #$i: failed to parse (${_brief(e)})');
      }
    }
    if (manifestJsons.isEmpty) {
      problems.add('no manifests found — no shard reported');
      return ShardMergeResult(
          problems: problems, passedTotal: 0, failedTotal: 0);
    }
    _collectShardProblems(manifests, problems);
    if (manifests.isNotEmpty) {
      _collectPartitionProblems(manifests, expectedFiles, problems);
    }
    return ShardMergeResult(
      problems: problems,
      passedTotal: manifests.fold(0, (sum, m) => sum + m.passed),
      failedTotal: manifests.fold(0, (sum, m) => sum + m.failed),
    );
  }

  /// Shard-level defects: count vs total, duplicate shard index, red shard.
  ///
  /// [manifests] may be empty when every payload failed to parse — the
  /// parse problems already red the merge.
  static void _collectShardProblems(
    List<ShardManifest> manifests,
    List<String> problems,
  ) {
    if (manifests.isEmpty) return;
    final total = manifests.first.total;
    for (final m in manifests) {
      if (m.total != total) {
        problems.add('shard ${m.shard}: total=${m.total} disagrees with '
            'the other manifests (total=$total)');
      }
    }
    if (manifests.length != total) {
      final seen = <int>{for (final m in manifests) m.shard};
      final missingShards = [
        for (var i = 0; i < total; i++)
          if (!seen.contains(i)) 'shard $i',
      ];
      problems.add('expected $total shard manifests, found '
          '${manifests.length} — missing shard manifests: $missingShards');
    }
    final seen = <int, int>{};
    for (final m in manifests) {
      seen[m.shard] = (seen[m.shard] ?? 0) + 1;
    }
    for (final entry in seen.entries) {
      if (entry.value > 1) {
        problems.add('shard ${entry.key} appears twice in the manifests');
      }
    }
    for (final m in manifests) {
      if (m.success != true) {
        problems.add('shard ${m.shard} failed (success=false, '
            'passed=${m.passed}, failed=${m.failed})');
      } else if (m.failed > 0) {
        problems.add('shard ${m.shard} reports failed=${m.failed} '
            'despite success=true');
      }
    }
  }

  /// Partition defects: the multiset of planned files must equal
  /// [expectedFiles] exactly — missing, duplicated, and unexpected files
  /// are each a red defect (never a silent green with fewer tests).
  static void _collectPartitionProblems(
    List<ShardManifest> manifests,
    List<String> expectedFiles,
    List<String> problems,
  ) {
    final planned = <String, int>{};
    for (final m in manifests) {
      for (final file in m.plannedFiles) {
        planned[file] = (planned[file] ?? 0) + 1;
      }
    }
    final expected = <String, int>{};
    for (final file in expectedFiles) {
      expected[file] = (expected[file] ?? 0) + 1;
    }
    final missing = [
      for (final entry in expected.entries)
        if ((planned[entry.key] ?? 0) < entry.value) entry.key,
    ];
    final duplicated = [
      for (final entry in planned.entries)
        if (expected.containsKey(entry.key) &&
            entry.value > expected[entry.key]!)
          entry.key,
    ];
    final unexpected = [
      for (final file in planned.keys)
        if (!expected.containsKey(file)) file,
    ];
    if (missing.isNotEmpty) {
      problems.add('planned-file partition is missing files never covered '
          'by any shard: $missing');
    }
    if (duplicated.isNotEmpty) {
      problems.add('duplicate planned entries (a file may not run twice): '
          '$duplicated');
    }
    if (unexpected.isNotEmpty) {
      problems.add('planned files not present in run_all.json: $unexpected');
    }
  }
}

/// Short single-line rendering of a merge parse error.
String _brief(Object error) {
  final text = error.toString().replaceAll('\n', ' ');
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}
