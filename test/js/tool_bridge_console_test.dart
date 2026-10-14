import 'dart:convert';
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
  testConsoleStringArgs();
  testConsoleErrorArgs();
}

/// String, JSON-encoded, joined, and oversized console arguments pass
/// through to the host without breaking script execution.
void testConsoleStringArgs() {
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

  test('a pathological console line is truncated, execution continues', () {
    // test_setupCommands.js failure fixtures print ~500 KB single lines;
    // the GitHub Actions log ingester stalls minutes per such line.
    final result = _runScript(
      "function action(params) {"
      " console.log('X'.repeat(500000));"
      " console.log('after');"
      " return 7; }",
    );
    expect(result, '7');
  });
}

/// gh-403: Error arguments render as the human-readable `String(e)` form,
/// never the `{}` of `JSON.stringify(new Error(m))`.
void testConsoleErrorArgs() {
  test('console.error renders an Error object with its message', () {
    // gh-403: JSON.stringify(new Error(m)) === '{}' (message/stack are
    // non-enumerable), so every `console.error('…', e)` in agent scripts
    // printed `{}` and destroyed the error text. The bridge must log the
    // human-readable `String(e)` form instead.
    final stderr = _CaptureStdout();
    final result = IOOverrides.runZoned(
      () => _runScript(
        "function action(params) {"
        " console.error('upd failed:', new Error('the message'));"
        " return 'done'; }",
      ),
      stderr: () => stderr,
    );
    expect(result, '"done"');
    expect(stderr.lines.join('\n'), contains('upd failed: Error: the message'));
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

/// An in-memory [Stdout] collecting every `writeln` line.
class _CaptureStdout implements Stdout {
  final lines = <String>[];

  final _buffer = StringBuffer();

  @override
  void write(Object? obj) => _buffer.write(obj);

  @override
  void writeln([Object? obj = '']) {
    _buffer.write(obj);
    lines.add(_buffer.toString());
    _buffer.clear();
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void add(List<int> data) => write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future close() => Future.value();

  @override
  Future flush() => Future.value();

  @override
  Future get done => Future.value();

  @override
  Encoding encoding = utf8;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String terminator) {}

  @override
  bool get hasTerminal => false;

  @override
  IOSink get nonBlocking => this;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;
}
