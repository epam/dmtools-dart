import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Project-metadata tests: getIssueTypes, getFields, getComponents,
/// getFixVersions — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getIssueTypesTests();
  getFieldsTests();
  getComponentsTests();
  getFixVersionsTests();
  projectMetadataExecutorDispatchTests();
}

/// `jira_get_issue_types` — GET `issue/createmeta/{project}/issuetypes`.
void getIssueTypesTests() {
  group('JiraClient.getIssueTypes', () {
    test('returns the issueTypes array', () async {
      final f = mockJira((o) => routeByPath(
          {'/issue/createmeta/PROJ/issuetypes': _issueTypesBody}, o));
      final result = await f.client.getIssueTypes('PROJ');
      expect(result, hasLength(2));
      expect(result[0]['name'], 'Task');
      expect(result[1]['name'], 'Bug');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when issueTypes is absent', () async {
      final f = mockJira((o) => '{}');
      expect(await f.client.getIssueTypes('PROJ'), isEmpty);
    });

    test('returns an empty list when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getIssueTypes('PROJ'), isEmpty);
    });
  });
}

/// `jira_get_fields` — GET `issue/createmeta/{project}/issuetypes`.
void getFieldsTests() {
  group('JiraClient.getFields', () {
    test('returns the decoded createmeta body', () async {
      final f = mockJira((o) =>
          routeByPath({'/issue/createmeta/PROJ/issuetypes': _fieldsBody}, o));
      final result = await f.client.getFields('PROJ');
      expect(result['issueTypes'], isNotNull);
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getFields('PROJ'), isEmpty);
    });
  });
}

/// `jira_get_components` — GET `project/{project}/components`.
void getComponentsTests() {
  group('JiraClient.getComponents', () {
    test('returns the components array', () async {
      final f = mockJira(
          (o) => routeByPath({'/project/PROJ/components': _componentsBody}, o));
      final result = await f.client.getComponents('PROJ');
      expect(result, hasLength(2));
      expect(result[0]['name'], 'Backend');
      expect(result[1]['name'], 'Frontend');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when the body is not an array', () async {
      final f = mockJira((o) => '{}');
      expect(await f.client.getComponents('PROJ'), isEmpty);
    });
  });
}

/// `jira_get_fix_versions` — GET `project/{project}/versions`.
void getFixVersionsTests() {
  group('JiraClient.getFixVersions', () {
    test('returns the versions array', () async {
      final f = mockJira(
          (o) => routeByPath({'/project/PROJ/versions': _versionsBody}, o));
      final result = await f.client.getFixVersions('PROJ');
      expect(result, hasLength(2));
      expect(result[0]['name'], '1.0');
      expect(result[1]['name'], '2.0');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when the body is not an array', () async {
      final f = mockJira((o) => '{}');
      expect(await f.client.getFixVersions('PROJ'), isEmpty);
    });
  });
}

/// [JiraToolExecutor.execute] routes project-metadata tool names correctly.
void projectMetadataExecutorDispatchTests() {
  group('JiraToolExecutor.execute (project metadata)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_get_issue_types with project', () async {
      await executor.execute('jira_get_issue_types', {'project': 'PROJ'});
      expect(spy.calls, ['getIssueTypes:PROJ']);
    });

    test('routes jira_get_fields with project', () async {
      await executor.execute('jira_get_fields', {'project': 'PROJ'});
      expect(spy.calls, ['getFields:PROJ']);
    });

    test('routes jira_get_components with project', () async {
      await executor.execute('jira_get_components', {'project': 'PROJ'});
      expect(spy.calls, ['getComponents:PROJ']);
    });

    test('routes jira_get_fix_versions with project', () async {
      await executor.execute('jira_get_fix_versions', {'project': 'PROJ'});
      expect(spy.calls, ['getFixVersions:PROJ']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyJiraClient extends JiraClient {
  _SpyJiraClient(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getIssueTypes(String project) {
    calls.add('getIssueTypes:$project');
    return super.getIssueTypes(project);
  }

  @override
  Future<Map<String, dynamic>> getFields(String project) {
    calls.add('getFields:$project');
    return super.getFields(project);
  }

  @override
  Future<List<Map<String, dynamic>>> getComponents(String project) {
    calls.add('getComponents:$project');
    return super.getComponents(project);
  }

  @override
  Future<List<Map<String, dynamic>>> getFixVersions(String project) {
    calls.add('getFixVersions:$project');
    return super.getFixVersions(project);
  }
}

/// Canned `issue/createmeta/{project}/issuetypes` (issue types) body.
const _issueTypesBody =
    '{"issueTypes":[{"id":"1","name":"Task"},{"id":"2","name":"Bug"}]}';

/// Canned `issue/createmeta/{project}/issuetypes` (fields) body.
const _fieldsBody =
    '{"issueTypes":[{"id":"1","name":"Task","fields":{"summary":{}}}]}';

/// Canned `project/{project}/components` body.
const _componentsBody =
    '[{"id":"10","name":"Backend"},{"id":"11","name":"Frontend"}]';

/// Canned `project/{project}/versions` body.
const _versionsBody = '[{"id":"20","name":"1.0"},{"id":"21","name":"2.0"}]';
