import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Metadata-listing tests: getPriorities, getSecurityLevels
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPrioritiesTests();
  getSecurityLevelsTests();
  metadataExecutorDispatchTests();
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

/// [JiraToolExecutor.execute] routes metadata-listing tool names.
void metadataExecutorDispatchTests() {
  group('JiraToolExecutor.execute (metadata listings)', () {
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
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned priority listing with two entries.
const _prioritiesBody = '[{"name":"High","id":"1"},{"name":"Low","id":"2"}]';

/// Canned security-level listing with two entries.
const _securityLevelsBody =
    '[{"name":"Public","id":"100"},{"name":"Internal","id":"101"}]';
