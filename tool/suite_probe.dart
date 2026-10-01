import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// Probes each suspicious agents-suite test file in a FRESH engine (the
/// shard condition): a self-sufficient file passes alone; a file that
/// depends on cross-engine global leakage fails.
Future<void> main(List<String> args) async {
  final agentsPath = args.isNotEmpty ? args[0] : 'agents';
  const files = [
    'js/unit-tests/test_workingDir.js',
    'js/unit-tests/test_developBugAndCreatePR.js',
    'js/unit-tests/test_postStoryTestAutomationReview.js',
    'js/unit-tests/test_developTicketAndCreatePR.js',
    'js/unit-tests/test_pushReworkChanges.js',
    'js/unit-tests/test_reworkCustomParams.js',
    'js/unit-tests/test_commentMarkup.js',
  ];
  for (final f in files) {
    final result = const JsJobRunner().runScript(
      scriptPath: '$agentsPath/js/unit-tests/testRunner.js',
      jobParams: {
        'testFiles': [f],
      },
      workingDirectory: agentsPath,
    );
    final decoded = result == null ? null : jsonDecode(result);
    stdout.writeln(
      '$f -> success=${decoded?['success']} passed=${decoded?['passed']} '
      'failed=${decoded?['failed']}',
    );
  }
}
