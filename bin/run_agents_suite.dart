import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// Runs the dmtools-agents test suite through the QuickJS runtime.
///
/// Usage:
///   dart run bin/run_agents_suite.dart [agents-repo-path]
///
/// Defaults to `/tmp/dmtools-agents`. The suite config lives at
/// `js/unit-tests/run_all.json` and drives `testRunner.js` — the Phase 4
/// primary acceptance gate.
Future<void> main(List<String> args) async {
  final agentsPath = args.isNotEmpty ? args[0] : '/tmp/dmtools-agents';
  final configPath = '$agentsPath/js/unit-tests/run_all.json';

  if (!File(configPath).existsSync()) {
    stderr.writeln('Config not found: $configPath');
    stderr.writeln('Clone dmtools-agents or pass its path as the first arg.');
    exit(2);
  }

  final config = jsonDecode(File(configPath).readAsStringSync()) as Map;
  final params = config['params'] as Map;
  final jobParams = Map<String, dynamic>.from(params['jobParams'] as Map);
  final jsPath = params['jsPath'] as String;

  final result = const JsJobRunner().runScript(
    scriptPath: '$agentsPath/$jsPath',
    jobParams: jobParams,
    workingDirectory: agentsPath,
  );

  stdout.writeln('Result: $result');

  // The agents suite is the primary acceptance gate: require a well-formed,
  // fully-passing result. A missing/malformed result (script crash that
  // returns undefined) fails the run instead of silently exiting 0.
  if (result == null) {
    stderr.writeln('Agents suite returned no result (script crashed?).');
    exit(1);
  }
  final decoded = jsonDecode(result);
  if (decoded is! Map) {
    stderr.writeln('Agents suite returned a non-object result: $decoded');
    exit(1);
  }
  final passed = decoded['passed'];
  final failed = decoded['failed'];
  if (decoded['success'] != true ||
      passed is! int ||
      failed is! int ||
      passed <= 0 ||
      failed > 0) {
    stderr.writeln('Agents suite failed: $decoded');
    exit(1);
  }
  stdout.writeln('Agents suite green: $passed passed, $failed failed.');
}
