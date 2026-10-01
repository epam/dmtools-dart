import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/agents_suite.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// Integration tests for the sharded agents suite: they run the REAL
/// `testRunner.js` over the REAL dmtools-agents checkout (env
/// `DMTOOLS_AGENTS_PATH`, the repo's `agents/` submodule on CI, or
/// `/tmp/dmtools-agents`) through real QuickJS isolates.
void main() {
  final checkout = _findAgentsCheckout();
  // Bodies stay inline (top-level group functions) so every test's
  // assertions are statically visible to the test_assertions gate.
  primingIntegrationTests(checkout);
  parallelTotalsIntegrationTests(checkout);
}

void primingIntegrationTests(String? checkout) {
  group(
    'agents-suite sharding (integration)',
    skip: checkout == null
        ? 'dmtools-agents checkout not found (set DMTOOLS_AGENTS_PATH)'
        : false,
    () {
      final agentsPath = checkout!;
      test('priming reproduces the serial scope for a dependent test file',
          () async {
        // test_workingDir.js reads `commentMarkupModule`, a global defined
        // by the earlier test_postPRReviewComments.js in run_all.json
        // order — alone it fails 16/16; with its serial prefix primed it
        // must pass exactly as in the serial run.
        final config = AgentsSuiteConfig.load(agentsPath);
        final chunks = planChunks(
          [
            'js/unit-tests/test_postPRReviewComments.js',
            'js/unit-tests/test_workingDir.js',
          ],
          2,
          (f) => 1,
        );
        final invocations = invocationsFor(
          agentsPath: agentsPath,
          config: config,
          chunks: chunks,
        );
        final outcomes = await runChunkQueue(
          invocations,
          runChunkInIsolate,
          concurrency: 2,
        );
        final report = AgentsSuiteReport.fromShards(outcomes);
        expect(report.crashedShards, isEmpty);
        expect(report.malformedShards, isEmpty);
        expect(report.failed, 0, reason: 'primed chunk must be green');
        expect(report.passed, greaterThan(0));
      }, timeout: const Timeout(Duration(minutes: 2)));
    },
  );
}

void parallelTotalsIntegrationTests(String? checkout) {
  group(
    'agents-suite sharding (integration)',
    skip: checkout == null
        ? 'dmtools-agents checkout not found (set DMTOOLS_AGENTS_PATH)'
        : false,
    () {
      final agentsPath = checkout!;
      test('parallel chunks sum to the serial run of the same files', () async {
        // Also the FFI-parallelism probe: several QuickJS engines with
        // host callbacks run on concurrent isolates in one process;
        // totals must equal the single-context serial run.
        final config = AgentsSuiteConfig.load(agentsPath);
        const files = [
          'js/unit-tests/test_commentMarkup.js',
          'js/unit-tests/test_configLoader.js',
          'js/unit-tests/test_branchNaming.js',
          'js/unit-tests/test_githubHelpers.js',
        ];
        final serial = const JsJobRunner().runScript(
          scriptPath: '$agentsPath/${config.jsPath}',
          jobParams: {'testFiles': files},
          workingDirectory: agentsPath,
        );
        final serialMap = jsonDecode(serial!) as Map;
        final chunks = planChunks(files, 4, (f) => 1);
        final invocations = invocationsFor(
          agentsPath: agentsPath,
          config: config,
          chunks: chunks,
        );
        final outcomes = await runChunkQueue(
          invocations,
          runChunkInIsolate,
          concurrency: 4,
        );
        final parallel = AgentsSuiteReport.fromShards(outcomes);
        expect(parallel.passed, serialMap['passed'],
            reason: 'parallel totals must equal serial totals');
        expect(parallel.failed, serialMap['failed'],
            reason: 'parallel totals must equal serial totals');
      }, timeout: const Timeout(Duration(minutes: 2)));
    },
  );
}

/// Finds a dmtools-agents checkout: `DMTOOLS_AGENTS_PATH`, the repo's
/// `agents/` submodule (CI), then the historical `/tmp/dmtools-agents`.
String? _findAgentsCheckout() {
  final candidates = [
    Platform.environment['DMTOOLS_AGENTS_PATH'],
    'agents',
    '/tmp/dmtools-agents',
  ];
  for (final path in candidates) {
    if (path == null) continue;
    if (File('$path/js/unit-tests/testRunner.js').existsSync()) return path;
  }
  return null;
}
