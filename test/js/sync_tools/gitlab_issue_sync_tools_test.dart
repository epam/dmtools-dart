import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/gitlab_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

/// Tests for the GitLab issue-tracker sync executors (Java
/// `GitLabIssues.java` parity — the tools trackers.js calls with
/// `DEFAULT_TRACKER=gitlab`: labels, comments, status moves, search).
late EchoServer server;
const tools = GitLabSyncTools();

Map<String, dynamic> echo(String tool, Map<String, dynamic> args) =>
    jsonDecode(tools.handlers[tool]!(args)) as Map<String, dynamic>;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  group('GitLab issue tools handler surface', () {
    test('every tracker-facing issue tool resolves to a handler', () {
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
        expect(tools.handlers.containsKey(name), isTrue,
            reason: 'missing handler: $name');
      }
    });
  });

  group('GitLab issue tools', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'GITLAB_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'GITLAB_TOKEN': 'glpat-test',
        'GITLAB_WORKSPACE': 'defgroup',
        'GITLAB_REPOSITORY': 'defrepo',
      });
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('gitlab_add_issue_label PUTs add_labels with explicit parts', () {
      final body = echo('gitlab_add_issue_label', {
        'workspace': 'mygroup',
        'repository': 'myrepo',
        'issueNumber': '42',
        'label': 'ai_concerns',
      });
      expect(body['method'], 'PUT');
      expect(
        body['path'],
        '/api/v4/projects/mygroup%2Fmyrepo/issues/42',
      );
      expect(
        jsonDecode(body['body'] as String),
        {'add_labels': 'ai_concerns'},
      );
      expect(body['headers']['PRIVATE-TOKEN'], 'glpat-test');
    });

    test('gitlab_add_issue_label resolves the gl-N router key', () {
      final body = echo('gitlab_add_issue_label', {'key': 'gl-2', 'label': 'x'});
      expect(
        body['path'],
        '/api/v4/projects/defgroup%2Fdefrepo/issues/2',
      );
    });

    test('gitlab_add_issue_label resolves a nested composite key', () {
      final body = echo('gitlab_add_issue_label', {
        'key': 'epm-esg/products/csrd/csrd-dm-ai-factory#7',
        'label': 'x',
      });
      expect(
        body['path'],
        '/api/v4/projects/epm-esg%2Fproducts%2Fcsrd%2Fcsrd-dm-ai-factory'
        '/issues/7',
      );
    });

    test('gitlab_remove_issue_label PUTs remove_labels', () {
      final body = echo('gitlab_remove_issue_label', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '5',
        'label': 'ai_questions_asked',
      });
      expect(body['method'], 'PUT');
      expect(
        jsonDecode(body['body'] as String),
        {'remove_labels': 'ai_questions_asked'},
      );
    });

    test('gitlab_create_issue_comment POSTs the note body', () {
      final body = echo('gitlab_create_issue_comment', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '42',
        'body': 'Completion comment',
      });
      expect(body['method'], 'POST');
      expect(
        body['path'],
        '/api/v4/projects/g%2Fr/issues/42/notes',
      );
      expect(
        jsonDecode(body['body'] as String),
        {'body': 'Completion comment'},
      );
    });

    test('gitlab_create_issue_comment accepts the text alias', () {
      final body = echo('gitlab_create_issue_comment', {
        'key': 'g/r#9',
        'text': 'via alias',
      });
      expect(body['path'], '/api/v4/projects/g%2Fr/issues/9/notes');
      expect(jsonDecode(body['body'] as String), {'body': 'via alias'});
    });

    test('gitlab_move_issue_to_status closes on done semantics', () {
      final body = echo('gitlab_move_issue_to_status', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '1',
        'statusName': 'done',
      });
      expect(body['method'], 'PUT');
      expect(
        jsonDecode(body['body'] as String),
        {'state_event': 'close'},
      );
    });

    test('gitlab_move_issue_to_status reopens on open semantics', () {
      final body = echo('gitlab_move_issue_to_status', {
        'key': 'gl-3',
        'statusName': 'reopened',
      });
      expect(
        jsonDecode(body['body'] as String),
        {'state_event': 'reopen'},
      );
    });

    test('gitlab_move_issue_to_status applies scoped status labels', () {
      final body = echo('gitlab_move_issue_to_status', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '1',
        'statusName': 'In Development',
      });
      expect(
        jsonDecode(body['body'] as String),
        {'add_labels': 'status::In Development'},
      );
    });

    test('gitlab_get_issue GETs the issue path', () {
      final body = echo('gitlab_get_issue', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '11',
      });
      expect(body['method'], 'GET');
      expect(body['path'], '/api/v4/projects/g%2Fr/issues/11');
    });

    test('gitlab_search_issues GETs search params with state default', () {
      final body = echo('gitlab_search_issues', {
        'query': 'login fails',
        'workspace': 'g',
        'repository': 'r',
      });
      expect(body['method'], 'GET');
      expect(
        body['path'],
        '/api/v4/projects/g%2Fr/issues'
        '?state=all&per_page=100&search=login+fails',
      );
    });

    test('gitlab_create_issue POSTs title and description', () {
      final body = echo('gitlab_create_issue', {
        'workspace': 'g',
        'repository': 'r',
        'title': 'Something broke',
        'body': 'Steps...',
      });
      expect(body['method'], 'POST');
      expect(body['path'], '/api/v4/projects/g%2Fr/issues');
      expect(
        jsonDecode(body['body'] as String),
        {'title': 'Something broke', 'description': 'Steps...'},
      );
    });

    test('gitlab_close_issue and gitlab_reopen_issue PUT state_event', () {
      final closed = echo('gitlab_close_issue', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '4',
      });
      expect(jsonDecode(closed['body'] as String), {'state_event': 'close'});
      final reopened = echo('gitlab_reopen_issue', {
        'workspace': 'g',
        'repository': 'r',
        'issueNumber': '4',
      });
      expect(jsonDecode(reopened['body'] as String), {'state_event': 'reopen'});
    });

    test('unparseable key yields a JSON error, not a crash', () {
      final result = tools.handlers['gitlab_get_issue']!({'key': 'not-a-key'});
      expect((jsonDecode(result) as Map)['error'], contains('Cannot parse'));
    });

    test('missing reference yields a JSON error', () {
      final result = tools.handlers['gitlab_add_issue_label']!({'label': 'x'});
      expect((jsonDecode(result) as Map)['error'],
          contains('GitLab issue reference requires'));
    });
  });
}
