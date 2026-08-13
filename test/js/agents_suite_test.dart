import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// Runs a single dmtools-agents test file through the QuickJS runtime using
/// the real `testRunner.js` — the Phase 4 acceptance pipeline in miniature.
///
/// Requires the dmtools-agents repo cloned (default `/tmp/dmtools-agents`,
/// overridable via `DMTOOLS_AGENTS_PATH`). Skips when the repo is absent.
void main() {
  final agentsPath =
      Platform.environment['DMTOOLS_AGENTS_PATH'] ?? '/tmp/dmtools-agents';
  final runnerPath = '$agentsPath/js/unit-tests/testRunner.js';
  final hasRepo = File(runnerPath).existsSync();

  test('testRunner.js runs one test file', () {
    final result = const JsJobRunner().runScript(
      scriptPath: runnerPath,
      jobParams: {
        'testFiles': ['js/unit-tests/test_configLoader.js'],
      },
      workingDirectory: agentsPath,
    );

    expect(result, isNotNull, reason: 'testRunner action() returned nothing');
    final decoded = jsonDecode(result!) as Map;
    expect(decoded['failed'], 0, reason: 'unexpected failures: $result');
    expect(decoded['success'], isTrue, reason: 'suite should pass: $result');
    expect(decoded['passed'] as int, greaterThan(0));
  },
      skip: hasRepo
          ? false
          : 'dmtools-agents repo not found at $agentsPath '
              '(set DMTOOLS_AGENTS_PATH or clone it)');
}
