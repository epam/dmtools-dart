import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/github_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';
import 'github_fixture_helper.dart';

// Tests for [GitHubCiSyncTools] — the CI/PR-activity sync executors —
// plus the search/move/create paths of the issue family the CRAP gate
// flagged. Fixture wiring mirrors github_sync_tools_test.dart: the
// scripted GitHub fixture subprocess serves the multi-request flows
// (paginated branches/commits/listings) and a generic JSON echo for
// the single-request write tools.

late GithubFixtureServer fx;
late GitHubSyncTools tools;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  _registryTests();
  if (hasPython3()) {
    _fixtureGroups();
  }
}

/// The 12-handler CI surface, keyed by Java tool name.
void _registryTests() {
  group('GitHubCiSyncTools.handlers', () {
    test('registers every CI/PR-activity tool', () {
      final names = const GitHubCiSyncTools().handlers.keys.toSet();
      expect(
        names,
        containsAll(const [
          'github_create_check_run',
          'github_update_check_run',
          'github_create_commit_status',
          'github_get_workflow_run',
          'github_repository_dispatch',
          'github_update_pr_comment',
          'github_delete_pr_comment',
          'github_get_pr_activities',
          'github_list_prs_filtered',
          'github_list_release_assets',
          'github_delete_release_asset',
          'github_get_commits_from_branches',
        ]),
      );
    });
  });
}

void _fixtureGroups() {
  group('GitHubCiSyncTools check runs (fixture)', _checkRunTests);
  group('GitHubCiSyncTools status/dispatch (fixture)', _statusDispatchTests);
  group('GitHubCiSyncTools PR comments (fixture)', _prCommentTests);
  group('GitHubCiSyncTools PR activities (fixture)', _prActivityTests);
  group('GitHubCiSyncTools filtered listing (fixture)', _filteredPrsTests);
  group('GitHubCiSyncTools release assets (fixture)', _releaseTests);
  group('GitHubCiSyncTools branch commits (fixture)', _branchCommitTests);
  group('GitHubIssueSyncTools search (fixture)', _searchIssuesTests);
  group('GitHubIssueSyncTools move-to-status (fixture)', _moveStatusTests);
  group('GitHubIssueSyncTools create issue (fixture)', _createIssueTests);
  group('GitHubIssueSyncTools ref resolution (fixture)', _issueRefTests);
}

/// Fixture config for workspace/repository `o`/`r` (plus the specialized
/// `pager`/`err`/`errc`/`bad`/`nl` variants the CI routes serve).
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

void _checkRunTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);
  _checkRunTestsP1();
  _checkRunTestsP2();
}

/// Check-run create-side body shaping.
void _checkRunTestsP1() {
  test('github_create_check_run sends the full shaped body', () {
    final raw = _call('github_create_check_run', {
      'workspace': 'o',
      'repository': 'r',
      'name': 'dmtools / review',
      'headSha': 'abc123',
      'status': 'in_progress',
      'title': 'AI Review',
      'summary': 'started',
      'text': 'all good',
      'externalId': 'KEY-1',
    });
    final sent = jsonDecode(_lastRequest['body'] as String);
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/o/r/check-runs');
    expect(sent, {
      'name': 'dmtools / review',
      'head_sha': 'abc123',
      'status': 'in_progress',
      'external_id': 'KEY-1',
      'output': {
        'title': 'AI Review',
        'summary': 'started',
        'text': 'all good',
      },
    });
    // The tool returns the fixture echo — the request shape is the assert.
    expect(jsonDecode(raw)['path'], '/repos/o/r/check-runs');
  });

  test('github_create_check_run defaults the output title to the name', () {
    _call('github_create_check_run', {
      'workspace': 'o',
      'repository': 'r',
      'name': 'review',
      'headSha': 'abc123',
      'summary': 'only summary',
    });
    expect(jsonDecode(_lastRequest['body'] as String), {
      'name': 'review',
      'head_sha': 'abc123',
      'output': {'title': 'review', 'summary': 'only summary'},
    });
  });

  test('github_create_check_run omits output without title and summary', () {
    _call('github_create_check_run', {
      'workspace': 'o',
      'repository': 'r',
      'name': 'review',
      'headSha': 'abc123',
      'text': 'orphan text',
    });
    expect(jsonDecode(_lastRequest['body'] as String), {
      'name': 'review',
      'head_sha': 'abc123',
    });
  });
}

/// Check-run update-side body shaping.
void _checkRunTestsP2() {
  test('github_update_check_run PATCHes status/conclusion/output', () {
    _call('github_update_check_run', {
      'workspace': 'o',
      'repository': 'r',
      'checkRunId': '9',
      'status': 'completed',
      'conclusion': 'success',
      'title': 'done',
      'summary': 'ok',
      'text': 'all',
    });
    expect(_lastRequest['method'], 'PATCH');
    expect(_lastRequest['path'], '/repos/o/r/check-runs/9');
    expect(jsonDecode(_lastRequest['body'] as String), {
      'status': 'completed',
      'conclusion': 'success',
      'output': {'title': 'done', 'summary': 'ok', 'text': 'all'},
    });
  });

  test('github_update_check_run omits blank conclusion and blank text', () {
    _call('github_update_check_run', {
      'workspace': 'o',
      'repository': 'r',
      'checkRunId': '9',
      'status': 'in_progress',
      'text': '   ',
    });
    // Blank text must NOT be sent — only non-blank output fields go.
    expect(jsonDecode(_lastRequest['body'] as String), {
      'status': 'in_progress',
    });
  });
}

void _statusDispatchTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);
  _statusDispatchTestsP1();
  _statusDispatchTestsP2();
}

/// Commit-status, workflow-run, and dispatch write tools.
void _statusDispatchTestsP1() {
  test('github_create_commit_status POSTs the shaped body', () {
    _call('github_create_commit_status', {
      'workspace': 'o',
      'repository': 'r',
      'sha': 'abc123',
      'state': 'success',
      'targetUrl': 'https://ci/run/1',
      'description': 'tests passed',
      'context': 'ci/tests',
    });
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/o/r/statuses/abc123');
    expect(jsonDecode(_lastRequest['body'] as String), {
      'state': 'success',
      'target_url': 'https://ci/run/1',
      'description': 'tests passed',
      'context': 'ci/tests',
    });
  });

  test('github_create_commit_status omits blank optional fields', () {
    _call('github_create_commit_status', {
      'workspace': 'o',
      'repository': 'r',
      'sha': 'abc123',
      'state': 'failure',
    });
    expect(jsonDecode(_lastRequest['body'] as String), {'state': 'failure'});
  });

  test('github_get_workflow_run GETs the actions run endpoint', () {
    _call('github_get_workflow_run', {
      'workspace': 'o',
      'repository': 'r',
      'runId': '55',
    });
    expect(_lastRequest['method'], 'GET');
    expect(_lastRequest['path'], '/repos/o/r/actions/runs/55');
  });
}

/// Repository-dispatch payload handling.
void _statusDispatchTestsP2() {
  test('github_repository_dispatch decodes client_payload JSON', () {
    _call('github_repository_dispatch', {
      'workspace': 'o',
      'repository': 'r',
      'eventType': 'rebuild',
      'clientPayload': '{"ticket":"gh-35","n":2}',
    });
    expect(_lastRequest['method'], 'POST');
    expect(_lastRequest['path'], '/repos/o/r/dispatches');
    expect(jsonDecode(_lastRequest['body'] as String), {
      'event_type': 'rebuild',
      'client_payload': {'ticket': 'gh-35', 'n': 2},
    });
  });

  test('github_repository_dispatch omits a blank payload', () {
    _call('github_repository_dispatch', {
      'workspace': 'o',
      'repository': 'r',
      'eventType': 'ping',
    });
    expect(
      jsonDecode(_lastRequest['body'] as String),
      {'event_type': 'ping'},
    );
  });

  test('github_repository_dispatch rejects invalid clientPayload JSON', () {
    final raw = _call('github_repository_dispatch', {
      'workspace': 'o',
      'repository': 'r',
      'eventType': 'rebuild',
      'clientPayload': '{not json',
    });
    expect(jsonDecode(raw), {
      'error': "Invalid clientPayload JSON: '{not json'",
    });
  });
}

void _prCommentTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);

  test('github_update_pr_comment PATCHes the issue comment body', () {
    _call('github_update_pr_comment', {
      'workspace': 'o',
      'repository': 'r',
      'commentId': '5',
      'text': 'edited body',
    });
    expect(_lastRequest['method'], 'PATCH');
    expect(_lastRequest['path'], '/repos/o/r/issues/comments/5');
    expect(
      jsonDecode(_lastRequest['body'] as String),
      {'body': 'edited body'},
    );
  });

  test('github_delete_pr_comment DELETEs the issue comment', () {
    _call('github_delete_pr_comment', {
      'workspace': 'o',
      'repository': 'r',
      'commentId': '5',
    });
    expect(_lastRequest['method'], 'DELETE');
    expect(_lastRequest['path'], '/repos/o/r/issues/comments/5');
  });
}

void _prActivityTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);

  test('github_get_pr_activities aggregates reviews and comment pages', () {
    final raw = _call('github_get_pr_activities', {
      'workspace': 'o',
      'repository': 'r',
      'pullRequestId': '42',
    });
    final activities = jsonDecode(raw) as List;
    // Review entry (raw map) + 3 inline comments + 1 discussion comment,
    // each comment wrapped as a COMMENTED activity.
    expect(activities, hasLength(5));
    expect(activities[0]['id'], 9);
    expect(activities[1]['action'], 'COMMENTED');
    expect(activities[1]['comment']['id'], 1);
    expect(activities.last['comment']['id'], 10);
  });

  test('github_get_pr_activities skips failed and non-list pages', () {
    // /repos/o/nl/pulls/77/... answers 200 with a JSON object for both
    // comment families and has no reviews page — best-effort means
    // skipped, not an error.
    final raw = _call('github_get_pr_activities', {
      'workspace': 'o',
      'repository': 'nl',
      'pullRequestId': '77',
    });
    expect(jsonDecode(raw), isEmpty);
  });

  test('github_get_pr_activities skips a non-OK inline page', () {
    // Pull 7's inline page 500s (fixture) — the family is best-effort.
    final raw = _call('github_get_pr_activities', {
      'workspace': 'o',
      'repository': 'r',
      'pullRequestId': '7',
    });
    expect(jsonDecode(raw), isEmpty);
  });

  test('github_get_pr_activities fails the tool on a strict page error', () {
    // Reviews are strict: a non-OK page fails the whole tool.
    final raw = _call('github_get_pr_activities', {
      'workspace': 'o',
      'repository': 'err',
      'pullRequestId': '77',
    });
    expect(
      jsonDecode(raw),
      {
        'error': 'HTTP 500 fetching comments (page 1): '
            '{"message": "reviews boom"}',
      },
    );
  });
}

void _filteredPrsTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);
  _filteredPrsTestsP1();
  _filteredPrsTestsP2();
}

/// Filtered PR listing: normalization and filtering.
void _filteredPrsTestsP1() {
  test('github_list_prs_filtered normalizes state and matches titles', () {
    final raw = _call('github_list_prs_filtered', {
      'workspace': 'o',
      'repository': 'r',
      'state': 'opened',
      'titleRegex': 'A|B',
    });
    expect(_lastRequest['path'], startsWith('/repos/o/r/pulls?state=open'));
    final prs = jsonDecode(raw) as List;
    expect(prs.map((p) => p['number']).toList(), [1, 2]);
  });

  test('github_list_prs_filtered keeps only merged PRs on merged state', () {
    final raw = _call('github_list_prs_filtered', {
      'workspace': 'o',
      'repository': 'r',
      'state': 'merged',
      'titleRegex': '.',
    });
    final prs = jsonDecode(raw) as List;
    expect(prs.map((p) => p['number']).toList(), [1]);
  });

  test('github_list_prs_filtered walks pages and filters non-maps', () {
    // o/pager: page 1 = 99 merged tNNN + one unmerged t-unmerged + …,
    // page 2 = one merged "final". The regex keeps only t0(01|50) and
    // the merged "final"; the unmerged and non-map entries drop out.
    final raw = _call('github_list_prs_filtered', {
      'workspace': 'o',
      'repository': 'pager',
      'state': 'closed',
      'titleRegex': r't0(01|50)|^final$',
    });
    final prs = jsonDecode(raw) as List;
    expect(prs.map((p) => p['number']).toList(), [1, 50, 100]);
    expect(_lastRequest['path'], contains('page=2'));
  });
}

/// Filtered PR listing: paging and error envelopes.
void _filteredPrsTestsP2() {
  test('github_list_prs_filtered errors on a failed page', () {
    final raw = _call('github_list_prs_filtered', {
      'workspace': 'o',
      'repository': 'err',
      'state': 'open',
      'titleRegex': '.',
    });
    expect(jsonDecode(raw), {
      'error': 'HTTP 500 listing pull requests (page 1): '
          '{"message": "boom"}',
    });
  });

  test('github_list_prs_filtered errors on a non-list payload', () {
    final raw = _call('github_list_prs_filtered', {
      'workspace': 'o',
      'repository': 'bad',
      'state': 'open',
      'titleRegex': '.',
    });
    expect(jsonDecode(raw), {'error': 'unexpected PR list payload'});
  });
}

void _releaseTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);

  test('github_list_release_assets GETs the release assets', () {
    final raw = _call('github_list_release_assets', {
      'workspace': 'o',
      'repository': 'r',
      'releaseId': '5',
    });
    expect(_lastRequest['path'], '/repos/o/r/releases/5/assets');
    final assets = jsonDecode(raw) as List;
    expect(assets.single['id'], 77);
  });

  test('github_delete_release_asset DELETEs the asset', () {
    _call('github_delete_release_asset', {
      'workspace': 'o',
      'repository': 'r',
      'assetId': '77',
    });
    expect(_lastRequest['method'], 'DELETE');
    expect(_lastRequest['path'], '/repos/o/r/releases/assets/77');
  });
}

void _branchCommitTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);

  test('github_get_commits_from_branches matches, dedupes, and pages', () {
    final raw = _call('github_get_commits_from_branches', {
      'workspace': 'o',
      'repository': 'r',
      'branchNameRegex': r'^match-',
    });
    final commits = jsonDecode(raw) as List;
    // c1/c2 from match-a (null sha skipped), c2 deduped from match-b,
    // c3 new — and the 100-commit paged branch is regex-excluded.
    expect(commits.map((c) => c['sha']).toList(), ['c1', 'c2', 'c3']);
  });

  test('github_get_commits_from_branches walks branch commit pages', () {
    final raw = _call('github_get_commits_from_branches', {
      'workspace': 'o',
      'repository': 'r',
      'branchNameRegex': r'^paged$',
    });
    final commits = jsonDecode(raw) as List;
    expect(commits, hasLength(101));
    expect(commits.first['sha'], 'p000');
    expect(commits.last['sha'], 'p100');
  });

  test('github_get_commits_from_branches skips a failed commit page', () {
    // o/errc: the branch listing succeeds, the commit fetch 500s —
    // best-effort per branch, so the result is just empty.
    final raw = _call('github_get_commits_from_branches', {
      'workspace': 'o',
      'repository': 'errc',
      'branchNameRegex': r'.*',
    });
    expect(jsonDecode(raw), isEmpty);
  });

  test('github_get_commits_from_branches fails on a branch listing error', () {
    // o/err: branches are strict — a non-OK page fails the tool.
    final raw = _call('github_get_commits_from_branches', {
      'workspace': 'o',
      'repository': 'err',
      'branchNameRegex': r'.*',
    });
    expect(jsonDecode(raw), {
      'error': 'HTTP 500 fetching comments (page 1): '
          '{"message": "branches boom"}',
    });
  });
}

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
    PropertyReader.setOverrides({
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

void _issueRefTests() {
  setUp(() => _startFixture());
  tearDown(_stopFixture);

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
