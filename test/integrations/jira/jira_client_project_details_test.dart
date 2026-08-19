import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Project-details tests: getProjectDetails, getProjectStatuses
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getProjectDetailsTests();
  getProjectStatusesTests();
  projectDetailsExecutorDispatchTests();
}

/// `jira_get_project_details` — GET `project/{key}`.
void getProjectDetailsTests() {
  group('JiraClient.getProjectDetails', () {
    test('returns the project map', () async {
      final f =
          mockJira((o) => routeByPath({'/project/PROJ': _projectBody}, o));
      final result = await f.client.getProjectDetails('PROJ');
      expect(result['key'], 'PROJ');
      expect(result['name'], 'Project X');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getProjectDetails('PROJ'), isEmpty);
    });
  });
}

/// `jira_get_project_statuses` — GET `project/{project}/statuses`.
void getProjectStatusesTests() {
  group('JiraClient.getProjectStatuses', () {
    test('returns the statuses array', () async {
      final f = mockJira(
          (o) => routeByPath({'/project/PROJ/statuses': _statusesBody}, o));
      final result = await f.client.getProjectStatuses('PROJ');
      expect(result, hasLength(2));
      expect(result[0]['name'], 'To Do');
      expect(result[1]['name'], 'In Progress');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when the body is not an array', () async {
      final f = mockJira((o) => '{}');
      expect(await f.client.getProjectStatuses('PROJ'), isEmpty);
    });
  });
}

/// [JiraToolExecutor.execute] routes project-detail tool names correctly.
void projectDetailsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (project details)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_get_project_details', () async {
      await executor.execute('jira_get_project_details', {
        'projectKey': 'PROJ',
      });
      expect(spy.calls, ['getProjectDetails:PROJ']);
    });

    test('routes jira_get_project_statuses', () async {
      await executor.execute('jira_get_project_statuses', {
        'project': 'PROJ',
      });
      expect(spy.calls, ['getProjectStatuses:PROJ']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyJiraClient extends JiraClient {
  _SpyJiraClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> getProjectDetails(String projectKey) {
    calls.add('getProjectDetails:$projectKey');
    return super.getProjectDetails(projectKey);
  }

  @override
  Future<List<Map<String, dynamic>>> getProjectStatuses(String project) {
    calls.add('getProjectStatuses:$project');
    return super.getProjectStatuses(project);
  }
}

/// Canned `project/{key}` body.
const _projectBody =
    '{"key":"PROJ","name":"Project X","id":"10000","style":"classic"}';

/// Canned `project/{project}/statuses` body.
const _statusesBody =
    '[{"id":"1","name":"To Do"},{"id":"2","name":"In Progress"}]';
