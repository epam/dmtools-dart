import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Advanced-update tests: postCommentIfNotExists, updateFieldAsAdf,
/// getAllFieldsWithName, updateAllFieldsWithName, updateTicket
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  postCommentIfNotExistsTests();
  updateFieldAsAdfTests();
  getAllFieldsWithNameTests();
  updateAllFieldsWithNameTests();
  updateTicketTests();
  advancedUpdatesExecutorDispatchTests();
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

/// [JiraToolExecutor.execute] routes advanced-update tool names correctly.
void advancedUpdatesExecutorDispatchTests() {
  group('JiraToolExecutor.execute (advanced updates)', () {
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
}

/// Canned `issue/{key}/comment` body with one existing comment.
const _commentsWithBody =
    '{"comments":[{"id":"1","body":"hello"},{"id":"2","body":"world"}]}';

/// Canned `field` body — two fields, only one matching "Story Points".
const _fieldsListBody =
    '[{"id":"summary","name":"Summary"},{"id":"customfield_10001","name":"Story Points"}]';
