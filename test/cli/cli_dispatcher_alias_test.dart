/// Unit tests for CLI alias-default resolution (Java
/// `McpCliHandler.resolveToolAlias`): an alias invocation on the CLI
/// surface picks the carrier tool via DEFAULT_TRACKER /
/// DEFAULT_SOURCE_CODE, resolved through the standard PropertyReader
/// chain (overrides → config.properties → dmtools.env → OS env) — so a
/// value in `dmtools.env` is visible to alias resolution (gh-122) and
/// wins over the OS-env tier.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;
late List<String> _lines;
late CliDispatcher _dispatcher;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_cli_alias_');
    PropertyReader.setOverrides({});
    PropertyReader.testEnvironment.clear();
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

  _testPropertyChainRouting();
  _testFileTierRouting();
}

/// Dispatches [args] on the shared dispatcher, asserts exit code [code],
/// and returns the decoded JSON object of the result line.
Future<Map<String, dynamic>> _dispatchTool(
  List<String> args, {
  int code = 1,
}) async {
  expect(await _dispatcher.dispatch(args), code);
  return jsonDecode(_lines.last) as Map<String, dynamic>;
}

void _writeEnv(String content) =>
    File('${_tmp.path}/dmtools.env').writeAsStringSync(content);

/// Carrier selection through the overrides-free tiers: unset falls back
/// to the first candidate, the OS-env tier still routes.
void _testPropertyChainRouting() {
  group('alias routing (unset and OS-env tier)', () {
    test('resolves a tracker_* alias to the jira carrier by default', () async {
      final result =
          await _dispatchTool(['tracker_get_ticket', '{"key": "DMC-479"}']);
      expect(result['error'], contains('Jira not configured'),
          reason: 'first candidate (jira) when DEFAULT_TRACKER is unset');
    });

    test('DEFAULT_TRACKER from the OS-env tier routes to the ado carrier',
        () async {
      PropertyReader.testEnvironment['DEFAULT_TRACKER'] = 'ado';
      final result =
          await _dispatchTool(['tracker_get_ticket', '{"key": "4242"}']);
      expect(result['error'], contains('ADO not configured'),
          reason: 'DEFAULT_TRACKER=ado picks the ado carrier');
    });
  });
}

/// The dmtools.env file tier of alias-default resolution (gh-122).
void _testFileTierRouting() {
  group('alias routing (dmtools.env tier)', () {
    test('DEFAULT_TRACKER in dmtools.env routes to the github carrier',
        () async {
      _writeEnv('DEFAULT_TRACKER=github\n');
      final result = await _dispatchTool(
          ['tracker_get_ticket', '{"key": "epam/dmtools-dart#38"}']);
      expect(result['error'], contains('GitHub not configured'),
          reason:
              'dmtools.env DEFAULT_TRACKER=github picks the github carrier');
    });

    test('dmtools.env wins over the OS-env tier (resolution order)', () async {
      PropertyReader.testEnvironment['DEFAULT_TRACKER'] = 'ado';
      _writeEnv('DEFAULT_TRACKER=github\n');
      final result =
          await _dispatchTool(['tracker_get_ticket', '{"key": "4242"}']);
      expect(result['error'], contains('GitHub not configured'),
          reason: 'the dmtools.env file tier precedes the OS env');
    });

    test('DEFAULT_SOURCE_CODE in dmtools.env routes source_code_* aliases',
        () async {
      _writeEnv('DEFAULT_SOURCE_CODE=gitlab\n');
      final result = await _dispatchTool(
          ['source_code_get_pr', '{"repository": "group/project"}']);
      expect(result['error'], contains('GitLab not configured'),
          reason:
              'dmtools.env DEFAULT_SOURCE_CODE=gitlab picks the gitlab carrier');
    });
  });
}
