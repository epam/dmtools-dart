import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/github_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';
import 'github_fixture_helper.dart';

// Tests for the search / move-to-status / create-issue / assign paths of
// [GitHubIssueSyncTools] the CRAP gate flagged, split out of
// github_ci_sync_tools_test.dart (loc limit) to mirror the source
// layout. Fixture wiring matches the CI-tools suite; the scripted
// GitHub fixture subprocess serves the flows and a generic JSON echo
// records the single-request writes.

late GithubFixtureServer fx;
late GitHubSyncTools tools;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  if (hasPython3()) {
    _fixtureGroups();
  }
}

void _fixtureGroups() {
  group('GitHubIssueSyncTools search (fixture)', _searchIssuesTests);
  group('GitHubIssueSyncTools move-to-status (fixture)', _moveStatusTests);
  group('GitHubIssueSyncTools create issue (fixture)', _createIssueTests);
  group('GitHubIssueSyncTools ref resolution (fixture)', _issueRefTests);
}

/// Fixture config for workspace/repository `o`/`r` (plus the `err`
/// variant the search route serves).
Future<void> _startFixture() async {
  fx = GithubFixtureServer();
  await fx.start();
  PropertyReader.setOverrides({
    'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
    'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${fx.port}',
    'SOURCE_GITHUB_WORKSPACE': 'o',
    'SOURCE_GITHUB_REPOSITORY': 'r',
  });
  tools = const GitHubSyncTools();
}

void _stopFixture() {
  PropertyReader.clearOverrides();
  fx.stop();
}

/// Runs one handler through the config-resolving dispatch layer.
String _call(String name, Map<String, dynamic> args) {
  final handler = const GitHubSyncTools().handlers[name];
  if (handler == null) throw StateError('missing handler $name');
  return handler(args);
}

/// The last recorded fixture request as `{method, path, headers, body}`.
Map<String, dynamic> get _lastRequest =>
    jsonDecode(fx.lastRequestJson!) as Map<String, dynamic>;

void _searchIssuesTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);

  test('github_search_issues scopes the query with the configured repo', () {
    final raw = _call('github_search_issues', {'query': 'is:open'});
    final q = Uri.parse(_lastRequest['path'] as String).queryParameters['q']!;
    expect(q, 'repo:o/r is:open');
    expect(_lastRequest['path'], contains('per_page=100'));
    final body = jsonDecode(raw) as Map<String, dynamic>;
    expect(body['total_count'], 1);
  });

  test('github_search_issues keeps an existing repo: term untouched', () {
    _call('github_search_issues', {'query': 'repo:other/x is:open'});
    expect(
      Uri.parse(_lastRequest['path'] as String).queryParameters['q'],
      'repo:other/x is:open',
    );
  });

  test('github_search_issues prefers explicit workspace/repository', () {
    _call('github_search_issues', {
      'query': 'is:open',
      'workspace': 'w',
      'repository': 'p',
    });
    expect(
      Uri.parse(_lastRequest['path'] as String).queryParameters['q'],
      'repo:w/p is:open',
    );
  });

  test('github_search_issues skips scoping without defaults', () {
    // setOverrides replaces the whole map — keep the fixture wiring.
    PropertyReader.setOverrides({
      'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
      'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${fx.port}',
      'SOURCE_GITHUB_WORKSPACE': '',
      'SOURCE_GITHUB_REPOSITORY': '',
    });
    _call('github_search_issues', {'query': 'is:open'});
    expect(
      Uri.parse(_lastRequest['path'] as String).queryParameters['q'],
      'is:open',
    );
  });

  test('github_search_issues passes a failed page through', () {
    final raw = _call('github_search_issues', {'query': 'boom'});
    expect(raw, '{"message": "search boom"}');
  });
}

void _moveStatusTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);
  _moveStatusTestsP1();
  _moveStatusTestsP2();
}

/// Move-to-status: validation and state synonyms.
void _moveStatusTestsP1() {
  test('github_move_issue_to_status requires statusName', () {
    final raw = _call('github_move_issue_to_status', {
      'owner': 'o',
      'repo': 'r',
      'number': 50,
    });
    expect(jsonDecode(raw), {'error': 'statusName is required'});
  });

  test('github_move_issue_to_status closes on a closed synonym', () {
    _call('github_move_issue_to_status', {
      'owner': 'o',
      'repo': 'r',
      'number': 50,
      'statusName': 'Done',
    });
    expect(_lastRequest['method'], 'PATCH');
    expect(_lastRequest['path'], '/repos/o/r/issues/50');
    expect(jsonDecode(_lastRequest['body'] as String), {'state': 'closed'});
  });

  test('github_move_issue_to_status reopens on an open synonym', () {
    _call('github_move_issue_to_status', {
      'owner': 'o',
      'repo': 'r',
      'number': 50,
      'statusName': 'todo',
    });
    expect(_lastRequest['method'], 'PATCH');
    expect(jsonDecode(_lastRequest['body'] as String), {'state': 'open'});
  });
}

/// Move-to-status: labeling and ref errors.
void _moveStatusTestsP2() {
  test('github_move_issue_to_status labels any other status', () {
    _call('github_move_issue_to_status', {
      'owner': 'o',
      'repo': 'r',
      'number': 50,
      'statusName': 'QA',
    });
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/o/r/issues/50/labels');
    expect(
      jsonDecode(_lastRequest['body'] as String),
      {
        'labels': ['QA']
      },
    );
  });

  test('github_move_issue_to_status surfaces the ref error', () {
    final raw = _call('github_move_issue_to_status', {
      'owner': 'o',
      'repo': 'r',
      'statusName': 'Done',
    });
    expect(jsonDecode(raw), {
      'error': "Issue reference requires owner/repo/number or a composite "
          "key 'owner/repo#123'.",
    });
  });
}

void _createIssueTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);
  _createIssueTestsP1();
  _createIssueTestsP2();
}

/// Create-issue body shaping and project keys.
void _createIssueTestsP1() {
  test('github_create_issue posts title and body when body is non-blank', () {
    _call('github_create_issue', {
      'owner': 'o',
      'repo': 'r',
      'title': 'Bug',
      'body': 'steps to reproduce',
    });
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/o/r/issues');
    expect(jsonDecode(_lastRequest['body'] as String), {
      'title': 'Bug',
      'body': 'steps to reproduce',
    });
  });

  test('github_create_issue omits a blank body', () {
    _call('github_create_issue', {
      'owner': 'o',
      'repo': 'r',
      'title': 'Bug',
      'body': '   ',
    });
    expect(jsonDecode(_lastRequest['body'] as String), {'title': 'Bug'});
  });

  test('github_create_issue mixes explicit owner with the default repo', () {
    _call('github_create_issue', {'owner': 'w', 'title': 'Bug'});
    expect(_lastRequest['path'], '/repos/w/r/issues');
  });
}

/// Create-issue ref errors and assign routing.
void _createIssueTestsP2() {
  test('github_create_issue ignores a key without a slash', () {
    // Java treats the key as a composite project reference only when it
    // carries owner/repo — a plain word falls through to the defaults.
    _call('github_create_issue', {'key': 'plainproject', 'title': 'Bug'});
    expect(_lastRequest['path'], '/repos/o/r/issues');
  });

  test('github_create_issue accepts the composite project key', () {
    _call('github_create_issue', {'key': 'myorg/myrepo', 'title': 'Bug'});
    expect(_lastRequest['path'], '/repos/myorg/myrepo/issues');
    expect(jsonDecode(_lastRequest['body'] as String), {'title': 'Bug'});
  });

  test('github_create_issue without any repo reference fails', () {
    // setOverrides replaces the whole map — keep the fixture wiring.
    PropertyReader.setOverrides({
      'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
      'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${fx.port}',
      'SOURCE_GITHUB_WORKSPACE': '',
      'SOURCE_GITHUB_REPOSITORY': '',
    });
    final raw = _call('github_create_issue', {'title': 'Bug'});
    expect(jsonDecode(raw), {
      'error': "github_create_issue requires owner/repo or a composite "
          "key/project 'owner/repo'.",
    });
  });

  test('github_assign_issue POSTs the assignees list', () {
    _call('github_assign_issue', {
      'owner': 'o',
      'repo': 'r',
      'number': 50,
      'user': 'octocat',
    });
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/o/r/issues/50/assignees');
    expect(jsonDecode(_lastRequest['body'] as String), {
      'assignees': ['octocat'],
    });
  });
}

void _issueRefTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);
  _issueRefTestsP1();
  _issueRefTestsP2();
}

/// Issue-ref resolution: number spellings and defaults.
void _issueRefTestsP1() {
  test('issue tools accept the pullRequestId number spelling', () {
    _call('github_close_issue', {
      'workspace': 'o',
      'repository': 'r',
      'pullRequestId': '50',
    });
    expect(_lastRequest['path'], '/repos/o/r/issues/50');
  });

  test('issue tools accept double and string number spellings', () {
    _call('github_close_issue', {
      'owner': 'o',
      'repo': 'r',
      'number': 50.0,
    });
    expect(_lastRequest['path'], '/repos/o/r/issues/50');

    _call('github_reopen_issue', {
      'owner': 'o',
      'repo': 'r',
      'number': '51',
    });
    expect(_lastRequest['path'], '/repos/o/r/issues/51');
  });

  test('issue tools resolve a bare number through the defaults', () {
    _call('github_get_issue', {'key': '9'});
    expect(_lastRequest['path'], '/repos/o/r/issues/9');
  });
}

/// Issue-ref resolution: key errors and composite routing.
void _issueRefTestsP2() {
  test('a gh- prefixed key is rejected by the sync family', () {
    // Java resolveIssueRef in the SYNC surface accepts composite and
    // bare-number keys; the gh- spelling is the async client's dialect.
    final raw = _call('github_get_issue', {
      'owner': 'o',
      'repo': 'r',
      'key': 'gh-12',
    });
    expect(jsonDecode(raw), {
      'error': "Cannot parse GitHub issue key: 'gh-12'. Expected "
          "'owner/repo#123' or a bare issue number.",
    });
  });

  test('a non-numeric number argument falls back to the ref error', () {
    final raw = _call('github_get_issue', {
      'owner': 'o',
      'repo': 'r',
      'number': 'abc',
    });
    expect(jsonDecode(raw), {
      'error': "Issue reference requires owner/repo/number or a composite "
          "key 'owner/repo#123'.",
    });
  });

  test('composite keys route through the sync issue tools', () {
    _call('github_add_labels', {
      'key': 'myorg/myrepo#5',
      'labels': ['bug'],
    });
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/myorg/myrepo/issues/5/labels');
  });
}
