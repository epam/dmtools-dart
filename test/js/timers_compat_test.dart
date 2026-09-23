// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// End-to-end: nodeCompat scripts get real, Node-behaving timers through the
/// product engine — the block-mode drain after `action` settles
/// setTimeout-as-sleep chains, and events fire through it too. Observable
/// side effects go through the real `file_write` tool: the JS runtime is
/// closed by the time `runScript` returns, so files are the evidence.
void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dmtools_timers_compat_');
    tmp.createSync();
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  String writeScript(String body) {
    final f = File('${tmp.path}/job.js');
    f.writeAsStringSync(body);
    return f.path;
  }

  String outPath(String name) => '${tmp.path}/$name';
  bool wrote(String name) => File(outPath(name)).existsSync();

  test('setTimeout-as-sleep chain settles before runScript returns', () {
    final path = writeScript('''
function action(params) {
  setTimeout(function () {
    file_write({ path: ${jsonEncode(outPath('later.txt'))}, content: 'later' });
    setTimeout(function () {
      file_write({ path: ${jsonEncode(outPath('much-later.txt'))}, content: 'much later' });
    }, 10);
  }, 10);
  return { started: true };
}
''');
    final result = JsJobRunner().runScript(
      scriptPath: path,
      jobParams: {'nodeCompat': true},
    );
    expect(jsonDecode(result!)['started'], true);
    expect(wrote('later.txt'), isTrue,
        reason: 'block-mode drain settles the 10ms timer');
    expect(wrote('much-later.txt'), isTrue,
        reason: 'timers registered inside timer callbacks fire too');
  });

  test('events + timers fire through the real engine', () {
    final base = outPath('tick-');
    final path = writeScript('''
var EventEmitter = require('events');
var ee = new EventEmitter();
ee.on('tick', function (v) {
  file_write({ path: ${jsonEncode(base)} + v + '.txt', content: 'x' });
});
function action(params) {
  setImmediate(function () { ee.emit('tick', 1); });
  setTimeout(function () { ee.emit('tick', 2); }, 0);
  return { registered: ee.listenerCount('tick') };
}
''');
    final result = JsJobRunner().runScript(
      scriptPath: path,
      jobParams: {'nodeCompat': true},
    );
    expect(jsonDecode(result!)['registered'], 1);
    expect(wrote('tick-1.txt'), isTrue,
        reason: 'immediate fired during the drain');
    expect(wrote('tick-2.txt'), isTrue, reason: 'due timeout fired too');
  });

  test('without nodeCompat timers are absent (ReferenceError, like before)',
      () {
    final path = writeScript('''
function action(params) {
  setTimeout(function () {}, 0);
  return { ok: true };
}
''');
    expect(
      () => JsJobRunner().runScript(
        scriptPath: path,
        jobParams: {},
      ),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('setTimeout'))),
    );
  });
}
