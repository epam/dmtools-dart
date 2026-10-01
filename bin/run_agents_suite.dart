import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// Runs the dmtools-agents test suite through the QuickJS runtime —
/// parallelized across isolates.
///
/// Usage:
///   dart run bin/run_agents_suite.dart [agents-repo-path]
///
/// Defaults to `/tmp/dmtools-agents`. The suite config lives at
/// `js/unit-tests/run_all.json` and drives `testRunner.js` — the Phase 4
/// primary acceptance gate. `testFiles` is cut into contiguous chunks and
/// executed by N workers (`DMTOOLS_SUITE_SHARDS`, else `numberOfProcessors`
/// capped at 8), each chunk on its own isolate with its own QuickJS
/// context; every chunk first evals its serial prefix with counting
/// neutralized, so totals match a serial run exactly (see
/// `lib/src/js/agents_suite.dart` for the design).
Future<void> main(List<String> args) async {
  final agentsPath = args.isNotEmpty ? args[0] : '/tmp/dmtools-agents';

  final AgentsSuiteConfig config;
  try {
    config = AgentsSuiteConfig.load(agentsPath);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('Clone dmtools-agents or pass its path as the first arg.');
    exit(2);
  }

  final shardCount = resolveShardCount(
    Platform.environment['DMTOOLS_SUITE_SHARDS'],
    processors: Platform.numberOfProcessors,
  );
  final chunks = planChunks(
    config.testFiles,
    chunkCountFor(config.testFiles.length, shardCount),
    (file) => File('$agentsPath/$file').lengthSync(),
  );
  final invocations = invocationsFor(
    agentsPath: agentsPath,
    config: config,
    chunks: chunks,
  );
  stdout.writeln(
    'Agents suite: ${config.testFiles.length} files in ${chunks.length} '
    'chunks on $shardCount parallel worker(s).',
  );

  final outcomes = await runChunkQueue(
    invocations,
    runChunkInIsolate,
    concurrency: shardCount,
  );
  final report = AgentsSuiteReport.fromShards(outcomes);

  stdout.writeln('Result: ${jsonEncode(report.toJson())}');

  // The agents suite is the primary acceptance gate: require a
  // well-formed, fully-passing result — one malformed/crashed chunk
  // fails the whole run, mirroring the old single-run gate.
  stderr.write(shardDiagnostics(outcomes));
  if (report.exitCode != 0) {
    stderr.writeln('Agents suite failed: ${failureSummary(report)}');
    exit(report.exitCode);
  }
  stdout.writeln(
    'Agents suite green: ${report.passed} passed, ${report.failed} failed.',
  );
}
