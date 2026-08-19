import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Search tests: searchByPage, searchWithPagination — plus the search tool
/// shapes and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  searchByPageTests();
  searchWithPaginationTests();
  searchToolShapeTests();
  searchExecutorDispatchTests();
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

/// Tool-definition shapes for the search tools.
void searchToolShapeTests() {
  group('jira_tools search shapes', () {
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

/// [JiraToolExecutor.execute] routes search tools.
void searchExecutorDispatchTests() {
  group('JiraToolExecutor.execute (search)', () {
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

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned cursor-page body with one issue and a next token.
const _cursorPageBody = '{"issues":[{"key":"X-1"}],"nextPageToken":"token-2"}';

/// Canned offset-page body with totals.
const _offsetPageBody =
    '{"issues":[{"key":"X-51"}],"total":150,"startAt":50,"maxResults":100}';
