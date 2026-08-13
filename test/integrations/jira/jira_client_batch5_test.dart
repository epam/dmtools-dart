import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Batch-5 tests: moveToStatusWithResolution, getAccountByEmail,
/// getUserProfile, getMyProfile, attachFileToTicket, downloadAttachment,
/// deleteProject, addFixVersion, removeFixVersion, getProjectBoardConfig,
/// scheme assignment tools, createProjectIssueType, setupProjectWorkflow,
/// syncProjectWorkflow, copyProjectStructure, cloneProject
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  moveToStatusWithResolutionTests();
  getAccountByEmailTests();
  getUserProfileTests();
  getMyProfileTests();
  attachFileToTicketTests();
  downloadAttachmentTests();
  deleteProjectTests();
  fixVersionMutationTests();
  getProjectBoardConfigTests();
  issueTypeSchemeTests();
  workflowSchemeTests();
  createProjectIssueTypeTests();
  setupProjectWorkflowTests();
  syncProjectWorkflowTests();
  copyProjectStructureTests();
  cloneProjectTests();
  batch5ExecutorDispatchTests();
  batch5ExecutorDispatchProjectTests();
  batch5ExecutorDispatchSchemeTests();
  batch5ExecutorDispatchExtraTests();
}

/// `jira_move_to_status_with_resolution` — transition + resolution body.
void moveToStatusWithResolutionTests() {
  group('JiraClient.moveToStatusWithResolution', () {
    test('POSTs transition with resolution in fields', () async {
      final f = mockJira((o) => routeByPath({
            '/issue/PROJ-1/transitions': _transitionsBody,
          }, o));
      await f.client.moveToStatusWithResolution('PROJ-1', 'Done', 'Fixed');
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].method, 'GET');
      final post = f.adapter.calls[1];
      expect(post.method, 'POST');
      final decoded = jsonDecode(post.data as String) as Map<String, dynamic>;
      expect(decoded['transition'], {'id': '31'});
      expect(decoded['fields'], {
        'resolution': {'name': 'Fixed'}
      });
    });

    test('returns explanation when no transition matches', () async {
      final f = mockJira((o) => '{"transitions":[]}');
      final result = await f.client
          .moveToStatusWithResolution('PROJ-1', 'Nonexistent', 'Fixed');
      expect(result, 'No transition found for status: Nonexistent');
      expect(f.adapter.calls.single.method, 'GET');
    });
  });
}

/// `jira_get_account_by_email` — GET `user/search?username=`.
void getAccountByEmailTests() {
  group('JiraClient.getAccountByEmail', () {
    test('returns the first matching user', () async {
      final f =
          mockJira((o) => routeByPath({'/user/search': _usersListBody}, o));
      final result = await f.client.getAccountByEmail('dev@example.com');
      expect(result['accountId'], '5b10a2844c20165700ede21g');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.queryParameters['username'],
          'dev@example.com');
    });

    test('returns an empty map when no users match', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getAccountByEmail('nobody@example.com'), isEmpty);
    });
  });
}

/// `jira_get_user_profile` — GET `user?accountId=`.
void getUserProfileTests() {
  group('JiraClient.getUserProfile', () {
    test('GETs user by accountId', () async {
      final f = mockJira((o) => routeByPath({'/user': _userBody}, o));
      final result = await f.client.getUserProfile('abc-123');
      expect(result['accountId'], 'abc-123');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.queryParameters['accountId'], 'abc-123');
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getUserProfile('abc-123'), isEmpty);
    });
  });
}

/// `jira_get_my_profile` — GET `myself`.
void getMyProfileTests() {
  group('JiraClient.getMyProfile', () {
    test('GETs the myself endpoint', () async {
      final f = mockJira((o) => routeByPath({'/myself': _userBody}, o));
      final result = await f.client.getMyProfile();
      expect(result['accountId'], 'abc-123');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, endsWith('/myself'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getMyProfile(), isEmpty);
    });
  });
}

/// `jira_attach_file_to_ticket` — POST multipart `issue/{key}/attachments`.
void attachFileToTicketTests() {
  group('JiraClient.attachFileToTicket', () {
    test('uploads a local file as multipart POST', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/dmtools_test_attach_${DateTime.now().millisecondsSinceEpoch}.txt');
      tmp.writeAsStringSync('attachment payload');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final f = mockJira((o) => '[]');
      final result =
          await f.client.attachFileToTicket('PROJ-1', 'notes.txt', tmp.path);

      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, contains('/rest/api/latest/issue/PROJ-1/attachments'));
      expect(call.headers['X-Atlassian-Token'], 'nocheck');
      expect(result, isEmpty);
    });
  });
}

/// `jira_download_attachment` — GET binary and write to local file.
void downloadAttachmentTests() {
  group('JiraClient.downloadAttachment', () {
    test('downloads bytes and writes them to filePath', () async {
      const url = 'https://jira.example.com/secure/attachment/10001/file.txt';
      final target = File(
          '${Directory.systemTemp.path}/dmtools_test_dl_${DateTime.now().millisecondsSinceEpoch}.bin');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync();
      });

      final f = mockJira((o) => 'downloaded bytes');
      await f.client.downloadAttachment(url, target.path);

      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, url);
      expect(target.existsSync(), isTrue);
      expect(target.readAsStringSync(), 'downloaded bytes');
    });
  });
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

/// `jira_add_fix_version` / `jira_remove_fix_version` — update.fixVersions.
void fixVersionMutationTests() {
  group('JiraClient.addFixVersion', () {
    test('PUTs an add operation on fixVersions', () async {
      final f = mockJira((o) => '{}');
      await f.client.addFixVersion('PROJ-1', '2.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issue/PROJ-1'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(decoded['update'], {
        'fixVersions': [
          {
            'add': {'name': '2.0'}
          }
        ]
      });
    });
  });

  group('JiraClient.removeFixVersion', () {
    test('PUTs a remove operation on fixVersions', () async {
      final f = mockJira((o) => '{}');
      await f.client.removeFixVersion('PROJ-1', '2.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(decoded['update'], {
        'fixVersions': [
          {
            'remove': {'name': '2.0'}
          }
        ]
      });
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

/// [JiraToolExecutor.execute] routes batch-5 ticket-level tool names.
void batch5ExecutorDispatchTests() {
  group('JiraToolExecutor.execute (batch-5)', () {
    test('routes jira_move_to_status_with_resolution', () async {
      final f = mockJira((o) =>
          routeByPath({'/issue/PROJ-1/transitions': _transitionsBody}, o));
      await executor(f).execute('jira_move_to_status_with_resolution', {
        'key': 'PROJ-1',
        'status': 'Done',
        'resolution': 'Fixed',
      });
      expect(f.adapter.calls.last.method, 'POST');
      final decoded = jsonDecode(f.adapter.calls.last.data as String)
          as Map<String, dynamic>;
      expect(decoded['fields'], {
        'resolution': {'name': 'Fixed'}
      });
    });

    test('routes jira_get_account_by_email', () async {
      final f =
          mockJira((o) => routeByPath({'/user/search': _usersListBody}, o));
      await executor(f)
          .execute('jira_get_account_by_email', {'email': 'dev@example.com'});
      expect(f.adapter.calls.single.queryParameters['username'],
          'dev@example.com');
    });

    test('routes jira_get_user_profile', () async {
      final f = mockJira((o) => routeByPath({'/user': _userBody}, o));
      await executor(f).execute('jira_get_user_profile', {'userId': 'abc-123'});
      expect(f.adapter.calls.single.queryParameters['accountId'], 'abc-123');
    });

    test('routes jira_attach_file_to_ticket', () async {
      final tmp = _tempFile('exec');
      final f = mockJira((o) => '[]');
      await executor(f).execute('jira_attach_file_to_ticket', {
        'key': 'PROJ-1',
        'fileName': 'notes.txt',
        'filePath': tmp.path,
      });
      expect(f.adapter.calls.single.method, 'POST');
      expect(
          f.adapter.calls.single.path, contains('/issue/PROJ-1/attachments'));
    });

    test('routes jira_add_fix_version', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_add_fix_version', {
        'key': 'PROJ-1',
        'version': '2.0',
      });
      expect(f.adapter.calls.single.method, 'PUT');
      expect(f.adapter.calls.single.path, endsWith('/issue/PROJ-1'));
    });
  });
}

/// [JiraToolExecutor.execute] routes batch-5 project-level tool names.
void batch5ExecutorDispatchProjectTests() {
  group('JiraToolExecutor.execute (batch-5 project)', () {
    test('routes jira_delete_project', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute(
          'jira_delete_project', {'key': 'PROJ', 'confirmDelete': true});
      expect(f.adapter.calls.single.method, 'DELETE');
      expect(f.adapter.calls.single.path, endsWith('/project/PROJ'));
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

/// [JiraToolExecutor.execute] routes batch-5 scheme assignment tool names.
void batch5ExecutorDispatchSchemeTests() {
  group('JiraToolExecutor.execute (batch-5 schemes)', () {
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

/// [JiraToolExecutor.execute] routes remaining batch-5 tool names.
void batch5ExecutorDispatchExtraTests() {
  group('JiraToolExecutor.execute (batch-5 extras)', () {
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

    test('routes jira_remove_fix_version', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_remove_fix_version', {
        'key': 'PROJ-1',
        'version': '2.0',
      });
      expect(f.adapter.calls.single.method, 'PUT');
      expect(f.adapter.calls.single.path, endsWith('/issue/PROJ-1'));
    });

    test('routes jira_get_my_profile', () async {
      final f = mockJira((o) => routeByPath({'/myself': _userBody}, o));
      await executor(f).execute('jira_get_my_profile', {});
      expect(f.adapter.calls.single.path, endsWith('/myself'));
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

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Creates a temporary file with content for attachment tests.
File _tempFile(String prefix) {
  final f = File(
      '${Directory.systemTemp.path}/dmtools_$prefix${DateTime.now().millisecondsSinceEpoch}.txt');
  f.writeAsStringSync('x');
  addTearDown(() {
    if (f.existsSync()) f.deleteSync();
  });
  return f;
}

/// Canned `issue/{key}/transitions` body with one "Done" transition.
const _transitionsBody =
    '{"transitions":[{"id":"31","name":"Done","to":{"name":"Done"}}]}';

/// Canned `user/search` body with one user.
const _usersListBody =
    '[{"accountId":"5b10a2844c20165700ede21g","emailAddress":"dev@example.com"}]';

/// Canned `user` / `myself` body.
const _userBody =
    '{"accountId":"abc-123","displayName":"Dev User","emailAddress":"dev@example.com"}';

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
