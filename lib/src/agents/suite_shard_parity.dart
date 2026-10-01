/// gh-315 — suite-parity: serial vs sharded outcome equality (AC6).
///
/// On-demand REG tool backing `scripts/agents_shard_parity.dart`. Runs the
/// suite serially (the full `run_all.json` list through the unmodified
/// `testRunner.js`), then runs each shard's planned subset — sequentially,
/// one fresh engine per run — and compares the per-shard outcomes against
/// the serial run.
///
/// Runbook (order-dependent test files, edge case E3): a mismatch here
/// means a test file depends on execution order — it passes serially only
/// because an earlier file left globals behind, or fails sharded because a
/// global it relied on is no longer set. Fix the file's self-containment:
/// via a PR to dmtools-agents when the file lives upstream (never a local
/// patch to `agents/` — the suite must run unmodified).
library;

import 'dart:convert';

import '../js/job_runner.dart';
import 'suite_shard_runner.dart';
import 'suite_sharding.dart';

/// One engine run's outcome, upstream's result contract verbatim.
class ShardOutcome {
  /// Creates an outcome. Crash-free runs carry [crash] = null.
  const ShardOutcome({
    required this.label,
    required this.success,
    required this.passed,
    required this.failed,
    this.crash,
  });

  /// Human-readable run identity (`serial`, `shard 1/4`).
  final String label;

  /// Upstream `success` (false when the run crashed or returned nothing).
  final bool success;

  /// Upstream `passed` counter (0 when the run crashed).
  final int passed;

  /// Upstream `failed` counter (0 when the run crashed).
  final int failed;

  /// Crash description when the engine died before producing a result.
  final String? crash;

  @override
  String toString() => '$label: success=$success passed=$passed failed=$failed'
      '${crash == null ? '' : ' (crashed: $crash)'}';
}

/// Serial-vs-sharded comparison result.
class ShardParityReport {
  /// Creates a report.
  const ShardParityReport({
    required this.serialOutcome,
    required this.shardOutcomes,
    required this.mismatches,
  });

  /// The serial (full-list) run's outcome.
  final ShardOutcome serialOutcome;

  /// Each shard's outcome, in shard order.
  final List<ShardOutcome> shardOutcomes;

  /// Differences between the serial run and the sharded runs — empty when
  /// outcomes are equal.
  final List<String> mismatches;

  /// Whether sharding preserves the serial outcome.
  bool get ok => mismatches.isEmpty;
}

/// Runs the suite at [agentsPath] serially and sharded ([totalShards]
/// shards, executed sequentially in-process) and compares the outcomes.
ShardParityReport runShardParity({
  required String agentsPath,
  int totalShards = 4,
}) {
  final config = loadAgentsSuiteConfig(agentsPath);
  final serialOutcome = _runOnce(
    agentsPath: agentsPath,
    jsPath: config.jsPath,
    label: 'serial',
    testFiles: config.testFiles,
  );
  final shardOutcomes = <ShardOutcome>[];
  for (var i = 0; i < totalShards; i++) {
    shardOutcomes.add(
      _runOnce(
        agentsPath: agentsPath,
        jsPath: config.jsPath,
        label: 'shard ${i + 1}/$totalShards',
        testFiles: ShardPlanner.split(config.testFiles, i, totalShards),
      ),
    );
  }
  return ShardParityReport(
    serialOutcome: serialOutcome,
    shardOutcomes: shardOutcomes,
    mismatches: _compare(serialOutcome, shardOutcomes),
  );
}

ShardOutcome _runOnce({
  required String agentsPath,
  required String jsPath,
  required String label,
  required List<String> testFiles,
}) {
  try {
    final result = const JsJobRunner().runScript(
      scriptPath: '$agentsPath/$jsPath',
      jobParams: {'testFiles': testFiles},
      workingDirectory: agentsPath,
    );
    return _decodeOutcome(label, result);
  } catch (e) {
    return ShardOutcome(
      label: label,
      success: false,
      passed: 0,
      failed: 0,
      crash: '$e',
    );
  }
}

/// Maps a raw engine result to an outcome; unusable results (undefined,
/// non-JSON, wrong shape) become crashed outcomes.
ShardOutcome _decodeOutcome(String label, String? result) {
  if (result == null) {
    return _crashOutcome(label, 'action() returned undefined');
  }
  final decoded = _tryDecode(result);
  if (!_wellFormedOutcome(decoded)) {
    return _crashOutcome(label, 'malformed result: $result');
  }
  return ShardOutcome(
    label: label,
    success: decoded['success'] as bool,
    passed: decoded['passed'] as int,
    failed: decoded['failed'] as int,
  );
}

ShardOutcome _crashOutcome(String label, String crash) => ShardOutcome(
      label: label,
      success: false,
      passed: 0,
      failed: 0,
      crash: crash,
    );

/// A unusable payload is a crash, whatever the reason: the runtime
/// JSON-encodes every action() return, so non-JSON text here means the
/// engine broke its contract just like a wrong-shaped object would.
dynamic _tryDecode(String result) {
  try {
    return jsonDecode(result);
  } on FormatException {
    return null;
  }
}

/// Upstream's result contract: `{success: bool, passed: int, failed: int}`.
bool _wellFormedOutcome(dynamic decoded) =>
    decoded is Map &&
    decoded['success'] is bool &&
    decoded['passed'] is int &&
    decoded['failed'] is int;

/// Outcome equality: shard successes must match the serial run, and the
/// passed/failed counters must sum to the serial counters.
List<String> _compare(
  ShardOutcome serial,
  List<ShardOutcome> shards,
) {
  final mismatches = <String>[];
  _counterMismatches(serial, shards, mismatches);
  _successMismatches(serial, shards, mismatches);
  return mismatches;
}

void _counterMismatches(
  ShardOutcome serial,
  List<ShardOutcome> shards,
  List<String> mismatches,
) {
  final passedSum = shards.fold(0, (sum, o) => sum + o.passed);
  final failedSum = shards.fold(0, (sum, o) => sum + o.failed);
  if (passedSum != serial.passed) {
    mismatches.add(
      'passed mismatch: serial=${serial.passed} vs shards sum=$passedSum',
    );
  }
  if (failedSum != serial.failed) {
    mismatches.add(
      'failed mismatch: serial=${serial.failed} vs shards sum=$failedSum',
    );
  }
}

void _successMismatches(
  ShardOutcome serial,
  List<ShardOutcome> shards,
  List<String> mismatches,
) {
  for (final shard in shards) {
    if (shard.success != serial.success || shard.crash != null) {
      mismatches.add(
        '${shard.label} outcome differs from serial: '
        'shard(success=${shard.success}, failed=${shard.failed}, '
        'crash=${shard.crash ?? 'none'}) vs '
        'serial(success=${serial.success}, failed=${serial.failed})',
      );
    }
  }
}
