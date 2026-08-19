import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Resolution tests: getResolutions — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getResolutionsTests();
  resolutionsExecutorDispatchTests();
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

/// [JiraToolExecutor.execute] routes resolution tool names.
void resolutionsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (resolutions)', () {
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

/// Canned resolution listing with two entries.
const _resolutionsBody =
    '[{"name":"Done","id":"10000"},{"name":"Incomplete","id":"10001"}]';
