import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Export tests: exportData — plus the export tool shape and executor
/// dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  exportDataTests();
  exportToolShapeTests();
  exportExecutorDispatchTests();
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

/// Tool-definition shapes for the export tool.
void exportToolShapeTests() {
  group('jira_tools export shapes', () {
    test('jira_export_data declares jql and optional array fields', () {
      final tool = jiraTools().firstWhere((t) => t.name == 'jira_export_data');
      expect(tool.category, 'search');
      expect(tool.params.map((p) => p.name).toList(), ['jql', 'fields']);
      expect(tool.params.first.required, isTrue);
      expect(tool.params.last.type, 'array');
    });
  });
}

/// [JiraToolExecutor.execute] routes export tool names.
void exportExecutorDispatchTests() {
  group('JiraToolExecutor.execute (export)', () {
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
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned cursor-search body with one issue for export.
const _exportIssuesBody = '{"issues":[{"key":"X-1"}]}';
