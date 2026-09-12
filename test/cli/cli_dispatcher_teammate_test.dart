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

/// In-zone `Directory.current` writes reported by [_withFakeCwd]'s setter
/// override. Production code under these tests must never chdir: an entry
/// here means TeammateJob/CliAgent changed cwd as real behavior while
/// observing the fake dir — the dispatch tests assert it stays empty so a
/// future production chdir surfaces loudly instead of being absorbed.
final List<String> _swallowedChdirs = [];

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
    _swallowedChdirs.clear();
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
  _testTeammatePreparedInput();
  _testTeammateCwdHermeticity();
}

/// Zone-scoped fake cwd: TeammateJob's prepared-input probe reads
/// `Directory.current`, so production code inside [body] observes [_tmp]
/// via IOOverrides — without the process-global `Directory.current = …`
/// chdir that every isolate of the test process would otherwise see.
/// In-zone writes cannot escape to the process (the setter override
/// intercepts them) and are recorded in [_swallowedChdirs], so a future
/// production chdir surfaces in the dispatch tests instead of being
/// absorbed silently.
Future<T> _withFakeCwd<T>(Future<T> Function() body) => IOOverrides.runZoned(
      body,
      getCurrentDirectory: () => Directory(_tmp.path),
      setCurrentDirectory: (path) => _swallowedChdirs.add(path),
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
              // Production must not chdir inside the fake: a swallowed
              // write here means the run changed cwd while observing the
              // fake dir — behavior no real process would have.
              expect(_swallowedChdirs, isEmpty);
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
              expect(_swallowedChdirs, isEmpty);
            }));
  });
}

void _testTeammatePreparedInput() {
  group('run <teammate-config>.json prepared input', () {
    test(
        'passes a prepared <cwd>/input/ticket.md through to one CliAgent run',
        () => _withFakeCwd(() async {
              Directory('${_tmp.path}/input').createSync();
              File('${_tmp.path}/input/ticket.md').writeAsStringSync(
                  'Synthetic prepared ticket\nBody of the prepared ticket.');
              final configFile = File('${_tmp.path}/teammate3.json')
                ..writeAsStringSync(jsonEncode({
                  'name': 'Teammate',
                  'params': {
                    'cliCommands': ['echo done'],
                    'cleanupInputFolder': false,
                    'metadata': {'contextId': 'prepared-issue'},
                  },
                }));
              final code = await _dispatcher.dispatch(['run', configFile.path]);
              expect(code, 0);
              final result = jsonDecode(_lines.last) as Map<String, dynamic>;
              expect(result['success'], isTrue);
              final results = result['results'] as List<dynamic>;
              expect(results, hasLength(1));
              expect(results.single['ticket'], 'prepared-issue');
              expect(results.single['success'], isTrue);
              expect(results.single['response'], contains('done'));
              // The probe must resolve against the ZONE cwd: only the
              // synthetic ticket may feed the CliAgent context folder — a
              // probe that regresses to a relative path would pick up the
              // process cwd's own input/ticket.md instead.
              final contextTicket =
                  File('${_tmp.path}/input/prepared-issue/ticket.md');
              expect(contextTicket.existsSync(), isTrue);
              expect(contextTicket.readAsStringSync(),
                  contains('Synthetic prepared ticket'));
              // Same no-chdir guard as the no-op group above: the
              // pass-through path runs TeammateJob → CliAgent end to end.
              expect(_swallowedChdirs, isEmpty);
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

    test('records in-zone chdir attempts instead of absorbing them', () async {
      // Regression: the setter must not be a silent sink. A production
      // chdir inside the fake has to surface in [_swallowedChdirs] — the
      // dispatch tests pin that list empty — and the swallowed write must
      // not leak process-wide either.
      await _withFakeCwd(() async {
        Directory.current = _tmp.parent.path;
      });
      expect(_swallowedChdirs, [_tmp.parent.path]);
      expect(await Isolate.run(() => Directory.current.path), _processCwd);
    });
  });
}
