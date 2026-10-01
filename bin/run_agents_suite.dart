import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// Runs the dmtools-agents test suite through the QuickJS runtime.
///
/// Usage:
///   dart run bin/run_agents_suite.dart [agents-repo-path]
///   dart run bin/run_agents_suite.dart [agents-repo-path] --serial
///   dart run bin/run_agents_suite.dart [agents-repo-path] \
///     --shard-index <i> --total-shards <n> --manifest-out <path>
///
/// Defaults to `/tmp/dmtools-agents`. The suite config lives at
/// `js/unit-tests/run_all.json` and drives `testRunner.js` — the Phase 4
/// primary acceptance gate.
///
/// Without flags the suite runs as parallel contiguous chunks over worker
/// isolates — same totals as serial, same `Result:` line and exit codes
/// (`lib/src/js/agents_suite.dart`; `DMTOOLS_SUITE_SHARDS` overrides the
/// worker count). `--serial` forces the historical single-engine run.
/// With `--shard-index`/`--total-shards` only the round-robin planned
/// subset runs and a JSON manifest of the shard result is written to
/// `--manifest-out` for the `agents-gate` merge job (gh-315).
Future<void> main(List<String> args) async {
  final parsed = SuiteShardArgs.parse(args);
  if (parsed.isSharded || parsed.serial) {
    exit(runAgentsSuite(parsed));
  }
  final SuiteRunConfig config;
  try {
    config = SuiteRunConfig.load(parsed.agentsPath);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('Clone dmtools-agents or pass its path as the first arg.');
    exit(2);
  }
  exit(
    await runParallelAgentsSuite(
      ParallelSuiteRequest(
        agentsPath: parsed.agentsPath,
        jsPath: config.jsPath,
        jobParams: config.jobParams,
        testFiles: config.testFiles,
      ),
    ),
  );
}
