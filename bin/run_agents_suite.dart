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

  if (result != null) {
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded['success'] == false) {
      exit(1);
    }
  }
}
