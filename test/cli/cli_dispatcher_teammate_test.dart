/// Teammate-dispatch hermeticity tests (`run <teammate-config>.json`).
///
/// Split out of `cli_dispatcher_test.dart` so the cwd pinning lives in one
/// focused file: with no `inputJql`, TeammateJob probes
/// `<Directory.current>/input/ticket.md` for the prepared-input
/// pass-through, so these tests must control what `Directory.current`
/// resolves to — without ever mutating it process-wide.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;
late List<String> _lines;
late CliDispatcher _dispatcher;

/// Process cwd as seen from outside any hermetic override, captured in
/// [setUp] before any per-group cwd override can be active.
late String _processCwd;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_cli_teammate_');
    _processCwd = Directory.current.path;
    PropertyReader.setOverrides({});
    _lines = [];
    _dispatcher = CliDispatcher(
      writer: _lines.add,
      propertyReader: PropertyReader(basePath: _tmp.path),
      isTty: () => false,
    );
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testTeammateNoOpRun();
  _testTeammateCwdHermeticity();
}

/// Zone-scoped fake cwd: TeammateJob's prepared-input probe reads
/// `Directory.current`, so production code inside [body] observes [_tmp]
/// via IOOverrides — without the process-global `Directory.current = …`
/// chdir that every isolate of the test process would otherwise see.
/// The `setCurrentDirectory` no-op swallows in-zone writes, so a stray
/// chdir inside the fake cannot escape to the process either.
Future<T> _withFakeCwd<T>(Future<T> Function() body) => IOOverrides.runZoned(
      body,
      getCurrentDirectory: () => Directory(_tmp.path),
      setCurrentDirectory: (_) {},
    );

void _testTeammateNoOpRun() {
  group('run <teammate-config>.json', () {
    test(
        'executes a teammate job without inputJql as a no-op success',
        () => _withFakeCwd(() async {
              final configFile = File('${_tmp.path}/teammate.json')
                ..writeAsStringSync(jsonEncode({
                  'name': 'Teammate',
                  'params': {
                    'cliCommands': ['echo done'],
                  },
                }));
              final code = await _dispatcher.dispatch(['run', configFile.path]);
              expect(code, 0);
              final result = jsonDecode(_lines.last) as Map<String, dynamic>;
              expect(result['success'], isTrue);
              expect(result['results'], isEmpty);
            }));

    test(
        'runs the teammate config case-insensitively',
        () => _withFakeCwd(() async {
              final configFile = File('${_tmp.path}/teammate2.json')
                ..writeAsStringSync(jsonEncode({
                  'name': 'teammate',
                  'params': {
                    'cliCommands': ['echo done']
                  },
                }));
              expect(await _dispatcher.dispatch(['run', configFile.path]), 0);
            }));
  });
}

void _testTeammateCwdHermeticity() {
  group('run <teammate-config>.json cwd pin', () {
    test('pins cwd hermetically without mutating the process-global one',
        () async {
      // Regression: the cwd pin must stay scoped to the tests that need
      // it. A fresh isolate observes the real process-global cwd (new
      // isolates carry no zone state) — the same view every other
      // concurrently running test-suite isolate shares. If the pin leaks
      // process-wide, this sees the temp dir instead of the repo root.
      expect(await Isolate.run(() => Directory.current.path), _processCwd);
      await _withFakeCwd(() async {
        // The production path under test must observe the pinned dir.
        expect(Directory.current.path, _tmp.path);
        expect(await Isolate.run(() => Directory.current.path), _processCwd);
      });
      expect(await Isolate.run(() => Directory.current.path), _processCwd);
    });
  });
}
