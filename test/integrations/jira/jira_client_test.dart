import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Coverage + behavior tests for [JiraClient] and [JiraHttpClient].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getTicketTests();
  searchByJqlTests();
  postCommentTests();
  labelTests();
  moveToStatusTests();
}

/// The expected `Authorization` value produced by the fixture's config.
String get _expectedAuth =>
    'Basic ${base64Encode(utf8.encode('dev@example.com:tok-123'))}';

/// [JiraHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('JiraHttpClient', () {
    test('builds /rest/api/latest and /rest/api/3 URLs', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.buildUrl('myself'),
          'https://jira.example.com/rest/api/latest/myself');
      expect(f.http.buildV3Url('issue/PROJ-1'),
          'https://jira.example.com/rest/api/3/issue/PROJ-1');
    });

    test('assembles Authorization and CSRF headers', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.headers['Authorization'], _expectedAuth);
      expect(f.http.headers['X-Atlassian-Token'], 'nocheck');
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/getV3/post/put/delete return the response bodies', () async {
      final f = mockHttp((o) => routeByPath({
            '/latest/get': 'GET-LATEST',
            '/3/get': 'GET-V3',
            '/latest/post': 'POST-BODY',
            '/latest/put': 'PUT-BODY',
            '/latest/del': 'DELETE-BODY',
          }, o));
      expect(await f.http.get('get'), 'GET-LATEST');
      expect(await f.http.getV3('get'), 'GET-V3');
      expect(await f.http.post('post'), 'POST-BODY');
      expect(await f.http.put('put'), 'PUT-BODY');
      expect(await f.http.delete('del'), 'DELETE-BODY');
      f.http.close();
    });

    test('throws StateError when JIRA_BASE_PATH is missing', () {
      PropertyReader.clearOverrides();
      expect(() => JiraHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when auth credentials are missing', () {
      PropertyReader.setOverrides(
          {'JIRA_BASE_PATH': 'https://jira.example.com'});
      expect(() => JiraHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `jira_test` — connectivity check via GET `/myself`.
void testConnectionTests() {
  group('JiraClient.testConnection', () {
    test('returns success with the user profile', () async {
      final f = mockJira((o) => routeByPath({'/myself': _myselfBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Jira connection successful');
      expect(result['user'], 'Dev User');
      expect(result['email'], 'dev@example.com');
      expect(f.adapter.calls.single.path, endsWith('/myself'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockJira((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `jira_get_ticket` — GET `/issue/{key}`.
void getTicketTests() {
  group('JiraClient.getTicket', () {
    test('returns the decoded ticket map', () async {
      final f = mockJira((o) => routeByPath({'/issue/PROJ-1': _ticketBody}, o));
      final ticket = await f.client.getTicket('PROJ-1');
      expect(ticket?['key'], 'PROJ-1');
      expect(f.adapter.calls.single.queryParameters['fields'], '*navigable');
    });

    test('passes requested fields through', () async {
      final f = mockJira((o) => routeByPath({'/issue/PROJ-1': _ticketBody}, o));
      await f.client.getTicket('PROJ-1', ['summary', 'status']);
      expect(
          f.adapter.calls.single.queryParameters['fields'], 'summary,status');
    });

    test('returns null when the body is not an object', () async {
      final f = mockJira((o) => routeByPath({'/issue/PROJ-1': '[1, 2]'}, o));
      expect(await f.client.getTicket('PROJ-1'), isNull);
    });
  });
}

/// `jira_search_by_jql` — cursor pagination + Server fallback.
void searchByJqlTests() {
  group('JiraClient.searchByJql', () {
    test('paginates the Cloud cursor endpoint', () async {
      final f =
          mockJira((o) => _cursorPage(o.queryParameters['nextPageToken']));
      final issues = await f.client.searchByJql('project = X');
      expect(issues.map((i) => i['key']).toList(), ['P-1', 'P-2', 'P-3']);
    });

    test('falls back to Server offset search when cursor is empty', () async {
      final f = mockJira((o) => routeByPath({
            '/search/jql': '{"issues": []}',
            '/search': _serverPage,
          }, o));
      final issues = await f.client.searchByJql('project = X');
      expect(issues, hasLength(1));
      expect(issues.single['key'], 'S-1');
    });
  });
}

/// `jira_post_comment` — POST `/issue/{key}/comment`.
void postCommentTests() {
  group('JiraClient.postComment', () {
    test('POSTs the comment body', () async {
      final f = mockJira((o) => '{}');
      await f.client.postComment('PROJ-1', 'hello world');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/issue/PROJ-1/comment'));
      expect(jsonDecode(call.data as String), {'body': 'hello world'});
    });
  });
}

/// `jira_add_label` / `jira_remove_label`.
void labelTests() {
  group('JiraClient.addLabel', () {
    test('adds a missing label via PUT', () async {
      final f = mockJira((o) => _labelRouter(o, existing: ['a']));
      await f.client.addLabel('PROJ-1', 'b');
      final put = f.adapter.calls.lastWhere((c) => c.method == 'PUT');
      expect(put.path, endsWith('/issue/PROJ-1'));
      expect(_labelsFromPut(put.data as String), {'a', 'b'});
    });

    test('is a no-op when the label already exists', () async {
      final f = mockJira((o) => _labelRouter(o, existing: ['a', 'b']));
      await f.client.addLabel('PROJ-1', 'b');
      expect(f.adapter.calls.where((c) => c.method == 'PUT'), isEmpty);
    });
  });

  group('JiraClient.removeLabel', () {
    test('removes a present label via PUT', () async {
      final f = mockJira((o) => _labelRouter(o, existing: ['a', 'b']));
      await f.client.removeLabel('PROJ-1', 'b');
      final put = f.adapter.calls.lastWhere((c) => c.method == 'PUT');
      expect(_labelsFromPut(put.data as String), {'a'});
    });
  });
}

/// `jira_move_to_status` — transition matching by name or destination status.
void moveToStatusTests() {
  group('JiraClient.moveToStatus', () {
    test('matches by transition name and posts', () async {
      final f = mockJira((o) => _transitionRouter(o));
      final result = await f.client.moveToStatus('PROJ-1', 'Done');
      expect(result, 'transitioned');
      final post = f.adapter.calls.lastWhere((c) => c.method == 'POST');
      expect(jsonDecode(post.data as String), {
        'transition': {'id': '31'}
      });
    });

    test('matches by destination status name', () async {
      final f = mockJira((o) => _transitionRouter(o));
      expect(await f.client.moveToStatus('PROJ-1', 'Closed'), 'transitioned');
    });

    test('returns an explanatory string when nothing matches', () async {
      final f = mockJira((o) => _transitionRouter(o));
      expect(await f.client.moveToStatus('PROJ-1', 'Nope'),
          'No transition found for status: Nope');
      expect(f.adapter.calls.where((c) => c.method == 'POST'), isEmpty);
    });
  });
}

/// Canned `/myself` response body.
const _myselfBody =
    '{"displayName":"Dev User","emailAddress":"dev@example.com"}';

/// Canned `/issue/{key}` response body.
const _ticketBody = '{"key":"PROJ-1","fields":{"summary":"Sample"}}';

/// Canned Server `/search` page (single issue, total = 1).
const _serverPage = '{"issues":[{"key":"S-1"}],"total":1}';

/// Returns the next Cloud cursor page given a [token].
String _cursorPage(String? token) {
  if (token == null) {
    return '{"issues":[{"key":"P-1"}],"nextPageToken":"t1"}';
  }
  if (token == 't1') {
    return '{"issues":[{"key":"P-2"}],"nextPageToken":"t2"}';
  }
  return '{"issues":[{"key":"P-3"}]}';
}

/// Serves label GET/PUT traffic for [key] starting from [existing].
String _labelRouter(RequestOptions o, {required List<String> existing}) {
  if (o.method == 'GET' && o.path.endsWith('/issue/PROJ-1')) {
    return '{"key":"PROJ-1","fields":{"labels":${jsonEncode(existing)}}}';
  }
  return '{}';
}

/// Extracts the `set` labels array from a PUT labels body.
Set<String> _labelsFromPut(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final update = decoded['update'] as Map<String, dynamic>;
  final labelsList = update['labels'] as List;
  final setOp = labelsList.single as Map<String, dynamic>;
  return (setOp['set'] as List).cast<String>().toSet();
}

/// Serves transitions GET (list) and POST (ack) traffic.
String _transitionRouter(RequestOptions o) {
  if (o.method == 'GET' && o.path.endsWith('/transitions')) {
    return '{"transitions":${jsonEncode([
          {
            'id': '11',
            'name': 'To Do',
            'to': {'name': 'Open'}
          },
          {
            'id': '31',
            'name': 'Done',
            'to': {'name': 'Closed'}
          }
        ])}}';
  }
  return 'transitioned';
}
