import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Batch-7 tests: getPriorities, getSecurityLevels, exportData,
/// getBoardIssues, getSprints — plus tool shapes and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPrioritiesTests();
  getSecurityLevelsTests();
  exportDataTests();
  getBoardIssuesTests();
  getSprintsTests();
  batch7ToolShapeTests();
  batch7ExecutorDispatchTests();
}

/// `jira_get_priorities` — GET `priority`.
void getPrioritiesTests() {
  group('JiraClient.getPriorities', () {
    test('returns the priority listing', () async {
      final f = mockJira((o) => routeByPath({'/priority': _prioritiesBody}, o));
      final result = await f.client.getPriorities();
      expect(result, hasLength(2));
      expect(result.first['name'], 'High');
      expect(f.adapter.calls.single.method, 'GET');
      expect(
          f.adapter.calls.single.path, endsWith('/rest/api/latest/priority'));
    });
  });
}

/// `jira_get_security_levels` — GET `securitylevel`.
void getSecurityLevelsTests() {
  group('JiraClient.getSecurityLevels', () {
    test('returns the security-level listing', () async {
      final f = mockJira(
          (o) => routeByPath({'/securitylevel': _securityLevelsBody}, o));
      final result = await f.client.getSecurityLevels();
      expect(result, hasLength(2));
      expect(result.first['name'], 'Public');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path,
          endsWith('/rest/api/latest/securitylevel'));
    });
  });
}

/// `jira_export_data` — delegates to full auto-paginating search.
void exportDataTests() {
  group('JiraClient.exportData', () {
    test('returns all issues matching the JQL via cursor search', () async {
      final f =
          mockJira((o) => routeByPath({'/search/jql': _exportIssuesBody}, o));
      final result = await f.client.exportData('project = X');
      expect(result, hasLength(1));
      expect(result.first['key'], 'X-1');
    });
  });
}

/// `jira_get_board_issues` — GET agile/1.0/board/{boardId}/issue.
void getBoardIssuesTests() {
  group('JiraClient.getBoardIssues', () {
    test('GETs the board issue endpoint with offset params', () async {
      final f =
          mockJira((o) => routeByPath({'/board/1/issue': _boardIssuesPage}, o));
      final result = await f.client.getBoardIssues(1);
      expect(result, hasLength(1));
      expect(result.first['key'], 'X-1');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/rest/agile/1.0/board/1/issue'));
      expect(call.queryParameters['startAt'], '0');
      expect(call.queryParameters['maxResults'], '100');
    });

    test('passes an optional jql filter through', () async {
      final f =
          mockJira((o) => routeByPath({'/board/1/issue': _boardIssuesPage}, o));
      await f.client.getBoardIssues(1, 'status = Done');
      expect(f.adapter.calls.single.queryParameters['jql'], 'status = Done');
    });

    test('auto-paginates across multiple offset pages', () async {
      final f = mockJira(_boardIssuesMultiPageRouter);
      final result = await f.client.getBoardIssues(1);
      expect(result, hasLength(2));
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].queryParameters['startAt'], '0');
      expect(f.adapter.calls[1].queryParameters['startAt'], '100');
    });
  });
}

/// `jira_get_sprints` — GET agile/1.0/board/{boardId}/sprint.
void getSprintsTests() {
  group('JiraClient.getSprints', () {
    test('GETs the sprint endpoint and returns the values array', () async {
      final f =
          mockJira((o) => routeByPath({'/board/1/sprint': _sprintsPage}, o));
      final result = await f.client.getSprints(1);
      expect(result, hasLength(1));
      expect(result.first['name'], 'Sprint 1');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/rest/agile/1.0/board/1/sprint'));
      expect(call.queryParameters['startAt'], '0');
    });

    test('auto-paginates using isLast until the last page', () async {
      final f = mockJira(_sprintsMultiPageRouter);
      final result = await f.client.getSprints(1);
      expect(result, hasLength(2));
      expect(f.adapter.calls, hasLength(2));
    });
  });
}

/// Tool-definition shapes for the batch-7 tools.
void batch7ToolShapeTests() {
  group('jira_tools batch-7 shapes', () {
    test('jira_export_data declares jql and optional array fields', () {
      final tool = jiraTools().firstWhere((t) => t.name == 'jira_export_data');
      expect(tool.category, 'search');
      expect(tool.params.map((p) => p.name).toList(), ['jql', 'fields']);
      expect(tool.params.first.required, isTrue);
      expect(tool.params.last.type, 'array');
    });

    test('jira_get_board_issues declares integer boardId and optional jql', () {
      final tool =
          jiraTools().firstWhere((t) => t.name == 'jira_get_board_issues');
      expect(tool.params.map((p) => p.name).toList(), ['boardId', 'jql']);
      expect(tool.params.first.type, 'integer');
      expect(tool.params.first.required, isTrue);
      expect(tool.params.last.required, isFalse);
    });

    test('jira_get_sprints declares a single integer boardId', () {
      final tool = jiraTools().firstWhere((t) => t.name == 'jira_get_sprints');
      expect(tool.params.map((p) => p.name).toList(), ['boardId']);
      expect(tool.params.first.type, 'integer');
      expect(tool.params.first.required, isTrue);
    });
  });
}

/// [JiraToolExecutor.execute] routes batch-7 tool names.
void batch7ExecutorDispatchTests() {
  group('JiraToolExecutor.execute (batch-7)', () {
    test('routes jira_get_priorities to GET priority', () async {
      final f = mockJira((o) => routeByPath({'/priority': _prioritiesBody}, o));
      expect(
          await executor(f).execute('jira_get_priorities', {}), hasLength(2));
    });

    test('routes jira_get_security_levels to GET securitylevel', () async {
      final f = mockJira(
          (o) => routeByPath({'/securitylevel': _securityLevelsBody}, o));
      expect(await executor(f).execute('jira_get_security_levels', {}),
          hasLength(2));
    });

    test('routes jira_export_data with jql and fields', () async {
      final f =
          mockJira((o) => routeByPath({'/search/jql': _exportIssuesBody}, o));
      final result = await executor(f).execute('jira_export_data', {
        'jql': 'project = X',
        'fields': ['summary'],
      });
      expect(result, hasLength(1));
      expect(f.adapter.calls.single.queryParameters['fields'], 'summary');
    });

    test('routes jira_get_board_issues with boardId', () async {
      final f =
          mockJira((o) => routeByPath({'/board/1/issue': _boardIssuesPage}, o));
      expect(await executor(f).execute('jira_get_board_issues', {'boardId': 1}),
          hasLength(1));
    });

    test('routes jira_get_sprints with boardId', () async {
      final f =
          mockJira((o) => routeByPath({'/board/1/sprint': _sprintsPage}, o));
      expect(await executor(f).execute('jira_get_sprints', {'boardId': 1}),
          hasLength(1));
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Returns different board-issue pages based on the `startAt` query param.
String _boardIssuesMultiPageRouter(RequestOptions o) {
  if (!o.path.contains('/board/1/issue')) return '{}';
  final startAt = int.tryParse('${o.queryParameters['startAt']}') ?? 0;
  if (startAt == 0) return '{"issues":[{"key":"X-1"}],"total":150}';
  return '{"issues":[{"key":"X-101"}],"total":150}';
}

/// Returns different sprint pages based on the `startAt` query param.
String _sprintsMultiPageRouter(RequestOptions o) {
  if (!o.path.contains('/board/1/sprint')) return '{}';
  final startAt = int.tryParse('${o.queryParameters['startAt']}') ?? 0;
  if (startAt == 0) {
    return '{"values":[{"id":1,"name":"Sprint 1"}],"isLast":false,"total":150}';
  }
  return '{"values":[{"id":2,"name":"Sprint 2"}],"isLast":true,"total":150}';
}

/// Canned priority listing with two entries.
const _prioritiesBody = '[{"name":"High","id":"1"},{"name":"Low","id":"2"}]';

/// Canned security-level listing with two entries.
const _securityLevelsBody =
    '[{"name":"Public","id":"100"},{"name":"Internal","id":"101"}]';

/// Canned cursor-search body with one issue for export.
const _exportIssuesBody = '{"issues":[{"key":"X-1"}]}';

/// Canned single board-issue page with total=1 (no further pagination).
const _boardIssuesPage = '{"issues":[{"key":"X-1"}],"total":1}';

/// Canned single sprint page marked as last (no further pagination).
const _sprintsPage =
    '{"values":[{"id":1,"name":"Sprint 1"}],"isLast":true,"total":1}';
