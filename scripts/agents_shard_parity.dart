// gh-315 — suite-parity REG tool: runs the agents suite serially, then
// sharded (shards executed sequentially, one fresh QuickJS engine per
// run), and compares the per-shard outcomes against the serial run.
//
// Usage (from the repo root; requires `make native`):
//   dart run scripts/agents_shard_parity.dart <agents-path> [total-shards]
//
// Exit codes: 0 = parity (sharding preserves the serial outcome),
// 1 = parity mismatch or suite red, 2 = config/environment problem.
//
// ORDER-DEPENDENCE RUNBOOK (edge case E3)
//
// A mismatch means at least one test file depends on execution order —
// it passes serially only because an earlier file left globals behind,
// or fails sharded because a global it relies on is no longer set
// (each shard runs in its own engine, so cross-file global leakage is
// cut at shard boundaries).
//
// Resolution, in order:
//   1. Identify the offending file(s) from the mismatched shard: run the
//      parity tool with --total-shards 1 (= serial) versus increasing
//      counts; the first shard whose outcome drifts pins the file set.
//   2. Fix the file's self-containment — move shared setup into the file
//      itself, stop reading globals another file defines.
//   3. If the file lives upstream (all dmtools-agents files do), the fix
//      is a PR to dmtools-agents — NEVER a local patch under agents/
//      (the unmodified-suite acceptance rule, GOAL.md Phase 4).
//
// Cadence: on-demand — at release time and whenever a shard fails while
// the serial run is green (promote to a nightly leg if E3 ever fires).
import 'dart:io';

import 'package:dmtools/src/agents/suite_shard_parity.dart';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run scripts/agents_shard_parity.dart '
      '<agents-path> [total-shards]',
    );
    exit(2);
  }
  final agentsPath = args[0];
  final totalShards = args.length == 2 ? int.tryParse(args[1]) : 1;
  if (totalShards == null || totalShards < 1) {
    stderr.writeln('total-shards must be a positive integer: "${args[1]}"');
    exit(2);
  }

  stdout.writeln(
    'Suite parity: serial run, then $totalShards shard run(s) '
    '(sequential, fresh engine each)',
  );
  final ShardParityReport report;
  try {
    report = runShardParity(
      agentsPath: agentsPath,
      totalShards: totalShards,
    );
  } catch (e) {
    stderr.writeln('Parity run failed: $e');
    exit(2);
  }

  stdout.writeln('  ${report.serialOutcome}');
  for (final outcome in report.shardOutcomes) {
    stdout.writeln('  $outcome');
  }

  if (report.ok) {
    final passed = report.serialOutcome.passed;
    stdout.writeln(
      'Parity OK: sharding preserves the serial outcome ($passed passed).',
    );
    exit(0);
  }
  stderr.writeln('Parity MISMATCH — order-dependent behavior detected:');
  for (final mismatch in report.mismatches) {
    stderr.writeln('  ✗ $mismatch');
  }
  stderr.writeln('See the runbook in scripts/agents_shard_parity.dart '
      '(fix upstream via a dmtools-agents PR, never a local patch).');
  exit(1);
}
