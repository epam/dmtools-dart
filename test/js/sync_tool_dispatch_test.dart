import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// Tests for [SyncToolDispatcher].
///
/// Server-dependent tests start a Python echo server subprocess because
/// Dart's [HttpServer] runs on the event loop, which is frozen during
/// `Process.runSync('curl', …)`.
void main() {
  _testRouting();
  _testNoConfig();
  if (hasPython3()) {
    _testJiraTools();
    _testGithubTools();
  }
}

void _testRouting() {
  group('SyncToolDispatcher routing', () {
    late SyncToolDispatcher dispatcher;

    setUp(() {
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': '',
        'JIRA_EMAIL': '',
        'JIRA_API_TOKEN': '',
        'JIRA_LOGIN_PASS_TOKEN': '',
        'SOURCE_GITHUB_TOKEN': '',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('unknown integration prefix returns null', () {
      expect(dispatcher.execute('unknown_tool', {}), isNull);
    });

    test('unsupported jira tool returns error JSON', () {
      final result = dispatcher.execute('jira_mystery', {});
      expect(
        jsonDecode(result!),
        {'error': 'Unsupported Jira tool: jira_mystery'},
      );
    });

    test('unsupported github tool returns error JSON', () {
      final result = dispatcher.execute('github_mystery', {});
      expect(
        jsonDecode(result!),
        {'error': 'Unsupported GitHub tool: github_mystery'},
      );
    });
  });
}

void _testNoConfig() {
  group('SyncToolDispatcher without config', () {
    setUp(() => PropertyReader.setOverrides({
          'JIRA_BASE_PATH': '',
          'JIRA_EMAIL': '',
          'JIRA_API_TOKEN': '',
          'JIRA_LOGIN_PASS_TOKEN': '',
          'SOURCE_GITHUB_TOKEN': '',
        }));

    tearDown(() => PropertyReader.clearOverrides());

    test('jira_get_ticket returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      final result = d.execute('jira_get_ticket', {'key': 'T-1'});
      expect(jsonDecode(result!), {'error': 'Jira not configured'});
    });

    test('github_get_pr returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      final result = d.execute('github_get_pr', {
        'owner': 'o',
        'repo': 'r',
        'number': 1,
      });
      expect(jsonDecode(result!), {'error': 'GitHub not configured'});
    });
  });
}

void _testJiraTools() {
  _testJiraReadTools();
  _testJiraTicketFields();
  _testJiraWriteTools();
}

void _testJiraReadTools() {
  group('SyncToolDispatcher Jira read tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
        'JIRA_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('jira_get_ticket hits issue endpoint with default fields', () {
      final result = dispatcher.execute('jira_get_ticket', {'key': 'PROJ-123'});
      final body = jsonDecode(result!);
      expect(body['method'], 'GET');
      expect(
        body['path'].startsWith('/rest/api/latest/issue/PROJ-123'),
        isTrue,
      );
      expect(body['path'], contains('fields='));
    });

    test('jira_search_by_jql encodes JQL in query string', () {
      final result = dispatcher.execute('jira_search_by_jql', {
        'jql': 'project = PROJ',
      });
      final body = jsonDecode(result!);
      expect(body['path'].startsWith('/rest/api/latest/search/jql'), isTrue);
      expect(body['path'], contains('jql='));
      expect(body['method'], 'GET');
    });
  });
}

void _testJiraTicketFields() {
  group('SyncToolDispatcher jira_get_ticket fields', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
        'JIRA_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('sends Authorization header', () {
      final result = dispatcher.execute('jira_get_ticket', {'key': 'P-1'});
      final body = jsonDecode(result!);
      expect(body['headers']['Authorization'], 'Basic dGVzdDp0b2tlbg==');
      expect(body['headers']['X-Atlassian-Token'], 'nocheck');
    });

    test('accepts fields as comma-separated string', () {
      final result = dispatcher.execute('jira_get_ticket', {
        'key': 'P-1',
        'fields': 'summary,status',
      });
      final body = jsonDecode(result!);
      expect(body['path'], contains('fields=summary%2Cstatus'));
    });

    test('accepts fields as an array', () {
      final result = dispatcher.execute('jira_get_ticket', {
        'key': 'P-1',
        'fields': ['summary', 'status'],
      });
      final body = jsonDecode(result!);
      expect(body['path'], contains('fields=summary%2Cstatus'));
    });
  });
}

void _testJiraWriteTools() {
  group('SyncToolDispatcher Jira write tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
        'JIRA_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('jira_post_comment POSTs comment body', () {
      final result = dispatcher.execute('jira_post_comment', {
        'key': 'PROJ-1',
        'comment': 'Hello world',
      });
      final body = jsonDecode(result!);
      expect(body['method'], 'POST');
      expect(body['path'], '/rest/api/latest/issue/PROJ-1/comment');
      final reqBody = jsonDecode(body['body'] as String);
      expect(reqBody['body'], 'Hello world');
    });

    test('jira_add_label PUTs full label set', () {
      final result = dispatcher.execute('jira_add_label', {
        'key': 'PROJ-1',
        'label': 'bug',
      });
      final body = jsonDecode(result!);
      expect(body['method'], 'PUT');
      final putBody = jsonDecode(body['body'] as String);
      expect(putBody['update']['labels'][0]['set'], contains('bug'));
    });

    test('jira_move_to_status returns error when no transitions found', () {
      final result = dispatcher.execute('jira_move_to_status', {
        'key': 'PROJ-1',
        'status': 'In Progress',
      });
      expect(
        jsonDecode(result!),
        {'error': 'No transition found for status: In Progress'},
      );
    });
  });
}

void _testGithubTools() {
  _testGithubReadTools();
  _testGithubWriteTools();
}

void _testGithubReadTools() {
  group('SyncToolDispatcher GitHub read tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
        'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${server.port}',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('github_get_pr hits pulls endpoint', () {
      final result = dispatcher.execute('github_get_pr', {
        'owner': 'octo',
        'repo': 'cat',
        'number': 42,
      });
      final body = jsonDecode(result!);
      expect(body['method'], 'GET');
      expect(body['path'], '/repos/octo/cat/pulls/42');
    });

    test('github_get_pr sends Bearer auth header', () {
      final result = dispatcher.execute('github_get_pr', {
        'owner': 'o',
        'repo': 'r',
        'number': 1,
      });
      final body = jsonDecode(result!);
      expect(body['headers']['Authorization'], 'Bearer ghp_testtoken');
      expect(body['headers']['Accept'], 'application/vnd.github+json');
    });
  });
}

void _testGithubWriteTools() {
  group('SyncToolDispatcher GitHub write tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
        'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${server.port}',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('github_create_comment POSTs to issues comments endpoint', () {
      final result = dispatcher.execute('github_create_comment', {
        'owner': 'octo',
        'repo': 'cat',
        'number': 42,
        'body': 'Nice PR!',
      });
      final body = jsonDecode(result!);
      expect(body['method'], 'POST');
      expect(body['path'], '/repos/octo/cat/issues/42/comments');
      final reqBody = jsonDecode(body['body'] as String);
      expect(reqBody['body'], 'Nice PR!');
    });

    test('number as string is coerced to int', () {
      final result = dispatcher.execute('github_get_pr', {
        'owner': 'o',
        'repo': 'r',
        'number': '7',
      });
      final body = jsonDecode(result!);
      expect(body['path'], '/repos/o/r/pulls/7');
    });
  });
}
