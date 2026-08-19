import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Agile-board tests: getBoardIssues, getSprints — plus the board tool
/// shapes and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getBoardIssuesTests();
  getSprintsTests();
  boardsToolShapeTests();
  boardsExecutorDispatchTests();
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

/// Tool-definition shapes for the agile-board tools.
void boardsToolShapeTests() {
  group('jira_tools board shapes', () {
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

/// [JiraToolExecutor.execute] routes agile-board tool names.
void boardsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (boards)', () {
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

/// Canned single board-issue page with total=1 (no further pagination).
const _boardIssuesPage = '{"issues":[{"key":"X-1"}],"total":1}';

/// Canned single sprint page marked as last (no further pagination).
const _sprintsPage =
    '{"values":[{"id":1,"name":"Sprint 1"}],"isLast":true,"total":1}';
