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

  _setTimeoutChainTests(() => tmp);
  _eventsTimersTests(() => tmp);
  _noNodeCompatTests(() => tmp);
}

String _writeScript(Directory tmp, String body) {
  final f = File('${tmp.path}/job.js');
  f.writeAsStringSync(body);
  return f.path;
}

String _outPath(Directory tmp, String name) => '${tmp.path}/$name';

bool _wrote(Directory tmp, String name) =>
    File(_outPath(tmp, name)).existsSync();

void _setTimeoutChainTests(Directory Function() tmp) {
  test('setTimeout-as-sleep chain settles before runScript returns', () {
    final path = _writeScript(tmp(), '''
function action(params) {
  setTimeout(function () {
    file_write({ path: ${jsonEncode(_outPath(tmp(), 'later.txt'))}, content: 'later' });
    setTimeout(function () {
      file_write({ path: ${jsonEncode(_outPath(tmp(), 'much-later.txt'))}, content: 'much later' });
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
    expect(
      _wrote(tmp(), 'later.txt'),
      isTrue,
      reason: 'block-mode drain settles the 10ms timer',
    );
    expect(
      _wrote(tmp(), 'much-later.txt'),
      isTrue,
      reason: 'timers registered inside timer callbacks fire too',
    );
  });
}

void _eventsTimersTests(Directory Function() tmp) {
  test('events + timers fire through the real engine', () {
    final base = _outPath(tmp(), 'tick-');
    final path = _writeScript(tmp(), '''
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
    expect(
      _wrote(tmp(), 'tick-1.txt'),
      isTrue,
      reason: 'immediate fired during the drain',
    );
    expect(
      _wrote(tmp(), 'tick-2.txt'),
      isTrue,
      reason: 'due timeout fired too',
    );
  });
}

void _noNodeCompatTests(Directory Function() tmp) {
  test(
    'without nodeCompat timers are absent (ReferenceError, like before)',
    () {
      final path = _writeScript(tmp(), '''
function action(params) {
  setTimeout(function () {}, 0);
  return { ok: true };
}
''');
      expect(
        () => JsJobRunner().runScript(scriptPath: path, jobParams: {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('setTimeout'),
          ),
        ),
      );
    },
  );
}
