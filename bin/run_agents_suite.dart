import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// Runs the dmtools-agents test suite through the QuickJS runtime.
///
/// Usage:
///   dart run bin/run_agents_suite.dart [agents-repo-path]
///   dart run bin/run_agents_suite.dart [agents-repo-path] \
///     --shard-index <i> --total-shards <n> --manifest-out <path>
///
/// Defaults to `/tmp/dmtools-agents`. The suite config lives at
/// `js/unit-tests/run_all.json` and drives `testRunner.js` — the Phase 4
/// primary acceptance gate.
///
/// Without shard flags this is the historical serial run (identical
/// behavior and exit contract, AC5). With `--shard-index`/`--total-shards`
/// only the round-robin planned subset runs (same unmodified
/// `testRunner.js`) and a JSON manifest of the shard result is written to
/// `--manifest-out` for the `agents-gate` merge job (gh-315). All logic
/// lives in lib/ — this shell only parses argv and exits.
Future<void> main(List<String> args) async {
  exit(runAgentsSuite(SuiteShardArgs.parse(args)));
}
