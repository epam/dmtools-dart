import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Batch-3 tests: getIssueTypes, getFields, getComponents, getFixVersions,
/// setFixVersion, setPriority, getSubtasks, updateDescription,
/// createTicketWithParent — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getIssueTypesTests();
  getFieldsTests();
  getComponentsTests();
  getFixVersionsTests();
  setFixVersionTests();
  setPriorityTests();
  getSubtasksTests();
  updateDescriptionTests();
  createTicketWithParentTests();
  batch3ExecutorReadDispatchTests();
  batch3ExecutorWriteDispatchTests();
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

/// `jira_set_fix_version` — PUT `issue/{key}` with fixVersions field.
void setFixVersionTests() {
  group('JiraClient.setFixVersion', () {
    test('PUTs the fixVersions field', () async {
      final f = mockJira((o) => '{}');
      await f.client.setFixVersion('PROJ-1', '1.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issue/PROJ-1'));
      expect(jsonDecode(call.data as String), {
        'fields': {
          'fixVersions': [
            {'name': '1.0'}
          ],
        },
      });
    });
  });
}

/// `jira_set_priority` — PUT `issue/{key}` with priority field.
void setPriorityTests() {
  group('JiraClient.setPriority', () {
    test('PUTs the priority field', () async {
      final f = mockJira((o) => '{}');
      await f.client.setPriority('PROJ-1', 'High');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issue/PROJ-1'));
      expect(jsonDecode(call.data as String), {
        'fields': {
          'priority': {'name': 'High'},
        },
      });
    });
  });
}

/// `jira_get_subtasks` — parses `fields.subtasks` from the ticket.
void getSubtasksTests() {
  group('JiraClient.getSubtasks', () {
    test('returns the fields.subtasks array', () async {
      final f =
          mockJira((o) => routeByPath({'/issue/PROJ-1': _subtasksBody}, o));
      final result = await f.client.getSubtasks('PROJ-1');
      expect(result, hasLength(2));
      expect(result[0]['key'], 'PROJ-2');
      expect(result[1]['key'], 'PROJ-3');
    });

    test('returns an empty list when subtasks is absent', () async {
      final f = mockJira((o) => routeByPath(
          {'/issue/PROJ-1': _noSubtasksBody}, o,
          fallback: _noSubtasksBody));
      expect(await f.client.getSubtasks('PROJ-1'), isEmpty);
    });
  });
}

/// `jira_update_description` — PUT `issue/{key}` with description field.
void updateDescriptionTests() {
  group('JiraClient.updateDescription', () {
    test('PUTs the description field', () async {
      final f = mockJira((o) => '{}');
      await f.client.updateDescription('PROJ-1', 'New desc');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issue/PROJ-1'));
      expect(jsonDecode(call.data as String), {
        'fields': {'description': 'New desc'},
      });
    });
  });
}

/// `jira_create_ticket_with_parent` — POST `issue` with parent link.
void createTicketWithParentTests() {
  group('JiraClient.createTicketWithParent', () {
    test('POSTs with the parent link', () async {
      final f = mockJira((o) => routeByPath({'/issue': _createdBody}, o));
      final result = await f.client.createTicketWithParent(
        'PROJ',
        'Sub-task',
        'Title',
        'PROJ-1',
      );
      expect(result['key'], 'PROJ-2');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/issue'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      final fields = decoded['fields'] as Map<String, dynamic>;
      expect(fields['summary'], 'Title');
      expect(fields['parent'], {'key': 'PROJ-1'});
      expect(fields['project'], {'key': 'PROJ'});
      expect(fields['issuetype'], {'name': 'Sub-task'});
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(
        await f.client.createTicketWithParent('PROJ', 'Task', 'T', 'PROJ-1'),
        isEmpty,
      );
    });
  });
}

/// [JiraToolExecutor.execute] routes batch-3 read tool names correctly.
void batch3ExecutorReadDispatchTests() {
  group('JiraToolExecutor.execute (batch-3 reads)', () {
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

    test('routes jira_get_subtasks with key', () async {
      await executor.execute('jira_get_subtasks', {'key': 'PROJ-1'});
      expect(spy.calls, ['getSubtasks:PROJ-1']);
    });
  });
}

/// [JiraToolExecutor.execute] routes batch-3 write tool names correctly.
void batch3ExecutorWriteDispatchTests() {
  group('JiraToolExecutor.execute (batch-3 writes)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_set_fix_version with key and fixVersion', () async {
      await executor.execute('jira_set_fix_version', {
        'key': 'PROJ-1',
        'fixVersion': '1.0',
      });
      expect(spy.calls, ['setFixVersion:PROJ-1:1.0']);
    });

    test('routes jira_set_priority with key and priority', () async {
      await executor.execute('jira_set_priority', {
        'key': 'PROJ-1',
        'priority': 'High',
      });
      expect(spy.calls, ['setPriority:PROJ-1:High']);
    });

    test('routes jira_update_description with key and description', () async {
      await executor.execute('jira_update_description', {
        'key': 'PROJ-1',
        'description': 'desc',
      });
      expect(spy.calls, ['updateDescription:PROJ-1:desc']);
    });

    test('routes jira_create_ticket_with_parent', () async {
      await executor.execute('jira_create_ticket_with_parent', {
        'project': 'PROJ',
        'issueType': 'Task',
        'summary': 'Title',
        'parentKey': 'PROJ-1',
      });
      expect(spy.calls, ['createTicketWithParent:PROJ:Task:Title:PROJ-1']);
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

  @override
  Future<void> setFixVersion(String key, String versionName) {
    calls.add('setFixVersion:$key:$versionName');
    return super.setFixVersion(key, versionName);
  }

  @override
  Future<void> setPriority(String key, String priorityName) {
    calls.add('setPriority:$key:$priorityName');
    return super.setPriority(key, priorityName);
  }

  @override
  Future<List<Map<String, dynamic>>> getSubtasks(String key) {
    calls.add('getSubtasks:$key');
    return super.getSubtasks(key);
  }

  @override
  Future<void> updateDescription(String key, String description) {
    calls.add('updateDescription:$key:$description');
    return super.updateDescription(key, description);
  }

  @override
  Future<Map<String, dynamic>> createTicketWithParent(
    String project,
    String issueType,
    String summary,
    String parentKey,
  ) {
    calls.add('createTicketWithParent:$project:$issueType:$summary:$parentKey');
    return super.createTicketWithParent(project, issueType, summary, parentKey);
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

/// Canned `issue/{key}` body containing subtasks.
const _subtasksBody =
    '{"key":"PROJ-1","fields":{"subtasks":[{"key":"PROJ-2"},{"key":"PROJ-3"}]}}';

/// Canned `issue/{key}` body without subtasks.
const _noSubtasksBody = '{"key":"PROJ-1","fields":{}}';

/// Canned `/issue` POST (create) response body.
const _createdBody = '{"key":"PROJ-2","id":"10042"}';
