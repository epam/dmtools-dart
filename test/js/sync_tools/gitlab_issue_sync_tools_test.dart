import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/gitlab_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

late EchoServer _server;
const _tools = GitLabSyncTools();

Map<String, dynamic> _echo(String tool, Map<String, dynamic> args) =>
    jsonDecode(_tools.handlers[tool]!(args)) as Map<String, dynamic>;

/// Tests for GitLab issue-tracker sync tools (`GitLabIssues.java` parity).
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _testIssueHandlerSurface();
  if (hasPython3()) {
    _testIssueReadAndCreateTools();
    _testIssueMutationTools();
  }
}

void _testIssueHandlerSurface() {
  test('GitLabSyncTools.handlers covers the issue tracker surface', () {
    const names = [
      'gitlab_get_issue',
      'gitlab_search_issues',
      'gitlab_create_issue',
      'gitlab_close_issue',
      'gitlab_reopen_issue',
      'gitlab_move_issue_to_status',
      'gitlab_assign_issue',
      'gitlab_add_issue_label',
      'gitlab_remove_issue_label',
      'gitlab_create_issue_comment',
      'gitlab_get_issue_comments',
    ];
    for (final name in names) {
      expect(_tools.handlers, containsPair(name, anything),
          reason: 'missing handler for $name');
    }
  });
}

void _setUpIssueServer() {
  setUp(() async {
    _server = EchoServer();
    await _server.start();
    PropertyReader.setOverrides({
      'GITLAB_BASE_PATH': 'http://127.0.0.1:${_server.port}',
      'GITLAB_TOKEN': 'glpat-test',
      'GITLAB_WORKSPACE': 'defgroup',
      'GITLAB_REPOSITORY': 'defrepo',
    });
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    _server.stop();
  });
}

void _testIssueReadAndCreateTools() {
  group('GitLabSyncTools issue read/create tools', () {
    _setUpIssueServer();

    test('gitlab_get_issue resolves composite key and gl-N key', () {
      final b1 = _echo('gitlab_get_issue', {'key': 'org/sub/repo#12'});
      expect(b1['method'], 'GET');
      expect(b1['path'], '/api/v4/projects/org%2Fsub%2Frepo/issues/12');

      final b2 = _echo('gitlab_get_issue', {'key': 'gl-99'});
      expect(b2['path'], '/api/v4/projects/defgroup%2Fdefrepo/issues/99');
    });

    test('gitlab_search_issues queries project issues with state and search',
        () {
      final b = _echo('gitlab_search_issues', {
        'query': 'login bug',
        'state': 'opened',
      });
      expect(b['method'], 'GET');
      expect(
        b['path'],
        '/api/v4/projects/defgroup%2Fdefrepo/issues'
        '?state=opened&per_page=100&search=login+bug',
      );
    });

    test('gitlab_create_issue POSTs title and description', () {
      final b = _echo('gitlab_create_issue', {
        'key': 'grp/proj',
        'title': 'Broken',
        'body': 'Details',
      });
      expect(b['method'], 'POST');
      expect(b['path'], '/api/v4/projects/grp%2Fproj/issues');
      expect(jsonDecode(b['body'] as String), {
        'title': 'Broken',
        'description': 'Details',
      });
    });
  });
}

void _testIssueMutationTools() {
  group('GitLabSyncTools issue mutation tools', () {
    _setUpIssueServer();

    test('gitlab_close_issue, reopen, and move_issue_to_status', () {
      final closed = _echo('gitlab_close_issue', {'key': 'gl-5'});
      expect(closed['method'], 'PUT');
      expect(jsonDecode(closed['body'] as String), {'state_event': 'close'});

      final reopened = _echo('gitlab_reopen_issue', {'key': 'gl-5'});
      expect(jsonDecode(reopened['body'] as String), {'state_event': 'reopen'});

      final movedDone = _echo('gitlab_move_issue_to_status', {
        'key': 'gl-5',
        'statusName': 'completed',
      });
      expect(jsonDecode(movedDone['body'] as String), {'state_event': 'close'});

      final movedCustom = _echo('gitlab_move_issue_to_status', {
        'key': 'gl-5',
        'statusName': 'In Review',
      });
      expect(
        jsonDecode(movedCustom['body'] as String),
        {'add_labels': 'status::In Review'},
      );
    });

    test('gitlab_add_issue_label, remove_label, and create_issue_comment', () {
      final added = _echo('gitlab_add_issue_label', {
        'key': 'gl-5',
        'label': 'bug',
      });
      expect(jsonDecode(added['body'] as String), {'add_labels': 'bug'});

      final removed = _echo('gitlab_remove_issue_label', {
        'key': 'gl-5',
        'label': 'bug',
      });
      expect(jsonDecode(removed['body'] as String), {'remove_labels': 'bug'});

      final comment = _echo('gitlab_create_issue_comment', {
        'key': 'gl-5',
        'body': 'Note text',
      });
      expect(comment['method'], 'POST');
      expect(
        comment['path'],
        '/api/v4/projects/defgroup%2Fdefrepo/issues/5/notes',
      );
      expect(jsonDecode(comment['body'] as String), {'body': 'Note text'});
    });
  });
}
