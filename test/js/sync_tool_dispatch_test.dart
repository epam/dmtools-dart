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
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _testRouting();
  _testUnsupportedIntegrationTools();
  _testNoConfig();
  _testPartialConfig();
  _testJiraAliases();
  _testNonHttpDelegation();
  if (hasPython3()) {
    _testJiraTools();
    _testGithubTools();
    _testJiraExtendedTools();
  }
}

/// Overrides that blank out every integration's config keys, so routing and
/// no-config tests are isolated from the host environment.
Map<String, String> _blankIntegrationConfig() => {
      'JIRA_BASE_PATH': '',
      'JIRA_EMAIL': '',
      'JIRA_API_TOKEN': '',
      'JIRA_LOGIN_PASS_TOKEN': '',
      'SOURCE_GITHUB_TOKEN': '',
      'GITLAB_BASE_PATH': '',
      'GITLAB_TOKEN': '',
      'CONFLUENCE_BASE_PATH': '',
      'CONFLUENCE_LOGIN_PASS_TOKEN': '',
      'ADO_ORGANIZATION': '',
      'ADO_PROJECT': '',
      'ADO_PAT_TOKEN': '',
    };

void _testRouting() {
  group('SyncToolDispatcher routing', () {
    late SyncToolDispatcher dispatcher;

    setUp(() {
      PropertyReader.setOverrides(_blankIntegrationConfig());
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('unknown integration prefix returns null', () {
      expect(dispatcher.execute('unknown_tool', {}), isNull);
    });

    test('unsupported jira tool returns error JSON', () {
      expect(
        jsonDecode(dispatcher.execute('jira_mystery', {})!),
        {'error': 'Unsupported Jira tool: jira_mystery'},
      );
    });

    test('unsupported github tool returns error JSON', () {
      expect(
        jsonDecode(dispatcher.execute('github_mystery', {})!),
        {'error': 'Unsupported GitHub tool: github_mystery'},
      );
    });
  });
}

void _testUnsupportedIntegrationTools() {
  group('SyncToolDispatcher unsupported integration tools', () {
    late SyncToolDispatcher dispatcher;

    setUp(() {
      PropertyReader.setOverrides(_blankIntegrationConfig());
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('unsupported gitlab tool returns error JSON', () {
      expect(
        jsonDecode(dispatcher.execute('gitlab_mystery', {})!),
        {'error': 'Unsupported GitLab tool: gitlab_mystery'},
      );
    });

    test('unsupported confluence tool returns error JSON', () {
      expect(
        jsonDecode(dispatcher.execute('confluence_mystery', {})!),
        {'error': 'Unsupported Confluence tool: confluence_mystery'},
      );
    });

    test('unsupported ado tool returns error JSON', () {
      expect(
        jsonDecode(dispatcher.execute('ado_mystery', {})!),
        {'error': 'Unsupported ADO tool: ado_mystery'},
      );
    });
  });
}

void _testNoConfig() {
  group('SyncToolDispatcher without config', () {
    setUp(() => PropertyReader.setOverrides(_blankIntegrationConfig()));

    tearDown(() => PropertyReader.clearOverrides());

    test('jira_get_ticket returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('jira_get_ticket', {'key': 'T-1'})!),
        {'error': 'Jira not configured'},
      );
    });

    test('github_get_pr returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('github_get_pr', {
          'workspace': 'o',
          'repository': 'r',
          'pullRequestId': 1,
        })!),
        {'error': 'GitHub not configured'},
      );
    });

    test('gitlab_get_mr returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('gitlab_get_mr', {'project': 'g/r', 'iid': 1})!),
        {'error': 'GitLab not configured'},
      );
    });

    test('confluence_search returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('confluence_search', {'cql': 'space = DEV'})!),
        {'error': 'Confluence not configured'},
      );
    });

    test('ado_get_work_item returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('ado_get_work_item', {'id': 1})!),
        {'error': 'ADO not configured'},
      );
    });
  });
}

void _testPartialConfig() {
  group('SyncToolDispatcher partial config', () {
    tearDown(() => PropertyReader.clearOverrides());

    test('gitlab with base path but no token is unconfigured', () {
      PropertyReader.setOverrides({
        'GITLAB_BASE_PATH': 'https://gitlab.example.com',
        'GITLAB_TOKEN': '',
      });
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('gitlab_get_mr', {'project': 'g/r', 'iid': 1})!),
        {'error': 'GitLab not configured'},
      );
    });

    test('confluence with base path but no token is unconfigured', () {
      PropertyReader.setOverrides({
        'CONFLUENCE_BASE_PATH': 'https://confluence.example.com',
        'CONFLUENCE_LOGIN_PASS_TOKEN': '',
      });
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('confluence_search', {'cql': 'a'})!),
        {'error': 'Confluence not configured'},
      );
    });

    test('ado with org/project but no PAT is unconfigured', () {
      PropertyReader.setOverrides({
        'ADO_ORGANIZATION': 'org',
        'ADO_PROJECT': 'proj',
        'ADO_PAT_TOKEN': '',
      });
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('ado_get_work_item', {'id': 1})!),
        {'error': 'ADO not configured'},
      );
    });

    test('ado with org but no project is unconfigured', () {
      PropertyReader.setOverrides({
        'ADO_ORGANIZATION': 'org',
        'ADO_PROJECT': '',
        'ADO_PAT_TOKEN': 'pat',
      });
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('ado_get_work_item', {'id': 1})!),
        {'error': 'ADO not configured'},
      );
    });
  });
}

void _testJiraTools() {
  _testJiraReadTools();
  _testJiraTicketFields();
  _testJiraWriteTools();
  _testJiraLabelTools();
  _testJiraLabelAbortTools();
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

/// Label add/remove — including the no-PUT-on-failed-fetch contract that
/// guards against wiping a ticket's labels on a transient GET failure.
void _testJiraLabelTools() {
  group('SyncToolDispatcher Jira label tools', () {
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

    test('jira_add_label PUTs the fetched set plus the new label', () {
      final result = dispatcher.execute('jira_add_label', {
        'key': 'PROJ-1',
        'label': 'bug',
      });
      final body = jsonDecode(result!);
      expect(body['method'], 'PUT');
      final putBody = jsonDecode(body['body'] as String);
      expect(putBody['update']['labels'][0]['set'], ['existing', 'bug']);
    });

    test('jira_remove_label PUTs the fetched set minus the label', () {
      final result = dispatcher.execute('jira_remove_label', {
        'key': 'PROJ-1',
        'label': 'existing',
      });
      final body = jsonDecode(result!);
      final putBody = jsonDecode(body['body'] as String);
      expect(putBody['update']['labels'][0]['set'], isEmpty);
    });
  });
}

/// The no-PUT-on-failed-fetch contract that guards against wiping a
/// ticket's labels on a transient GET failure.
void _testJiraLabelAbortTools() {
  group('SyncToolDispatcher Jira label fetch failures', () {
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

    test('jira_add_label aborts (no PUT) when the label fetch fails', () {
      final result = dispatcher.execute('jira_add_label', {
        'key': '__jira_fail',
        'label': 'bug',
      });
      final body = jsonDecode(result!);
      expect(body, {
        'error': 'Failed to fetch labels for __jira_fail',
      });
      expect(body['method'], isNull); // no PUT echo — nothing was sent
    });

    test('jira_remove_label aborts (no PUT) when the label fetch fails', () {
      final result = dispatcher.execute('jira_remove_label', {
        'key': '__jira_fail',
        'label': 'bug',
      });
      expect(
        jsonDecode(result!),
        {'error': 'Failed to fetch labels for __jira_fail'},
      );
    });
  });
}

void _testJiraExtendedTools() {
  _testJiraExtendedReadTools();
  _testJiraExtendedWriteTools();
  _testJiraLifecycleTools();
}

void _testJiraExtendedReadTools() {
  group('SyncToolDispatcher Jira extended read tools', () {
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

    test('jira_get_comments hits the comment endpoint', () {
      final body = jsonDecode(
          dispatcher.execute('jira_get_comments', {'key': 'PROJ-1'})!);
      expect(body['method'], 'GET');
      expect(body['path'], '/rest/api/latest/issue/PROJ-1/comment');
    });

    test('jira_get_transitions hits the transitions endpoint', () {
      final body = jsonDecode(
          dispatcher.execute('jira_get_transitions', {'key': 'PROJ-1'})!);
      expect(body['method'], 'GET');
      expect(body['path'], '/rest/api/latest/issue/PROJ-1/transitions');
    });

    test('jira_get_my_profile hits the myself endpoint', () {
      final body = jsonDecode(dispatcher.execute('jira_get_my_profile', {})!);
      expect(body['method'], 'GET');
      expect(body['path'], '/rest/api/latest/myself');
    });
  });
}

void _testJiraExtendedWriteTools() {
  group('SyncToolDispatcher Jira extended write tools', () {
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

    test('jira_update_field PUTs the field value', () {
      final body = jsonDecode(dispatcher.execute('jira_update_field', {
        'key': 'PROJ-1',
        'field': 'priority',
        'value': 'High',
      })!);
      expect(body['method'], 'PUT');
      expect(body['path'], '/rest/api/latest/issue/PROJ-1');
      final fields = jsonDecode(body['body'] as String)['fields'];
      expect(fields['priority'], 'High');
    });

    test('jira_update_description PUTs the description', () {
      final body = jsonDecode(dispatcher.execute('jira_update_description', {
        'key': 'PROJ-1',
        'description': 'Updated text',
      })!);
      final fields = jsonDecode(body['body'] as String)['fields'];
      expect(fields['description'], 'Updated text');
    });

    test('jira_assign_to PUTs accountId to the assignee endpoint', () {
      final body = jsonDecode(dispatcher.execute('jira_assign_to', {
        'key': 'PROJ-1',
        'accountId': 'acc-42',
      })!);
      expect(body['method'], 'PUT');
      expect(body['path'], '/rest/api/latest/issue/PROJ-1/assignee');
      expect(
        jsonDecode(body['body'] as String)['accountId'],
        'acc-42',
      );
    });
  });
}

void _testJiraLifecycleTools() {
  group('SyncToolDispatcher Jira lifecycle tools', () {
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

    test('jira_delete_ticket DELETEs the issue', () {
      final body = jsonDecode(
          dispatcher.execute('jira_delete_ticket', {'key': 'PROJ-1'})!);
      expect(body['method'], 'DELETE');
      expect(body['path'], '/rest/api/latest/issue/PROJ-1');
    });

    test('jira_create_ticket_basic POSTs the create body', () {
      final body = jsonDecode(dispatcher.execute(
        'jira_create_ticket_basic',
        {
          'project': 'PROJ',
          'issueType': 'Task',
          'summary': 'New work',
          'description': 'Details',
        },
      )!);
      expect(body['method'], 'POST');
      expect(body['path'], '/rest/api/latest/issue');
      final fields = jsonDecode(body['body'] as String)['fields'];
      expect(fields['project']['key'], 'PROJ');
      expect(fields['summary'], 'New work');
      expect(fields['description'], 'Details');
    });
  });
}

void _testJiraAliases() {
  group('SyncToolDispatcher Jira tool aliases', () {
    setUp(() => PropertyReader.setOverrides({
          'JIRA_BASE_PATH': '',
          'JIRA_LOGIN_PASS_TOKEN': '',
        }));

    tearDown(() => PropertyReader.clearOverrides());

    test('jira_assign alias routes to the assign executor', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('jira_assign', {'key': 'K'})!),
        {'error': 'Jira not configured'},
      );
    });

    test('jira_create_ticket alias routes to the create executor', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('jira_create_ticket', {})!),
        {'error': 'Jira not configured'},
      );
    });
  });
}

/// Verifies [toolName] with [args] is passed through to the non-HTTP handler
/// and returns the tool name the handler received.
String _expectDelegated(String toolName, Map<String, dynamic> args) {
  late String gotName;
  late Map<String, dynamic> gotArgs;
  final d = SyncToolDispatcher(
    PropertyReader(),
    nonHttpHandler: (name, a) {
      gotName = name;
      gotArgs = a;
      return '{"delegated":true}';
    },
  );
  expect(d.execute(toolName, args), '{"delegated":true}');
  expect(gotName, toolName);
  expect(gotArgs, args);
  return gotName;
}

void _testNonHttpDelegation() {
  group('SyncToolDispatcher non-HTTP delegation', () {
    test('delegates file_write to the handler', () {
      expect(
          _expectDelegated(
              'file_write', {'path': '/tmp/a.txt', 'content': 'x'}),
          'file_write');
    });

    test('delegates file_list to the handler', () {
      expect(_expectDelegated('file_list', {'path': '/tmp'}), 'file_list');
    });

    test('delegates file_exists to the handler', () {
      expect(_expectDelegated('file_exists', {'path': '/tmp/a.txt'}),
          'file_exists');
    });

    test('delegates file_delete to the handler', () {
      expect(_expectDelegated('file_delete', {'path': '/tmp/a.txt'}),
          'file_delete');
    });

    test('delegates cli_execute_command to the handler', () {
      expect(
          _expectDelegated('cli_execute_command', {
            'command': 'git',
            'args': ['status'],
          }),
          'cli_execute_command');
    });

    test('returns null for non-HTTP tool without a handler', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(d.execute('file_write', {'path': 'x'}), isNull);
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
        'workspace': 'octo',
        'repository': 'cat',
        'pullRequestId': 42,
      });
      final body = jsonDecode(result!);
      expect(body['method'], 'GET');
      expect(body['path'], '/repos/octo/cat/pulls/42');
    });

    test('github_get_pr sends Bearer auth header', () {
      final result = dispatcher.execute('github_get_pr', {
        'workspace': 'o',
        'repository': 'r',
        'pullRequestId': 1,
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
        'workspace': 'octo',
        'repository': 'cat',
        'pullRequestId': 42,
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
        'workspace': 'o',
        'repository': 'r',
        'pullRequestId': '7',
      });
      final body = jsonDecode(result!);
      expect(body['path'], '/repos/o/r/pulls/7');
    });
  });
}
