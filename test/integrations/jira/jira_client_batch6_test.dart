import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Batch-6 tests: searchByPage, searchWithPagination, getAttachments,
/// getWorklogs, getWatchers, addWatcher, removeWatcher, getResolutions
/// — plus tool shapes and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  searchByPageTests();
  searchWithPaginationTests();
  getAttachmentsTests();
  getWorklogsTests();
  getWatchersTests();
  addRemoveWatcherTests();
  getResolutionsTests();
  batch6ToolShapeTests();
  batch6ExecutorDispatchSearchTests();
  batch6ExecutorDispatchTicketTests();
}

/// `jira_search_by_page` — GET `search/jql` returning one cursor page.
void searchByPageTests() {
  group('JiraClient.searchByPage', () {
    test('GETs search/jql with default fields and no token', () async {
      final f =
          mockJira((o) => routeByPath({'/search/jql': _cursorPageBody}, o));
      final result = await f.client.searchByPage('project = X');
      expect(result['nextPageToken'], 'token-2');
      expect(result['issues'] as List, hasLength(1));
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/rest/api/latest/search/jql'));
      expect(call.queryParameters['jql'], 'project = X');
      expect(call.queryParameters['fields'], '*navigable');
      expect(call.queryParameters.containsKey('nextPageToken'), isFalse);
    });

    test('passes nextPageToken and fields through', () async {
      final f =
          mockJira((o) => routeByPath({'/search/jql': '{"issues":[]}'}, o));
      await f.client.searchByPage('project = X', 'token-1', ['summary']);
      final call = f.adapter.calls.single;
      expect(call.queryParameters['nextPageToken'], 'token-1');
      expect(call.queryParameters['fields'], 'summary');
    });
  });
}

/// `jira_search_with_pagination` — GET `search` returning one offset page.
void searchWithPaginationTests() {
  group('JiraClient.searchWithPagination', () {
    test('GETs search with startAt offset and maxResults 100', () async {
      final f = mockJira((o) => routeByPath({'/search': _offsetPageBody}, o));
      final result = await f.client.searchWithPagination('project = X', 50);
      expect(result['total'], 150);
      expect(result['startAt'], 50);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/rest/api/latest/search'));
      expect(call.queryParameters['startAt'], '50');
      expect(call.queryParameters['maxResults'], '100');
    });

    test('defaults startAt to zero and fields to *navigable', () async {
      final f = mockJira((o) => routeByPath({'/search': _offsetPageBody}, o));
      await f.client.searchWithPagination('project = X');
      final call = f.adapter.calls.single;
      expect(call.queryParameters['startAt'], '0');
      expect(call.queryParameters['fields'], '*navigable');
    });
  });
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

/// `jira_get_resolutions` — GET `resolution`.
void getResolutionsTests() {
  group('JiraClient.getResolutions', () {
    test('returns the resolution listing', () async {
      final f =
          mockJira((o) => routeByPath({'/resolution': _resolutionsBody}, o));
      final result = await f.client.getResolutions();
      expect(result, hasLength(2));
      expect(result.first['name'], 'Done');
    });
  });
}

/// Tool-definition shapes for the batch-6 search tools.
void batch6ToolShapeTests() {
  group('jira_tools batch-6 shapes', () {
    test('jira_search_by_page declares jql, nextPageToken, fields', () {
      final tool =
          jiraTools().firstWhere((t) => t.name == 'jira_search_by_page');
      expect(tool.category, 'search');
      expect(tool.params.map((p) => p.name).toList(),
          ['jql', 'nextPageToken', 'fields']);
      expect(tool.params.first.required, isTrue);
    });

    test('jira_search_with_pagination declares jql, startAt, fields', () {
      final tool = jiraTools()
          .firstWhere((t) => t.name == 'jira_search_with_pagination');
      expect(tool.params.map((p) => p.name).toList(),
          ['jql', 'startAt', 'fields']);
      expect(tool.params[1].type, 'integer');
      expect(tool.params[1].required, isFalse);
    });
  });
}

/// [JiraToolExecutor.execute] routes batch-6 search tools.
void batch6ExecutorDispatchSearchTests() {
  group('JiraToolExecutor.execute (batch-6 search)', () {
    test('routes jira_search_by_page with cursor', () async {
      final f =
          mockJira((o) => routeByPath({'/search/jql': _cursorPageBody}, o));
      final result = await executor(f).execute('jira_search_by_page', {
        'jql': 'project = X',
        'nextPageToken': 'token-1',
        'fields': ['summary'],
      });
      expect(result['nextPageToken'], 'token-2');
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/search/jql'));
      expect(call.queryParameters['nextPageToken'], 'token-1');
      expect(call.queryParameters['fields'], 'summary');
    });

    test('routes jira_search_with_pagination with offset', () async {
      final f = mockJira((o) => routeByPath({'/search': _offsetPageBody}, o));
      final result = await executor(f).execute('jira_search_with_pagination', {
        'jql': 'project = X',
        'startAt': 25,
      });
      expect(result['total'], 150);
      expect(f.adapter.calls.single.queryParameters['startAt'], '25');
    });
  });
}

/// [JiraToolExecutor.execute] routes batch-6 ticket/watcher/resolution tools.
void batch6ExecutorDispatchTicketTests() {
  group('JiraToolExecutor.execute (batch-6 ticket)', () {
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

    test('routes jira_get_resolutions', () async {
      final f =
          mockJira((o) => routeByPath({'/resolution': _resolutionsBody}, o));
      expect(
          await executor(f).execute('jira_get_resolutions', {}), hasLength(2));
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned cursor-page body with one issue and a next token.
const _cursorPageBody = '{"issues":[{"key":"X-1"}],"nextPageToken":"token-2"}';

/// Canned offset-page body with totals.
const _offsetPageBody =
    '{"issues":[{"key":"X-51"}],"total":150,"startAt":50,"maxResults":100}';

/// Canned ticket body with one attachment.
const _ticketWithAttachment =
    '{"key":"PROJ-1","fields":{"attachment":[{"filename":"notes.txt","size":12}]}}';

/// Canned worklog body with two entries.
const _worklogsBody = '{"worklogs":[{"timeSpent":"1h"},{"timeSpent":"2h"}]}';

/// Canned watchers body with one watcher.
const _watchersBody =
    '{"watchers":[{"accountId":"acct-1","displayName":"Dev"}]}';

/// Canned resolution listing with two entries.
const _resolutionsBody =
    '[{"name":"Done","id":"10000"},{"name":"Incomplete","id":"10001"}]';
