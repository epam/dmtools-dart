/// Tests for [GithubTrackerClient] — the write-side GitHub issues tracker
/// client (Java `GitHubTrackerClient` / `GitHubTicket` parity, gh-35).
///
/// The client routes over the `github_*` sync tool surface, so every test
/// injects a recording [GithubTrackerClient.execute] fake — no network.
/// Key resolution reads `GITHUB_REPOSITORY` /
/// `SOURCE_GITHUB_WORKSPACE`/`SOURCE_GITHUB_REPOSITORY` through
/// [PropertyReader.testEnvironment].
library;

import 'dart:convert';

import 'package:dmtools/src/agents/github_tracker_client.dart';
import 'package:dmtools/src/config/property_reader.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  group('GithubTrackerClient key resolution', _keyResolutionTests);
  group('GithubTrackerClient write operations', _writeOperationTests);
  group('GithubTrackerClient write errors', _writeErrorTests);
  group('GithubTrackerClient createTicket', _createTicketTests);
  group('GithubTrackerClient isConfigured', _isConfiguredTests);
}

/// A client whose tool dispatch is recorded into [calls] (optional);
/// [results] maps the tool name to the canned result (default `{}`).
GithubTrackerClient _client({
  List<(String, Map<String, dynamic>)>? calls,
  Map<String, String> results = const {},
  Map<String, String> env = const {},
}) {
  PropertyReader.testEnvironment
    ..clear()
    ..addAll(env);
  return GithubTrackerClient(
    execute: (tool, args) {
      calls?.add((tool, args));
      return results[tool] ?? jsonEncode({});
    },
  );
}

void _keyResolutionTests() {
  group('composite and gh- keys', _keyShapeTests);
  group('default-repo fallback', _keyDefaultTests);
}

void _keyShapeTests() {
  test('composite key owner/repo#42 dispatches explicit parts', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    client.postComment('owner/repo#42', 'hello');
    expect(calls.single.$1, 'github_create_comment');
    expect(calls.single.$2, {
      'workspace': 'owner',
      'repository': 'repo',
      'pullRequestId': '42',
      'body': 'hello',
    });
  });

  test('gh-<n> key resolves the repo from GITHUB_REPOSITORY', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(
      calls: calls,
      env: {'GITHUB_REPOSITORY': 'acme/widgets'},
    );
    client.postComment('GH-42', 'hello');
    expect(calls.single.$2['workspace'], 'acme');
    expect(calls.single.$2['repository'], 'widgets');
    expect(calls.single.$2['pullRequestId'], '42');
  });

  test('lowercase gh-<n> keys resolve the same way', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(
      calls: calls,
      env: {'GITHUB_REPOSITORY': 'acme/widgets'},
    );
    client.postComment('gh-7', 'x');
    expect(calls.single.$2['pullRequestId'], '7');
  });

  test('explicit composite parts beat the configured defaults', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(
      calls: calls,
      env: {'GITHUB_REPOSITORY': 'other/repo'},
    );
    client.postComment('owner/repo#42', 'x');
    expect(calls.single.$2['workspace'], 'owner');
    expect(calls.single.$2['repository'], 'repo');
  });
}

void _keyDefaultTests() {
  test('bare number resolves against the configured default repo', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(
      calls: calls,
      env: {
        'SOURCE_GITHUB_WORKSPACE': 'acme',
        'SOURCE_GITHUB_REPOSITORY': 'widgets',
      },
    );
    client.postComment('42', 'hello');
    expect(calls.single.$2['workspace'], 'acme');
    expect(calls.single.$2['repository'], 'widgets');
  });

  test('unresolvable key throws with the Java message shape', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    expect(() => client.postComment('PROJ-1', 'x'), throwsStateError);
    expect(calls, isEmpty);
  });

  test('missing repo for a bare number throws', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    expect(() => client.postComment('42', 'x'), throwsStateError);
    expect(calls, isEmpty);
  });
}

void _writeOperationTests() {
  test('moveToStatus dispatches github_move_issue_to_status', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    client.moveToStatus('owner/repo#42', 'Done');
    expect(calls.single.$1, 'github_move_issue_to_status');
    expect(calls.single.$2['statusName'], 'Done');
  });

  test('assignTo dispatches github_assign_issue', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    client.assignTo('owner/repo#42', 'octocat');
    expect(calls.single.$1, 'github_assign_issue');
    expect(calls.single.$2['user'], 'octocat');
  });

  test('addLabel posts a one-element labels array', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    client.addLabel('owner/repo#42', 'bug');
    expect(calls.single.$1, 'github_add_labels');
    expect(calls.single.$2['labels'], ['bug']);
  });

  test('removeLabel dispatches github_remove_label', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    client.removeLabel('owner/repo#42', 'bug');
    expect(calls.single.$1, 'github_remove_label');
    expect(calls.single.$2['label'], 'bug');
  });
}

void _writeErrorTests() {
  test('an error envelope surfaces as a StateError (IOException parity)', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(
      calls: calls,
      results: {
        'github_create_comment': '{"error": "HTTP 403: forbidden"}',
      },
    );
    expect(
      () => client.postComment('owner/repo#42', 'x'),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('403'),
      )),
    );
  });

  test('every write op rejects unresolvable keys before dispatching', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    expect(() => client.moveToStatus('NOPE', 'Done'), throwsStateError);
    expect(() => client.assignTo('NOPE', 'octocat'), throwsStateError);
    expect(() => client.addLabel('NOPE', 'bug'), throwsStateError);
    expect(() => client.removeLabel('NOPE', 'bug'), throwsStateError);
    expect(calls, isEmpty);
  });
}

void _createTicketTests() {
  test('createTicket splits the project and returns the composite key', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(
      calls: calls,
      results: {
        'github_create_issue': jsonEncode({'number': 7, 'title': 't'}),
      },
    );
    final key = client.createTicket(
      project: 'acme/widgets',
      summary: 'Something is broken',
      description: 'Steps to reproduce…',
    );
    expect(key, 'acme/widgets#7');
    expect(calls.single.$1, 'github_create_issue');
    expect(calls.single.$2['owner'], 'acme');
    expect(calls.single.$2['repo'], 'widgets');
    expect(calls.single.$2['title'], 'Something is broken');
    expect(calls.single.$2['body'], 'Steps to reproduce…');
  });

  test('createTicket with an unnumbered payload throws', () {
    final calls = <(String, Map<String, dynamic>)>[];
    final client = _client(calls: calls);
    expect(
      () => client.createTicket(project: 'acme/widgets', summary: 't'),
      throwsStateError,
    );
  });
}

void _isConfiguredTests() {
  test('isConfigured follows SOURCE_GITHUB_TOKEN', () {
    final withToken = _client(env: {'SOURCE_GITHUB_TOKEN': 't'});
    expect(withToken.isConfigured, isTrue);
    final withoutToken = _client();
    expect(withoutToken.isConfigured, isFalse);
  });
}
