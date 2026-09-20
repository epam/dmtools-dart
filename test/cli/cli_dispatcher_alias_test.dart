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
  _testAliasHelp();
  _testAliasList();
  _testAliasIntegrations();
  _testAliasHelpEdges();
  _testAliasKeyHintRouting();
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

/// The tool names in a tools-list response (`dmtools list` / `--help` shape).
List<String> _toolNames(Map<String, dynamic> response) =>
    (response['tools'] as List)
        .cast<Map<String, dynamic>>()
        .map((t) => t['name'] as String)
        .toList();

/// gh-136: the `--help` path (`dmtools <tool> --help`) and the
/// `dmtools list <filter>` path resolve an alias filter through
/// `resolveToolAlias` before the substring filter — Java `McpCliHandler`
/// help resolution mirrors invocation resolution, so an aliased tool shows
/// the resolved backend tool's schema instead of an empty tools list.
void _testAliasHelp() {
  group('alias help/list resolution', () {
    test('tracker_get_ticket --help shows the first-candidate (jira) schema',
        () async {
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      final names = _toolNames(result);
      expect(names, isNotEmpty);
      expect(names, contains('jira_get_ticket'),
          reason: 'DEFAULT_TRACKER unset → first candidate (jira)');
    });

    test('DEFAULT_TRACKER=github routes tracker_get_ticket --help to github',
        () async {
      _writeEnv('DEFAULT_TRACKER=github\n');
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      expect(_toolNames(result), contains('github_get_issue'),
          reason: 'DEFAULT_TRACKER=github picks the github carrier');
    });

    test('tracker_post_comment --help follows DEFAULT_TRACKER=ado', () async {
      _writeEnv('DEFAULT_TRACKER=ado\n');
      final result =
          await _dispatchTool(['tracker_post_comment', '--help'], code: 0);
      expect(_toolNames(result), contains('ado_add_work_item_comment'),
          reason: 'DEFAULT_TRACKER=ado picks the ado carrier');
    });

    test('tracker_search --help shows the first candidate (jira)', () async {
      final result = await _dispatchTool(['tracker_search', '--help'], code: 0);
      expect(_toolNames(result), contains('jira_search_by_jql'));
    });

    test('source_code_get_pr --help follows DEFAULT_SOURCE_CODE=gitlab',
        () async {
      _writeEnv('DEFAULT_SOURCE_CODE=gitlab\n');
      final result =
          await _dispatchTool(['source_code_get_pr', '--help'], code: 0);
      expect(_toolNames(result), contains('gitlab_get_mr'),
          reason: 'DEFAULT_SOURCE_CODE=gitlab picks the gitlab carrier');
    });

    test('canonical tool --help is unchanged', () async {
      final result =
          await _dispatchTool(['jira_get_ticket', '--help'], code: 0);
      expect(_toolNames(result), contains('jira_get_ticket'));
    });
  });
}

/// gh-136: `dmtools list <filter>` shares the help filter path, so an
/// alias filter resolves to its carrier while unknown text keeps the raw
/// substring semantics.
void _testAliasList() {
  group('alias list resolution', () {
    test('dmtools list <alias> resolves the filter to the carrier', () async {
      final result =
          await _dispatchTool(['list', 'tracker_get_ticket'], code: 0);
      expect(_toolNames(result), contains('jira_get_ticket'));
    });

    test('dmtools list keeps substring semantics for unknown filters',
        () async {
      final result = await _dispatchTool(['list', 'jira_search'], code: 0);
      final names = _toolNames(result);
      expect(names, contains('jira_search_by_jql'));
      expect(names.every((name) => name.startsWith('jira_search')), isTrue);
    });

    test('DEFAULT_TRACKER routes dmtools list <alias> to the carrier',
        () async {
      _writeEnv('DEFAULT_TRACKER=ado\n');
      final result =
          await _dispatchTool(['list', 'tracker_get_ticket'], code: 0);
      expect(_toolNames(result), contains('ado_get_work_item'),
          reason: 'the list path honors DEFAULT_TRACKER like invocation');
    });
  });
}

/// gh-136 review (IMPORTANT): `DMTOOLS_INTEGRATIONS` narrows the tools
/// list, so alias resolution must pick a carrier visible in that filtered
/// response — otherwise `dmtools <alias> --help` prints `{"tools": []}`
/// whenever the default carrier sits outside the filter.
void _testAliasIntegrations() {
  group('alias help under DMTOOLS_INTEGRATIONS', () {
    test('resolution falls back to a carrier inside the filter', () async {
      PropertyReader.setOverrides({'DMTOOLS_INTEGRATIONS': 'ado'});
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      final names = _toolNames(result);
      expect(names, isNotEmpty);
      expect(names, contains('ado_get_work_item'),
          reason: 'jira/github are filtered out — the ado carrier shows');
    });

    test('DEFAULT_TRACKER outside the filter falls back to a visible carrier',
        () async {
      PropertyReader.setOverrides({'DMTOOLS_INTEGRATIONS': 'jira'});
      _writeEnv('DEFAULT_TRACKER=github\n');
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      expect(_toolNames(result), contains('jira_get_ticket'),
          reason: 'the github carrier is filtered out — first visible wins');
    });

    test('every listed tool respects the integration filter', () async {
      PropertyReader.setOverrides({'DMTOOLS_INTEGRATIONS': 'ado'});
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      expect(
        _toolNames(result).every((name) => name.startsWith('ado_')),
        isTrue,
      );
    });
  });
}

/// gh-136 review suggestions: the help path mirrors the invocation path's
/// unknown-tool error, and the remaining DEFAULT_* / tier contracts are
/// pinned at the dispatcher level.
void _testAliasHelpEdges() {
  group('alias help edge cases', () {
    test('unknown tool + --help mirrors the invocation unknown-tool error',
        () async {
      expect(await _dispatcher.dispatch(['some_typo_tool', '--help']), 1);
      expect(_lines, contains('Error: unknown tool: some_typo_tool'));
      expect(_lines, contains('Run "dmtools list" for available tools'));
    });

    test('free-text list keeps exit 0 even with an empty result', () async {
      expect(await _dispatcher.dispatch(['list', 'zenhub_nope']), 0);
      final result = jsonDecode(_lines.last) as Map<String, dynamic>;
      expect(result['tools'], isEmpty);
    });

    test('OS-env tier DEFAULT_TRACKER routes the help path', () async {
      PropertyReader.testEnvironment['DEFAULT_TRACKER'] = 'github';
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      expect(_toolNames(result), contains('github_get_issue'));
    });

    test('an invalid DEFAULT_TRACKER falls back to the first candidate',
        () async {
      _writeEnv('DEFAULT_TRACKER=bitrise\n');
      final result =
          await _dispatchTool(['tracker_get_ticket', '--help'], code: 0);
      expect(_toolNames(result), contains('jira_get_ticket'),
          reason: 'bitrise is not a tracker carrier — first candidate wins');
    });
  });
}

/// tracker_* invocations route by the key hint extracted from the raw
/// arguments (dm.ai #577 `McpCliHandler.extractKeyHint` parity): a gh-N /
/// owner/repo#N payload routes to the GitHub carrier, a PROJ-123 payload
/// to Jira — regardless of DEFAULT_TRACKER. The unconfigured-integration
/// error envelope of the dispatched carrier proves the routing.
void _testAliasKeyHintRouting() {
  group('alias key-hint routing', () {
    test('a gh-N payload key routes tracker_get_ticket to GitHub', () async {
      final result = await _dispatchTool(
        ['tracker_get_ticket', '{"key":"gh-42"}'],
      );
      expect(result, containsPair('error', 'GitHub not configured'));
    });

    test('a PROJ-123 payload key routes tracker_get_ticket to Jira', () async {
      final result = await _dispatchTool(
        ['tracker_get_ticket', '{"key":"PROJ-123"}'],
      );
      expect(result, containsPair('error', 'Jira not configured'));
    });

    test('the GitHub key hint beats DEFAULT_TRACKER', () async {
      PropertyReader.setOverrides({'DEFAULT_TRACKER': 'jira'});
      final result = await _dispatchTool(
        ['tracker_get_ticket', '{"key":"epam/dm.ai#42"}'],
      );
      expect(result, containsPair('error', 'GitHub not configured'));
    });
  });
}
