import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Project-administration tests: deleteProject, getProjectBoardConfig,
/// issue-type and workflow scheme assignment, createProjectIssueType,
/// setupProjectWorkflow, syncProjectWorkflow, copyProjectStructure,
/// cloneProject — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  deleteProjectTests();
  restoreProjectTests();
  getProjectBoardConfigTests();
  issueTypeSchemeTests();
  workflowSchemeTests();
  createProjectIssueTypeTests();
  setupProjectWorkflowTests();
  syncProjectWorkflowTests();
  copyProjectStructureTests();
  cloneProjectTests();
  projectAdminExecutorDispatchSetupTests();
  projectAdminExecutorDispatchReadTests();
  projectAdminExecutorDispatchCreateTests();
  projectAdminExecutorDispatchSchemeTests();
}

/// `jira_delete_project` — DELETE `project/{key}` with confirmation.
void deleteProjectTests() {
  group('JiraClient.deleteProject', () {
    test('DELETEs the project when confirmed', () async {
      final f = mockJira((o) => '{}');
      await f.client.deleteProject('PROJ', true);
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/project/PROJ'));
    });

    test('is a no-op when confirmDelete is false', () async {
      final f = mockJira((o) => '{}');
      await f.client.deleteProject('PROJ', false);
      expect(f.adapter.calls, isEmpty);
    });
  });
}

/// `jira_restore_project` — POST `project/{key}/restore`.
void restoreProjectTests() {
  group('JiraClient.restoreProject', () {
    test('POSTs to the restore endpoint and reports the project', () async {
      final f =
          mockJira((o) => '{"key":"PROJ","id":"10000","name":"My Project"}');
      final result = await f.client.restoreProject('PROJ');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/project/PROJ/restore'));
      expect(result['success'], isTrue);
      expect(result['projectKey'], 'PROJ');
      expect(result['projectId'], '10000');
      expect(result['projectName'], 'My Project');
      expect(result['message'], 'Project restored successfully');
    });

    test('falls back to the given key when the body omits fields', () async {
      final f = mockJira((o) => '{}');
      final result = await f.client.restoreProject('PROJ');
      expect(result['projectKey'], 'PROJ');
      expect(result['projectId'], '');
      expect(result['projectName'], '');
    });
  });
}

/// `jira_get_project_board_config` — Agile board lookup + configuration.
void getProjectBoardConfigTests() {
  group('JiraClient.getProjectBoardConfig', () {
    test('finds the board then fetches its configuration', () async {
      final f = mockJira((o) => routeByPath({
            '/rest/agile/1.0/board': _boardListBody,
            '/rest/agile/1.0/board/42/configuration': _boardConfigBody,
          }, o));
      final result = await f.client.getProjectBoardConfig('PROJ');
      expect(result['columnConfig'], isNotNull);
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].method, 'GET');
      expect(f.adapter.calls[1].path, endsWith('/board/42/configuration'));
    });

    test('returns an empty map when the project has no board', () async {
      final f = mockJira((o) => '{"values":[]}');
      expect(await f.client.getProjectBoardConfig('PROJ'), isEmpty);
      expect(f.adapter.calls.single.method, 'GET');
    });
  });
}

/// `jira_get_project_issue_type_scheme` / `jira_assign_issue_type_scheme`.
void issueTypeSchemeTests() {
  group('JiraClient.getProjectIssueTypeScheme', () {
    test('GETs the issue-type scheme for the project', () async {
      final f = mockJira((o) =>
          routeByPath({'/project/PROJ/issueTypeScheme': _schemeBody}, o));
      final result = await f.client.getProjectIssueTypeScheme('PROJ');
      expect(result['id'], 10100);
      expect(result['name'], 'Default Software Scheme');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path,
          endsWith('/project/PROJ/issueTypeScheme'));
    });
  });

  group('JiraClient.assignIssueTypeScheme', () {
    test('PUTs projectId under issuetypescheme/{schemeId}/project', () async {
      final f = mockJira((o) => '{}');
      await f.client.assignIssueTypeScheme('10000', '10100');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issuetypescheme/10100/project'));
      expect(jsonDecode(call.data as String), {'projectId': '10000'});
    });
  });
}

/// `jira_get_project_workflow_scheme` / `jira_assign_workflow_scheme`.
void workflowSchemeTests() {
  group('JiraClient.getProjectWorkflowScheme', () {
    test('GETs the workflow scheme for the project', () async {
      final f = mockJira((o) => routeByPath(
          {'/project/PROJ/workflowScheme': _workflowSchemeBody}, o));
      final result = await f.client.getProjectWorkflowScheme('PROJ');
      expect(result['id'], 10200);
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path,
          endsWith('/project/PROJ/workflowScheme'));
    });
  });

  group('JiraClient.assignWorkflowScheme', () {
    test('PUTs projectId under workflowscheme/{schemeId}/project', () async {
      final f = mockJira((o) => '{}');
      await f.client.assignWorkflowScheme('10000', '10200');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/workflowscheme/10200/project'));
      expect(jsonDecode(call.data as String), {'projectId': '10000'});
    });
  });
}

/// `jira_create_project_issue_type` — POST `issuetype`.
void createProjectIssueTypeTests() {
  group('JiraClient.createProjectIssueType', () {
    test('POSTs name and type', () async {
      final f = mockJira(
          (o) => routeByPath({'/issuetype': '{"id":"1","name":"Epic"}'}, o));
      final result =
          await f.client.createProjectIssueType('PROJ', 'Epic', 'standard');
      expect(result['id'], '1');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/issuetype'));
      expect(jsonDecode(call.data as String),
          {'name': 'Epic', 'type': 'standard'});
    });

    test('includes description when provided', () async {
      final f = mockJira((o) => '{}');
      await f.client.createProjectIssueType(
          'PROJ', 'Epic', 'standard', 'A big work item');
      final decoded = jsonDecode(f.adapter.calls.single.data as String)
          as Map<String, dynamic>;
      expect(decoded['description'], 'A big work item');
    });
  });
}

/// `jira_setup_project_workflow` — POST `workflow` with project scope.
void setupProjectWorkflowTests() {
  group('JiraClient.setupProjectWorkflow', () {
    test('POSTs workflow with a project scope and the statuses payload',
        () async {
      final f = mockJira((o) => '{"name":"wf"}');
      final result = await f.client.setupProjectWorkflow('PROJ', {
        'statuses': [
          {'name': 'To Do'}
        ],
      });
      expect(result['name'], 'wf');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/workflow'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(decoded['scope'], {
        'type': 'project',
        'project': {'key': 'PROJ'},
      });
      expect(decoded['statuses'], [
        {'name': 'To Do'}
      ]);
    });
  });
}

/// `jira_sync_project_workflow` — copy workflow scheme across projects.
void syncProjectWorkflowTests() {
  group('JiraClient.syncProjectWorkflow', () {
    test('reads the source scheme and assigns it to the target', () async {
      final f = mockJira((o) => routeByPath({
            '/project/SRC/workflowScheme': _workflowSchemeBody,
          }, o));
      await f.client.syncProjectWorkflow('SRC', 'TGT');
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].method, 'GET');
      final put = f.adapter.calls[1];
      expect(put.method, 'PUT');
      expect(put.path, endsWith('/workflowscheme/10200/project'));
      expect(jsonDecode(put.data as String), {'projectId': 'TGT'});
    });

    test('does nothing when the source has no scheme id', () async {
      final f = mockJira((o) => '{}');
      await f.client.syncProjectWorkflow('SRC', 'TGT');
      expect(f.adapter.calls, hasLength(1));
      expect(f.adapter.calls.single.method, 'GET');
    });
  });
}

/// `jira_copy_project_structure` — copy components + versions.
void copyProjectStructureTests() {
  group('JiraClient.copyProjectStructure', () {
    test('recreates components and versions in the target', () async {
      final f = mockJira((o) => routeByPath({
            '/project/SRC/components': _componentsBody,
            '/project/SRC/versions': _versionsBody,
          }, o));
      await f.client.copyProjectStructure('SRC', 'TGT');
      expect(f.adapter.calls, hasLength(6));
      expect(f.adapter.calls[0].method, 'GET');
      expect(f.adapter.calls[1].method, 'POST');
      expect(f.adapter.calls[1].path, endsWith('/project/TGT/components'));
      expect(f.adapter.calls[3].method, 'GET');
      expect(f.adapter.calls[4].method, 'POST');
      expect(f.adapter.calls[4].path, endsWith('/project/TGT/versions'));
      final posted = jsonDecode(f.adapter.calls[1].data as String);
      expect(posted['name'], 'Backend');
    });
  });
}

/// `jira_clone_project` — create + copy structure + sync workflow.
void cloneProjectTests() {
  group('JiraClient.cloneProject', () {
    test('creates the target then copies structure and workflow', () async {
      final f = mockJira((o) => routeByPath({
            '/project/SRC': _projectDetailBody,
            '/project/SRC/components': '[]',
            '/project/SRC/versions': '[]',
            '/project/SRC/workflowScheme': _workflowSchemeBody,
          }, o, fallback: '{"key":"TGT"}'));
      final result =
          await f.client.cloneProject('SRC', 'TGT', 'Target Project');
      expect(result['key'], 'TGT');

      final create = f.adapter.calls[0];
      expect(create.method, 'GET');
      final post = f.adapter.calls[1];
      expect(post.method, 'POST');
      expect(post.path, endsWith('/project'));
      final decoded = jsonDecode(post.data as String) as Map<String, dynamic>;
      expect(decoded['key'], 'TGT');
      expect(decoded['name'], 'Target Project');
      expect(decoded['projectTypeKey'], 'software');
      expect(decoded.containsKey('leadAccountId'), isFalse);
      // + structure copy (2 GET) + workflow sync (GET + PUT)
      expect(f.adapter.calls, hasLength(6));
    });

    test('includes leadAccountId when lead is provided', () async {
      final f = mockJira((o) => routeByPath({
            '/project/SRC': _projectDetailBody,
            '/project/SRC/components': '[]',
            '/project/SRC/versions': '[]',
            '/project/SRC/workflowScheme': _workflowSchemeBody,
          }, o, fallback: '{}'));
      await f.client.cloneProject('SRC', 'TGT', 'Target', 'lead-1');
      final decoded =
          jsonDecode(f.adapter.calls[1].data as String) as Map<String, dynamic>;
      expect(decoded['leadAccountId'], 'lead-1');
    });
  });
}

/// [JiraToolExecutor.execute] routes the project delete and workflow-setup
/// tool names.
void projectAdminExecutorDispatchSetupTests() {
  group('JiraToolExecutor.execute (project admin)', () {
    test('routes jira_delete_project', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute(
          'jira_delete_project', {'key': 'PROJ', 'confirmDelete': true});
      expect(f.adapter.calls.single.method, 'DELETE');
      expect(f.adapter.calls.single.path, endsWith('/project/PROJ'));
    });

    test('routes jira_restore_project', () async {
      final f = mockJira((o) => '{"key":"PROJ","id":"10000","name":"P"}');
      await executor(f).execute('jira_restore_project', {'projectKey': 'PROJ'});
      expect(f.adapter.calls.single.method, 'POST');
      expect(f.adapter.calls.single.path, endsWith('/project/PROJ/restore'));
    });

    test('routes jira_setup_project_workflow', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_setup_project_workflow', {
        'target': 'TGT',
        'statusesJson': {'statuses': []},
      });
      expect(f.adapter.calls.single.method, 'POST');
      expect(f.adapter.calls.single.path, endsWith('/workflow'));
    });
  });
}

/// [JiraToolExecutor.execute] routes the project read tool names.
void projectAdminExecutorDispatchReadTests() {
  group('JiraToolExecutor.execute (project admin)', () {
    test('routes jira_get_project_board_config', () async {
      final f = mockJira(
          (o) => routeByPath({'/rest/agile/1.0/board': _boardListBody}, o));
      await executor(f)
          .execute('jira_get_project_board_config', {'project': 'PROJ'});
      expect(f.adapter.calls.last.path,
          endsWith('/rest/agile/1.0/board/42/configuration'));
    });

    test('routes jira_get_project_issue_type_scheme', () async {
      final f = mockJira((o) => '{}');
      await executor(f)
          .execute('jira_get_project_issue_type_scheme', {'project': 'PROJ'});
      expect(f.adapter.calls.single.path,
          endsWith('/project/PROJ/issueTypeScheme'));
    });
  });
}

/// [JiraToolExecutor.execute] routes the issue-type creation and project
/// clone tool names.
void projectAdminExecutorDispatchCreateTests() {
  group('JiraToolExecutor.execute (project admin)', () {
    test('routes jira_create_project_issue_type', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_create_project_issue_type', {
        'project': 'PROJ',
        'name': 'Epic',
        'type': 'standard',
        'description': 'Big',
      });
      expect(f.adapter.calls.single.method, 'POST');
      expect(f.adapter.calls.single.path, endsWith('/issuetype'));
    });

    test('routes jira_clone_project', () async {
      final f = mockJira((o) => routeByPath({
            '/project/SRC': _projectDetailBody,
            '/project/SRC/components': '[]',
            '/project/SRC/versions': '[]',
            '/project/SRC/workflowScheme': _workflowSchemeBody,
          }, o, fallback: '{}'));
      await executor(f).execute('jira_clone_project', {
        'source': 'SRC',
        'target': 'TGT',
        'targetName': 'Target',
        'lead': 'lead-1',
      });
      expect(
          f.adapter.calls
              .any((c) => c.method == 'POST' && c.path.endsWith('/project')),
          isTrue);
    });
  });
}

/// [JiraToolExecutor.execute] routes project scheme-assignment tool names.
void projectAdminExecutorDispatchSchemeTests() {
  group('JiraToolExecutor.execute (project schemes)', () {
    test('routes jira_assign_issue_type_scheme', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_assign_issue_type_scheme', {
        'projectId': '10000',
        'schemeId': '10100',
      });
      expect(f.adapter.calls.single.method, 'PUT');
      expect(f.adapter.calls.single.path,
          endsWith('/issuetypescheme/10100/project'));
    });

    test('routes jira_get_project_workflow_scheme', () async {
      final f = mockJira((o) => '{}');
      await executor(f)
          .execute('jira_get_project_workflow_scheme', {'project': 'PROJ'});
      expect(f.adapter.calls.single.path,
          endsWith('/project/PROJ/workflowScheme'));
    });

    test('routes jira_assign_workflow_scheme', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_assign_workflow_scheme', {
        'projectId': '10000',
        'schemeId': '10200',
      });
      expect(f.adapter.calls.single.method, 'PUT');
      expect(f.adapter.calls.single.path,
          endsWith('/workflowscheme/10200/project'));
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned Agile `board` listing body.
const _boardListBody = '{"values":[{"id":42,"name":"PROJ board"}]}';

/// Canned Agile `board/{id}/configuration` body.
const _boardConfigBody =
    '{"columnConfig":{"columns":[{"name":"To Do"},{"name":"Done"}]}}';

/// Canned issue-type scheme body.
const _schemeBody =
    '{"id":10100,"name":"Default Software Scheme","defaultIssueTypeId":"1"}';

/// Canned workflow-scheme body (id differs from the issue-type scheme).
const _workflowSchemeBody =
    '{"id":10200,"name":"Software Simplified Workflow"}';

/// Canned components body.
const _componentsBody =
    '[{"name":"Backend","description":"Server code"},{"name":"Frontend","description":"Web app"}]';

/// Canned versions body.
const _versionsBody =
    '[{"name":"1.0","description":"First"},{"name":"1.1","description":"Second"}]';

/// Canned `project/{key}` body for clone-source details.
const _projectDetailBody =
    '{"key":"SRC","name":"Source","projectTypeKey":"software","description":"src"}';
