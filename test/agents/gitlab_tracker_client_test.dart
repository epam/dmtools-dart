/// Tests for [GitlabTrackerClient] — the write-side GitLab issues tracker
/// client (Java `GitLabTrackerClient` parity, epam/dm.ai#876).
library;

import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

typedef _Call = ({String tool, Map<String, dynamic> args});

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  group('GitlabTrackerClient key resolution', _keyResolutionTests);
  group('GitlabTrackerClient write operations', _writeOperationTests);
  group('GitlabTrackerClient write errors', _writeErrorTests);
  group('GitlabTrackerClient createTicket', _createTicketTests);
  group('GitlabTrackerClient isConfigured', _isConfiguredTests);
}

GitlabTrackerClient _client(
  List<_Call> calls, {
  String? Function(String, Map<String, dynamic>)? onCall,
}) =>
    GitlabTrackerClient(
      execute: (tool, args) {
        calls.add((tool: tool, args: args));
        return onCall != null ? onCall(tool, args) : '{"iid":42}';
      },
    );

void _keyResolutionTests() {
  test('resolves composite namespace/project#iid and nested subgroup keys', () {
    final calls = <_Call>[];
    final c = _client(calls);
    expect(c.resolveIssueRef('mygroup/myrepo#42'), ('mygroup/myrepo', '42'));
    expect(
      c.resolveIssueRef('org/sub/myrepo#99'),
      ('org/sub/myrepo', '99'),
    );
  });

  test('resolves gl-N and bare IID via CI_PROJECT_PATH or GITLAB_WORKSPACE',
      () {
    final calls = <_Call>[];
    final c = _client(calls);
    PropertyReader.setOverrides({'CI_PROJECT_PATH': 'ci-group/ci-repo'});
    expect(c.resolveIssueRef('gl-17'), ('ci-group/ci-repo', '17'));
    expect(c.resolveIssueRef('18'), ('ci-group/ci-repo', '18'));

    PropertyReader.setOverrides({
      'GITLAB_WORKSPACE': 'ws-group',
      'GITLAB_REPOSITORY': 'ws-repo',
    });
    expect(c.resolveIssueRef('GL-21'), ('ws-group/ws-repo', '21'));
  });

  test('returns null when key is malformed or project is unconfigured', () {
    final calls = <_Call>[];
    final c = _client(calls);
    PropertyReader.clearOverrides();
    expect(c.resolveIssueRef('gl-42'), isNull);
    expect(c.resolveIssueRef('not-a-key'), isNull);
  });
}

void _writeOperationTests() {
  test('dispatches postComment, moveToStatus, assignTo, addLabel, removeLabel',
      () {
    final calls = <_Call>[];
    final c = _client(calls);
    c.postComment('grp/proj#7', 'hello');
    c.moveToStatus('grp/proj#7', 'Done');
    c.assignTo('grp/proj#7', 'alice');
    c.addLabel('grp/proj#7', 'ai_developed');
    c.removeLabel('grp/proj#7', 'agent:dev');

    expect(calls.map((x) => x.tool), [
      'gitlab_create_issue_comment',
      'gitlab_move_issue_to_status',
      'gitlab_assign_issue',
      'gitlab_add_issue_label',
      'gitlab_remove_issue_label',
    ]);
    expect(calls[0].args, {'key': 'grp/proj#7', 'body': 'hello'});
    expect(calls[1].args, {'key': 'grp/proj#7', 'statusName': 'Done'});
    expect(calls[2].args, {'key': 'grp/proj#7', 'user': 'alice'});
    expect(calls[3].args, {'key': 'grp/proj#7', 'label': 'ai_developed'});
    expect(calls[4].args, {'key': 'grp/proj#7', 'label': 'agent:dev'});
  });
}

void _writeErrorTests() {
  test('throws StateError on unresolvable key or error envelope', () {
    final calls = <_Call>[];
    final c = _client(
      calls,
      onCall: (_, __) => jsonEncode({'error': 'boom'}),
    );
    expect(() => c.postComment('bad', 'x'), throwsStateError);
    expect(() => c.postComment('grp/proj#1', 'x'), throwsStateError);
  });
}

void _createTicketTests() {
  test('creates an issue and returns namespace/project#iid', () {
    final calls = <_Call>[];
    final c = _client(
      calls,
      onCall: (_, __) => jsonEncode({'iid': 55}),
    );
    final key = c.createTicket(
      project: 'grp/sub/proj',
      summary: 'New feature',
      description: 'Details',
    );
    expect(key, 'grp/sub/proj#55');
    expect(calls.single.tool, 'gitlab_create_issue');
    expect(calls.single.args, {
      'key': 'grp/sub/proj',
      'title': 'New feature',
      'body': 'Details',
    });
  });

  test('rejects invalid project or missing iid in response', () {
    final calls = <_Call>[];
    final c = _client(calls, onCall: (_, __) => '{}');
    expect(
      () => c.createTicket(project: 'invalid', summary: 'x'),
      throwsStateError,
    );
    expect(
      () => c.createTicket(project: 'grp/proj', summary: 'x'),
      throwsStateError,
    );
  });
}

void _isConfiguredTests() {
  test('isConfigured reflects GITLAB_TOKEN presence', () {
    final c = _client([]);
    PropertyReader.clearOverrides();
    expect(c.isConfigured, isFalse);
    PropertyReader.setOverrides({'GITLAB_TOKEN': 'glpat_123'});
    expect(c.isConfigured, isTrue);
  });
}
