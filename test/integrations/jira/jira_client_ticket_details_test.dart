import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Ticket-detail tests: getAttachments, getWorklogs, getWatchers,
/// addWatcher, removeWatcher — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getAttachmentsTests();
  getWorklogsTests();
  getWatchersTests();
  addRemoveWatcherTests();
  ticketDetailsExecutorDispatchTests();
}

/// `jira_get_attachments` — reads `fields.attachment` from the ticket.
void getAttachmentsTests() {
  group('JiraClient.getAttachments', () {
    test('reads the attachment array from the ticket', () async {
      final f = mockJira(
          (o) => routeByPath({'/issue/PROJ-1': _ticketWithAttachment}, o));
      final result = await f.client.getAttachments('PROJ-1');
      expect(result, hasLength(1));
      expect(result.first['filename'], 'notes.txt');
      expect(f.adapter.calls.single.queryParameters['fields'], 'attachment');
    });

    test('returns empty when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getAttachments('PROJ-1'), isEmpty);
    });
  });
}

/// `jira_get_worklogs` — GET `issue/{key}/worklog`.
void getWorklogsTests() {
  group('JiraClient.getWorklogs', () {
    test('returns the worklogs array', () async {
      final f = mockJira(
          (o) => routeByPath({'/issue/PROJ-1/worklog': _worklogsBody}, o));
      final result = await f.client.getWorklogs('PROJ-1');
      expect(result, hasLength(2));
      expect(result.first['timeSpent'], '1h');
      expect(f.adapter.calls.single.method, 'GET');
    });
  });
}

/// `jira_get_watchers` — GET `issue/{key}/watchers`.
void getWatchersTests() {
  group('JiraClient.getWatchers', () {
    test('returns the watchers array', () async {
      final f = mockJira(
          (o) => routeByPath({'/issue/PROJ-1/watchers': _watchersBody}, o));
      final result = await f.client.getWatchers('PROJ-1');
      expect(result, hasLength(1));
      expect(result.first['accountId'], 'acct-1');
    });
  });
}

/// `jira_add_watcher` / `jira_remove_watcher` — POST then DELETE watchers.
void addRemoveWatcherTests() {
  group('JiraClient.addWatcher', () {
    test('POSTs the accountId as a bare JSON string', () async {
      final f = mockJira((o) => '{}');
      await f.client.addWatcher('PROJ-1', 'acct-9');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/issue/PROJ-1/watchers'));
      expect(call.data, '"acct-9"');
    });
  });

  group('JiraClient.removeWatcher', () {
    test('DELETEs with the accountId query parameter', () async {
      final f = mockJira((o) => '{}');
      await f.client.removeWatcher('PROJ-1', 'acct-9');
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/issue/PROJ-1/watchers'));
      expect(call.queryParameters['accountId'], 'acct-9');
    });
  });
}

/// [JiraToolExecutor.execute] routes ticket-detail and watcher tools.
void ticketDetailsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (ticket details)', () {
    test('routes the ticket read tools to their endpoints', () async {
      final routes = {
        '/issue/PROJ-1': _ticketWithAttachment,
        '/issue/PROJ-1/worklog': _worklogsBody,
        '/issue/PROJ-1/watchers': _watchersBody,
      };
      final f = mockJira((o) => routeByPath(routes, o));
      expect(
          await executor(f).execute('jira_get_attachments', {'key': 'PROJ-1'}),
          hasLength(1));
      expect(await executor(f).execute('jira_get_worklogs', {'key': 'PROJ-1'}),
          hasLength(2));
      expect(await executor(f).execute('jira_get_watchers', {'key': 'PROJ-1'}),
          hasLength(1));
    });

    test('routes jira_add_watcher and jira_remove_watcher', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute(
          'jira_add_watcher', {'key': 'PROJ-1', 'accountId': 'acct-9'});
      expect(f.adapter.calls.single.method, 'POST');
      expect(f.adapter.calls.single.data, '"acct-9"');
      await executor(f).execute(
          'jira_remove_watcher', {'key': 'PROJ-1', 'accountId': 'acct-9'});
      expect(f.adapter.calls.last.method, 'DELETE');
      expect(f.adapter.calls.last.queryParameters['accountId'], 'acct-9');
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned ticket body with one attachment.
const _ticketWithAttachment =
    '{"key":"PROJ-1","fields":{"attachment":[{"filename":"notes.txt","size":12}]}}';

/// Canned worklog body with two entries.
const _worklogsBody = '{"worklogs":[{"timeSpent":"1h"},{"timeSpent":"2h"}]}';

/// Canned watchers body with one watcher.
const _watchersBody =
    '{"watchers":[{"accountId":"acct-1","displayName":"Dev"}]}';
