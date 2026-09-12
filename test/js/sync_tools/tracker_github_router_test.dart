import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:dmtools/src/js/sync_tools/jira_sync_tools.dart';
import 'package:dmtools/src/js/sync_tools/tracker_github_router.dart';
import 'package:dmtools/src/js/tool_bridge.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';
import 'github_fixture_helper.dart';

/// Tests for [TrackerGitHubRouter] — the gh-N → GitHub Issues routing of
/// tracker-shaped `jira_*` calls when Jira is unconfigured (gh-62).
///
/// The routing-decision groups run without HTTP: a fired route with no
/// GitHub config surfaces the config error envelope; a suppressed route
/// returns `null`. Server-dependent tests use the scripted GitHub fixture
/// subprocess (see `github_fixture_server.py`) because Dart's HttpServer
/// runs on the event loop, frozen during `Process.runSync('curl', …)`.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _keyShapeTests();
  group('TrackerGitHubRouter routing fires', _routingFireTests);
  group('TrackerGitHubRouter routing suppressed', _routingSuppressTests);
  group('TrackerGitHubRouter dispatch logging', _routingLogTests);
  if (hasPython3()) {
    group('TrackerGitHubRouter read tools (fixture)', _fixtureReadTools);
    group('TrackerGitHubRouter label tools (fixture)', _fixtureLabelTools);
    group('TrackerGitHubRouter status tools (fixture)', _fixtureStatusTools);
    group('TrackerGitHubRouter search tools (fixture)', _fixtureSearchTools);
    group(
        'TrackerGitHubRouter search clauses (fixture)', _fixtureSearchClauses);
    group('TrackerGitHubRouter entry points (fixture)', _fixtureEntryPoints);
    group('TrackerGitHubRouter opt-in (Jira configured)', _optInTests);
  }
}

/// Decodes the `{"error": …}` envelope of a routed result.
String _errOf(String result) =>
    (jsonDecode(result) as Map<String, dynamic>)['error'] as String;

/// Pure key-shape tests for the `gh-<number>` pattern.
void _keyShapeTests() {
  group('TrackerGitHubRouter.ghIssueNumber', () {
    test('accepts gh-<number> keys', () {
      expect(TrackerGitHubRouter.ghIssueNumber('gh-50'), '50');
      expect(TrackerGitHubRouter.ghIssueNumber('gh-1'), '1');
    });

    test('rejects non-gh keys', () {
      expect(TrackerGitHubRouter.ghIssueNumber('PROJ-123'), isNull);
      expect(TrackerGitHubRouter.ghIssueNumber('gh-'), isNull);
      expect(TrackerGitHubRouter.ghIssueNumber('gh-5x'), isNull);
      expect(TrackerGitHubRouter.ghIssueNumber('GH-5'), isNull);
      expect(TrackerGitHubRouter.ghIssueNumber('a gh-5'), isNull);
      expect(TrackerGitHubRouter.ghIssueNumber(50), isNull);
      expect(TrackerGitHubRouter.ghIssueNumber(null), isNull);
    });
  });
}

/// Routing-decision tests where the route fires (no HTTP: the missing
/// GitHub config error proves the route was taken).
void _routingFireTests() {
  tearDown(PropertyReader.clearOverrides);

  test('gh key + no Jira config fires the route', () {
    PropertyReader.setOverrides(const {});
    final result = const TrackerGitHubRouter().maybeRoute('jira_add_label', {
      'key': 'gh-50',
      'label': 'pr_approved',
    });
    expect(result, isNotNull);
    expect(_errOf(result!), contains('SOURCE_GITHUB_TOKEN'));
  });

  test('Jira base path without a token still routes', () {
    PropertyReader.setOverrides(const {
      'JIRA_BASE_PATH': 'https://jira.example.com',
    });
    final result = const TrackerGitHubRouter().maybeRoute('jira_get_ticket', {
      'key': 'gh-50',
    });
    expect(result, isNotNull);
    expect(_errOf(result!), contains('SOURCE_GITHUB_TOKEN'));
  });

  test('jira_search_by_jql routes when Jira is unconfigured', () {
    PropertyReader.setOverrides(const {});
    final result =
        const TrackerGitHubRouter().maybeRoute('jira_search_by_jql', {
      'jql': 'labels = agent:review',
    });
    expect(result, isNotNull);
    expect(_errOf(result!), contains('SOURCE_GITHUB_TOKEN'));
  });
}

/// Routing-decision tests where the route must stay silent (`null`).
void _routingSuppressTests() {
  tearDown(PropertyReader.clearOverrides);

  test('gh key + Jira configured falls through to Jira', () {
    PropertyReader.setOverrides(const {
      'JIRA_BASE_PATH': 'https://jira.example.com',
      'JIRA_LOGIN_PASS_TOKEN': 'dG9rZW4=',
    });
    final result = const TrackerGitHubRouter().maybeRoute('jira_add_label', {
      'key': 'gh-50',
      'label': 'pr_approved',
    });
    expect(result, isNull);
  });

  test('non-gh key does not route', () {
    PropertyReader.setOverrides(const {});
    expect(
      const TrackerGitHubRouter().maybeRoute('jira_add_label', {
        'key': 'PROJ-1',
        'label': 'x',
      }),
      isNull,
    );
  });

  test('non-routable tool with a gh key does not route', () {
    PropertyReader.setOverrides(const {});
    expect(
      const TrackerGitHubRouter().maybeRoute('jira_delete_ticket', {
        'key': 'gh-1',
      }),
      isNull,
    );
  });

  test('jira_search_by_jql does not route when Jira is configured', () {
    PropertyReader.setOverrides(const {
      'JIRA_BASE_PATH': 'https://jira.example.com',
      'JIRA_LOGIN_PASS_TOKEN': 'dG9rZW4=',
    });
    expect(
      const TrackerGitHubRouter().maybeRoute('jira_search_by_jql', {
        'jql': 'labels = agent:review',
      }),
      isNull,
    );
  });
}

/// The one-line dispatch log contract.
void _routingLogTests() {
  tearDown(PropertyReader.clearOverrides);

  test('logs one line at dispatch', () {
    PropertyReader.setOverrides(const {});
    final lines = <String>[];
    final router = TrackerGitHubRouter(logger: lines.add);
    router.maybeRoute('jira_add_label', {'key': 'gh-7', 'label': 'x'});
    router.maybeRoute('jira_search_by_jql', {'jql': ''});
    expect(lines, [
      'tracker: gh-7 → github issues',
      'tracker: jira_search_by_jql → github issues',
    ]);
  });

  test('logs nothing when the route is suppressed', () {
    PropertyReader.setOverrides(const {
      'JIRA_BASE_PATH': 'https://jira.example.com',
      'JIRA_LOGIN_PASS_TOKEN': 'dG9rZW4=',
    });
    final lines = <String>[];
    TrackerGitHubRouter(logger: lines.add)
        .maybeRoute('jira_add_label', {'key': 'gh-7', 'label': 'x'});
    expect(lines, isEmpty);
  });
}

/// GitHub config shared by the fixture groups: Jira absent, GitHub
/// pointing at the fixture server.
Map<String, String> _githubOverrides(int port) => {
      'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:$port',
      'SOURCE_GITHUB_TOKEN': 'ghp-test',
      'GITHUB_REPOSITORY': 'o/r',
    };

/// Harness for the fixture groups: starts the scripted GitHub fixture
/// server and points the GitHub env at it (Jira stays unconfigured).
class _Fixture {
  late GithubFixtureServer server;
  final tools = const JiraSyncTools();

  Future<void> start() async {
    server = GithubFixtureServer();
    await server.start();
    PropertyReader.setOverrides(_githubOverrides(server.port));
  }

  void stop() {
    PropertyReader.clearOverrides();
    server.stop();
  }
}

/// L2-style fixture tests: canned GitHub API shapes served by
/// `github_fixture_server.py`, asserted against the request log.
void _fixtureReadTools() {
  final fx = _Fixture();
  setUp(fx.start);
  tearDown(fx.stop);

  test('jira_get_ticket maps the issue to the ticket contract', () {
    final ticket = jsonDecode(fx.tools.dispatch('jira_get_ticket', {
      'key': 'gh-50',
    })) as Map<String, dynamic>;
    expect(ticket['key'], 'gh-50');
    final fields = ticket['fields'] as Map<String, dynamic>;
    expect(fields['summary'], 'Route gh-N tracker ops');
    expect(fields['description'], 'issue body text');
    expect(fields['labels'], ['agent:review', 'status:In Progress']);
    expect((fields['status'] as Map<String, dynamic>)['name'], 'In Progress');
    expect(fx.server.requests, contains('GET /repos/o/r/issues/50'));
  });

  test('jira_get_comments maps the Jira comments envelope', () {
    final result = jsonDecode(fx.tools.dispatch('jira_get_comments', {
      'key': 'gh-50',
    })) as Map<String, dynamic>;
    final comments = result['comments'] as List;
    expect(comments, hasLength(2));
    final first = comments.first as Map<String, dynamic>;
    expect(first['body'], 'first comment');
    expect((first['author'] as Map<String, dynamic>)['displayName'], 'octocat');
    expect(first['created'], '2024-01-01T00:00:00Z');
    expect(fx.server.requests,
        contains('GET /repos/o/r/issues/50/comments?per_page=100'));
  });

  test('jira_post_comment posts the body and maps the created comment', () {
    final created = jsonDecode(fx.tools.dispatch('jira_post_comment', {
      'key': 'gh-50',
      'comment': 'hello world',
    })) as Map<String, dynamic>;
    expect(created['body'], 'hello world');
    final request =
        jsonDecode(fx.server.lastRequestJson!) as Map<String, dynamic>;
    expect(request['method'], 'POST');
    expect(request['path'], '/repos/o/r/issues/50/comments');
    expect(jsonDecode(request['body'] as String), {'body': 'hello world'});
  });
}

/// Label add/remove mappings, including the absent-label tolerance.
void _fixtureLabelTools() {
  final fx = _Fixture();
  setUp(fx.start);
  tearDown(fx.stop);

  test('jira_add_label posts the labels array', () {
    final result = fx.tools.dispatch('jira_add_label', {
      'key': 'gh-50',
      'label': 'pr_approved',
    });
    expect((jsonDecode(result) as Map).containsKey('error'), isFalse);
    final request =
        jsonDecode(fx.server.lastRequestJson!) as Map<String, dynamic>;
    expect(request['method'], 'POST');
    expect(request['path'], '/repos/o/r/issues/50/labels');
    expect(
      jsonDecode(request['body'] as String),
      {
        'labels': ['pr_approved']
      },
    );
  });

  test('jira_remove_label deletes the label', () {
    final result = jsonDecode(fx.tools.dispatch('jira_remove_label', {
      'key': 'gh-50',
      'label': 'agent:review',
    }));
    expect(result, '');
    expect(fx.server.requests,
        contains('DELETE /repos/o/r/issues/50/labels/agent%3Areview'));
  });

  test('jira_remove_label tolerates an absent label (404)', () {
    final result = jsonDecode(fx.tools.dispatch('jira_remove_label', {
      'key': 'gh-50',
      'label': 'missing',
    }));
    expect(result, '');
    expect(fx.server.requests,
        contains('DELETE /repos/o/r/issues/50/labels/missing'));
  });
}

/// The `jira_move_to_status` label swap plus close/reopen state mapping.
void _fixtureStatusTools() {
  final fx = _Fixture();
  setUp(fx.start);
  tearDown(fx.stop);

  test('jira_move_to_status swaps the status label and closes on Done', () {
    final result = jsonDecode(fx.tools.dispatch('jira_move_to_status', {
      'key': 'gh-50',
      'status': 'Done',
    }));
    expect(result, '');
    expect(fx.server.requests, [
      'GET /repos/o/r/issues/50',
      'DELETE /repos/o/r/issues/50/labels/status%3AIn%20Progress',
      'POST /repos/o/r/issues/50/labels',
      'PATCH /repos/o/r/issues/50',
    ]);
    final request =
        jsonDecode(fx.server.lastRequestJson!) as Map<String, dynamic>;
    expect(jsonDecode(request['body'] as String), {'state': 'closed'});
  });

  test('jira_move_to_status with a neutral name is label-only', () {
    jsonDecode(fx.tools.dispatch('jira_move_to_status', {
      'key': 'gh-50',
      'status': 'Selected for Development',
    }));
    expect(fx.server.requests, [
      'GET /repos/o/r/issues/50',
      'DELETE /repos/o/r/issues/50/labels/status%3AIn%20Progress',
      'POST /repos/o/r/issues/50/labels',
    ]);
  });

  test('jira_move_to_status reopens a closed issue on an Open-ish name', () {
    jsonDecode(fx.tools.dispatch('jira_move_to_status', {
      'key': 'gh-61',
      'status': 'Ready For Development',
    }));
    expect(fx.server.requests, [
      'GET /repos/o/r/issues/61',
      'DELETE /repos/o/r/issues/61/labels/status%3ADone',
      'POST /repos/o/r/issues/61/labels',
      'PATCH /repos/o/r/issues/61',
    ]);
    final request =
        jsonDecode(fx.server.lastRequestJson!) as Map<String, dynamic>;
    expect(jsonDecode(request['body'] as String), {'state': 'open'});
  });
}

/// The best-effort `jira_search_by_jql` mapping and the repo env chain.
void _fixtureSearchTools() {
  final fx = _Fixture();
  setUp(fx.start);
  tearDown(fx.stop);

  test('jira_search_by_jql maps label/status filters, drops PRs', () {
    final result = jsonDecode(fx.tools.dispatch('jira_search_by_jql', {
      'jql': 'labels = agent:review AND status = Open',
    })) as List;
    expect(
      fx.server.requests,
      contains(
        'GET /repos/o/r/issues?labels=agent%3Areview&state=open'
        '&per_page=100',
      ),
    );
    expect(result, hasLength(2));
    final keys = result
        .map((t) => (t as Map<String, dynamic>)['key'] as String)
        .toList();
    expect(keys, ['gh-50', 'gh-70']);
    final closed = result.last as Map<String, dynamic>;
    expect(((closed['fields'] as Map)['status'] as Map)['name'], 'Done');
  });

  test('jira_search_by_jql with a key filter fetches the issues', () {
    final result = jsonDecode(fx.tools.dispatch('jira_search_by_jql', {
      'jql': 'key in (gh-50, gh-61)',
    })) as List;
    expect(result.map((t) => (t as Map)['key']), ['gh-50', 'gh-61']);
    expect(fx.server.requests, contains('GET /repos/o/r/issues/50'));
    expect(fx.server.requests, contains('GET /repos/o/r/issues/61'));
  });
}

/// Assignee clauses, unsupported-JQL honesty, and the repo env chain.
void _fixtureSearchClauses() {
  final fx = _Fixture();
  setUp(fx.start);
  tearDown(fx.stop);

  test('jira_search_by_jql maps assignee and Done-ish status filters', () {
    jsonDecode(fx.tools.dispatch('jira_search_by_jql', {
      'jql': "assignee = 'octocat' AND status = Done",
    }));
    expect(
      fx.server.requests,
      contains(
        'GET /repos/o/r/issues?state=closed&assignee=octocat&per_page=100',
      ),
    );
  });

  test('jira_search_by_jql rejects currentUser() honestly', () {
    final error = _errOf(fx.tools.dispatch('jira_search_by_jql', {
      'jql': 'assignee = currentUser()',
    }));
    expect(error, contains('unsupported JQL for GitHub tracker routing'));
  });

  test('jira_search_by_jql reports unsupported JQL honestly', () {
    final error = _errOf(fx.tools.dispatch('jira_search_by_jql', {
      'jql': 'project = DMT AND labels = agent:review',
    }));
    expect(error, contains('unsupported JQL for GitHub tracker routing'));
    expect(error, contains('project = DMT'));
  });

  test('DMTOOLS_TRACKER_REPO wins over GITHUB_REPOSITORY', () {
    PropertyReader.setOverrides({
      ..._githubOverrides(fx.server.port),
      'DMTOOLS_TRACKER_REPO': 'x/y',
    });
    fx.tools.dispatch('jira_get_ticket', {'key': 'gh-50'});
    expect(fx.server.requests, contains('GET /repos/x/y/issues/50'));
  });
}

/// The routing must behave identically through every dispatch entry
/// point the agents use (JS bridge, CLI direct dispatch, wrappers).
void _fixtureEntryPoints() {
  final fx = _Fixture();
  setUp(fx.start);
  tearDown(fx.stop);

  test('routes through SyncToolDispatcher (the machine entry point)', () {
    final dispatcher = SyncToolDispatcher(PropertyReader());
    final result = dispatcher.execute('jira_move_to_status', {
      'key': 'gh-50',
      'status': 'In Review',
    });
    expect(jsonDecode(result!), '');
    expect(fx.server.requests, contains('POST /repos/o/r/issues/50/labels'));
  });

  test('routes through ToolBridge (JS bridge / CLI direct dispatch)', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    bridge.execute('jira_add_label', {
      'key': 'gh-50',
      'label': 'pr_approved',
    });
    expect(fx.server.requests, contains('POST /repos/o/r/issues/50/labels'));
  });
}

/// The opt-in rule: with a real Jira config, gh-N calls keep the Jira
/// path — zero regression for Java-parity environments.
void _optInTests() {
  late GithubFixtureServer fx;
  const tools = JiraSyncTools();

  setUp(() async {
    fx = GithubFixtureServer();
    await fx.start();
    PropertyReader.setOverrides({
      ..._githubOverrides(fx.port),
      'JIRA_BASE_PATH': 'http://127.0.0.1:${fx.port}',
      'JIRA_LOGIN_PASS_TOKEN': 'dG9rZW4=',
    });
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    fx.stop();
  });

  test('jira_add_label on gh-50 hits Jira, not GitHub', () {
    tools.dispatch('jira_add_label', {
      'key': 'gh-50',
      'label': 'pr_approved',
    });
    expect(
      fx.requests,
      contains('GET /rest/api/latest/issue/gh-50?fields=labels'),
    );
    expect(
      fx.requests,
      contains('PUT /rest/api/latest/issue/gh-50'),
    );
    expect(
      fx.requests.where((r) => r.contains('/repos/')),
      isEmpty,
    );
  });
}
