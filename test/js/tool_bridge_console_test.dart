import 'dart:io';

import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// Tests for the [ToolBridge] console bridge — `console.log`/`warn`/`error`
/// calls from JS are marshaled to the host and decoded by `_consoleArg`
/// (raw string, JSON-encoded non-string, and joined-argument shapes).
///
/// Every script defines `action(params)` — the JSRunner contract enforced
/// by [JsJobRunner.runScript] (Java `JobJavaScriptBridge` parity).
void main() {
  test('console.log prints a plain string argument and continues', () {
    final result = _runScript(
      "function action(params) { console.log('hello'); return 1 + 1; }",
    );
    expect(result, '2');
  });

  test('console.log prints a JSON-encoded non-string argument', () {
    final result = _runScript(
      'function action(params) { console.log(42); return "ok"; }',
    );
    expect(result, '"ok"');
  });

  test('console.log prints multiple joined arguments', () {
    final result = _runScript(
      "function action(params) { console.log('a', 'b'); return 7; }",
    );
    expect(result, '7');
  });

  test('console.warn and console.error do not break execution', () {
    final result = _runScript(
      "function action(params) { console.warn('w'); "
      "console.error('e'); return 5; }",
    );
    expect(result, '5');
  });

  test('console calls are chainable no-ops in expressions', () {
    final result = _runScript(
      "function action(params) { const x = console.log('v'); return 3; }",
    );
    expect(result, '3');
  });
}

/// Runs [source] as a temp script and returns the raw JSON result.
String? _runScript(String source) {
  final dir = Directory.systemTemp.createTempSync('dmtools_console');
  try {
    final script = File('${dir.path}/test.js')..writeAsStringSync(source);
    return const JsJobRunner().runScript(
      scriptPath: script.path,
      jobParams: {},
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
