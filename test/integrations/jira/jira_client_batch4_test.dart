import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Batch-4 tests: postCommentIfNotExists, updateFieldAsAdf,
/// getAllFieldsWithName, updateAllFieldsWithName, updateTicket, linkIssues,
/// getIssueLinkTypes, executeRequest, getProjectDetails, getProjectStatuses
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  postCommentIfNotExistsTests();
  updateFieldAsAdfTests();
  getAllFieldsWithNameTests();
  updateAllFieldsWithNameTests();
  updateTicketTests();
  linkIssuesTests();
  getIssueLinkTypesTests();
  executeRequestTests();
  getProjectDetailsTests();
  getProjectStatusesTests();
  batch4ExecutorDispatchTests();
  batch4ExecutorDispatchExtraTests();
}

/// `jira_post_comment_if_not_exists` — POST only when comment is absent.
void postCommentIfNotExistsTests() {
  group('JiraClient.postCommentIfNotExists', () {
    test('returns false and skips POST when comment already exists', () async {
      final f = mockJira(
          (o) => routeByPath({'/issue/PROJ-1/comment': _commentsWithBody}, o));
      final posted = await f.client.postCommentIfNotExists('PROJ-1', 'hello');
      expect(posted, isFalse);
      expect(f.adapter.calls, hasLength(1));
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns true and POSTs when comment is absent', () async {
      var firstCall = true;
      final f = mockJira((o) {
        if (firstCall && o.path.contains('/comment')) {
          firstCall = false;
          return '{"comments":[]}';
        }
        return '{}';
      });
      final posted =
          await f.client.postCommentIfNotExists('PROJ-1', 'new text');
      expect(posted, isTrue);
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].method, 'GET');
      expect(f.adapter.calls[1].method, 'POST');
    });
  });
}

/// `jira_update_field_as_adf` — PUT via v3 endpoint with ADF document.
void updateFieldAsAdfTests() {
  group('JiraClient.updateFieldAsAdf', () {
    test('PUTs to the v3 endpoint with ADF in fields', () async {
      final f = mockJira((o) => '{}');
      const adf = {
        'type': 'doc',
        'version': 1,
        'content': <Map<String, dynamic>>[]
      };
      await f.client.updateFieldAsAdf('PROJ-1', 'description', adf);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, contains('/rest/api/3/issue/PROJ-1'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      final fields = decoded['fields'] as Map<String, dynamic>;
      expect(fields['description'], adf);
    });
  });
}

/// `jira_get_all_fields_with_name` — GET `field`, filter by display name.
void getAllFieldsWithNameTests() {
  group('JiraClient.getAllFieldsWithName', () {
    test('returns only fields whose name matches', () async {
      final f = mockJira((o) => routeByPath({'/field': _fieldsListBody}, o));
      final result =
          await f.client.getAllFieldsWithName('PROJ', 'Story Points');
      expect(result, hasLength(1));
      expect(result[0]['id'], 'customfield_10001');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when nothing matches', () async {
      final f = mockJira((o) => routeByPath({'/field': _fieldsListBody}, o));
      expect(
        await f.client.getAllFieldsWithName('PROJ', 'Nonexistent'),
        isEmpty,
      );
    });
  });
}

/// `jira_update_all_fields_with_name` — update every field matching a name.
void updateAllFieldsWithNameTests() {
  group('JiraClient.updateAllFieldsWithName', () {
    test('PUTs all field ids matching the name', () async {
      final f = mockJira(
          (o) => routeByPath({'/field': _fieldsListBody}, o, fallback: '{}'));
      await f.client.updateAllFieldsWithName('PROJ-1', 'Story Points', 5);
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].method, 'GET');
      final put = f.adapter.calls[1];
      expect(put.method, 'PUT');
      expect(put.path, endsWith('/issue/PROJ-1'));
      final decoded = jsonDecode(put.data as String) as Map<String, dynamic>;
      final fields = decoded['fields'] as Map<String, dynamic>;
      expect(fields, {'customfield_10001': 5});
    });

    test('does nothing when no fields match', () async {
      final f = mockJira(
          (o) => routeByPath({'/field': _fieldsListBody}, o, fallback: '{}'));
      await f.client.updateAllFieldsWithName('PROJ-1', 'Nonexistent', 5);
      expect(f.adapter.calls, hasLength(1));
      expect(f.adapter.calls.single.method, 'GET');
    });
  });
}

/// `jira_update_ticket` — PUT `issue/{key}` with raw JSON body.
void updateTicketTests() {
  group('JiraClient.updateTicket', () {
    test('PUTs the raw JSON body verbatim', () async {
      final f = mockJira((o) => '{}');
      await f.client.updateTicket('PROJ-1', {
        'fields': {'summary': 'Updated'},
        'update': {
          'labels': [
            {'add': 'x'}
          ]
        },
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issue/PROJ-1'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(decoded['fields'], {'summary': 'Updated'});
      expect(decoded.containsKey('update'), isTrue);
    });
  });
}

/// `jira_link_issues` — POST `issue/link`.
void linkIssuesTests() {
  group('JiraClient.linkIssues', () {
    test('POSTs to issue/link with correct body', () async {
      final f = mockJira((o) => '{}');
      await f.client.linkIssues('Blocks', 'PROJ-1', 'PROJ-2');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/issue/link'));
      expect(jsonDecode(call.data as String), {
        'type': {'name': 'Blocks'},
        'inwardIssue': {'key': 'PROJ-1'},
        'outwardIssue': {'key': 'PROJ-2'},
      });
    });
  });
}

/// `jira_get_issue_link_types` — GET `issue/link/type`.
void getIssueLinkTypesTests() {
  group('JiraClient.getIssueLinkTypes', () {
    test('returns the issueLinkTypes array', () async {
      final f =
          mockJira((o) => routeByPath({'/issue/link/type': _linkTypesBody}, o));
      final result = await f.client.getIssueLinkTypes();
      expect(result, hasLength(2));
      expect(result[0]['name'], 'Blocks');
      expect(result[1]['name'], 'Relates');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when issueLinkTypes is absent', () async {
      final f = mockJira((o) => '{}');
      expect(await f.client.getIssueLinkTypes(), isEmpty);
    });
  });
}

/// `jira_execute_request` — GET any Jira REST path.
void executeRequestTests() {
  group('JiraClient.executeRequest', () {
    test('GETs the given path and returns the decoded map', () async {
      final f = mockJira(
          (o) => routeByPath({'/serverInfo': '{"version":"10.0"}'}, o));
      final result = await f.client.executeRequest('serverInfo');
      expect(result['version'], '10.0');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, endsWith('/serverInfo'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.executeRequest('serverInfo'), isEmpty);
    });
  });
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

/// [JiraToolExecutor.execute] routes batch-4 tool names correctly.
void batch4ExecutorDispatchTests() {
  group('JiraToolExecutor.execute (batch-4)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_post_comment_if_not_exists', () async {
      await executor.execute('jira_post_comment_if_not_exists', {
        'key': 'PROJ-1',
        'comment': 'hi',
      });
      expect(spy.calls, ['postCommentIfNotExists:PROJ-1:hi']);
    });

    test('routes jira_update_field_as_adf', () async {
      await executor.execute('jira_update_field_as_adf', {
        'key': 'PROJ-1',
        'field': 'description',
        'value': {'type': 'doc'},
      });
      expect(spy.calls, ['updateFieldAsAdf:PROJ-1:description']);
    });

    test('routes jira_get_all_fields_with_name', () async {
      await executor.execute('jira_get_all_fields_with_name', {
        'project': 'PROJ',
        'fieldName': 'Story Points',
      });
      expect(spy.calls, ['getAllFieldsWithName:PROJ:Story Points']);
    });

    test('routes jira_update_all_fields_with_name', () async {
      await executor.execute('jira_update_all_fields_with_name', {
        'key': 'PROJ-1',
        'fieldName': 'Story Points',
        'value': 5,
      });
      expect(spy.calls, ['updateAllFieldsWithName:PROJ-1:Story Points']);
    });

    test('routes jira_update_ticket', () async {
      await executor.execute('jira_update_ticket', {
        'key': 'PROJ-1',
        'jsonParams': {'fields': {}},
      });
      expect(spy.calls, ['updateTicket:PROJ-1']);
    });
  });
}

/// [JiraToolExecutor.execute] routes the remaining batch-4 tool names
/// (issue links, ad-hoc requests, and project lookups) to the client.
void batch4ExecutorDispatchExtraTests() {
  group('JiraToolExecutor.execute (batch-4 extras)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_link_issues', () async {
      await executor.execute('jira_link_issues', {
        'linkType': 'Blocks',
        'inwardKey': 'PROJ-1',
        'outwardKey': 'PROJ-2',
      });
      expect(spy.calls, ['linkIssues:Blocks:PROJ-1:PROJ-2']);
    });

    test('routes jira_get_issue_link_types', () async {
      await executor.execute('jira_get_issue_link_types', {});
      expect(spy.calls, ['getIssueLinkTypes']);
    });

    test('routes jira_execute_request', () async {
      await executor.execute('jira_execute_request', {'url': 'serverInfo'});
      expect(spy.calls, ['executeRequest:serverInfo']);
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
  Future<bool> postCommentIfNotExists(String key, String comment) {
    calls.add('postCommentIfNotExists:$key:$comment');
    return super.postCommentIfNotExists(key, comment);
  }

  @override
  Future<void> updateFieldAsAdf(
    String key,
    String field,
    Map<String, dynamic> value,
  ) {
    calls.add('updateFieldAsAdf:$key:$field');
    return super.updateFieldAsAdf(key, field, value);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllFieldsWithName(
    String project,
    String fieldName,
  ) {
    calls.add('getAllFieldsWithName:$project:$fieldName');
    return super.getAllFieldsWithName(project, fieldName);
  }

  @override
  Future<void> updateAllFieldsWithName(
    String key,
    String fieldName,
    Object value,
  ) {
    calls.add('updateAllFieldsWithName:$key:$fieldName');
    return super.updateAllFieldsWithName(key, fieldName, value);
  }

  @override
  Future<void> updateTicket(String key, Map<String, dynamic> jsonParams) {
    calls.add('updateTicket:$key');
    return super.updateTicket(key, jsonParams);
  }

  @override
  Future<void> linkIssues(
    String linkType,
    String inwardKey,
    String outwardKey,
  ) {
    calls.add('linkIssues:$linkType:$inwardKey:$outwardKey');
    return super.linkIssues(linkType, inwardKey, outwardKey);
  }

  @override
  Future<List<Map<String, dynamic>>> getIssueLinkTypes() {
    calls.add('getIssueLinkTypes');
    return super.getIssueLinkTypes();
  }

  @override
  Future<Map<String, dynamic>> executeRequest(String url) {
    calls.add('executeRequest:$url');
    return super.executeRequest(url);
  }

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

/// Canned `issue/{key}/comment` body with one existing comment.
const _commentsWithBody =
    '{"comments":[{"id":"1","body":"hello"},{"id":"2","body":"world"}]}';

/// Canned `field` body — two fields, only one matching "Story Points".
const _fieldsListBody =
    '[{"id":"summary","name":"Summary"},{"id":"customfield_10001","name":"Story Points"}]';

/// Canned `issue/link/type` body.
const _linkTypesBody =
    '{"issueLinkTypes":[{"id":"1","name":"Blocks"},{"id":"2","name":"Relates"}]}';

/// Canned `project/{key}` body.
const _projectBody =
    '{"key":"PROJ","name":"Project X","id":"10000","style":"classic"}';

/// Canned `project/{project}/statuses` body.
const _statusesBody =
    '[{"id":"1","name":"To Do"},{"id":"2","name":"In Progress"}]';
