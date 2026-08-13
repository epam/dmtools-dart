import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Coverage + behavior tests for [GitlabClient] and [GitlabHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getMrTests();
  listMrsTests();
  createMrNoteTests();
  getIssueTests();
}

/// The expected `PRIVATE-TOKEN` value produced by the fixture's config.
const _expectedToken = 'glpat-123';

/// [GitlabHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('GitlabHttpClient', () {
    test('builds /api/v4 URLs', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.buildUrl('user'), 'https://gitlab.example.com/api/v4/user');
    });

    test('assembles PRIVATE-TOKEN and Content-Type headers', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.headers['PRIVATE-TOKEN'], _expectedToken);
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/post/put/delete return the response bodies', () async {
      final f = mockHttp((o) => routeByPath({
            '/v4/get': 'GET-BODY',
            '/v4/post': 'POST-BODY',
            '/v4/put': 'PUT-BODY',
            '/v4/del': 'DELETE-BODY',
          }, o));
      expect(await f.http.get('get'), 'GET-BODY');
      expect(await f.http.post('post'), 'POST-BODY');
      expect(await f.http.put('put'), 'PUT-BODY');
      expect(await f.http.delete('del'), 'DELETE-BODY');
      f.http.close();
    });

    test('throws StateError when GITLAB_BASE_PATH is missing', () {
      PropertyReader.clearOverrides();
      expect(() => GitlabHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when GITLAB_TOKEN is missing', () {
      PropertyReader.setOverrides(
          {'GITLAB_BASE_PATH': 'https://gitlab.example.com'});
      expect(() => GitlabHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `gitlab_test` — connectivity check via GET `/api/v4/user`.
void testConnectionTests() {
  group('GitlabClient.testConnection', () {
    test('returns success with the user profile', () async {
      final f = mockGitlab((o) => routeByPath({'/user': _userBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'GitLab connection successful');
      expect(result['user'], 'Dev User');
      expect(result['email'], 'dev@example.com');
      expect(f.adapter.calls.single.path, endsWith('/api/v4/user'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockGitlab((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `gitlab_get_mr` — GET `/projects/{id}/merge_requests/{iid}`.
void getMrTests() {
  group('GitlabClient.getMr', () {
    test('returns the decoded merge request map', () async {
      final f =
          mockGitlab((o) => routeByPath({'/merge_requests/42': _mrBody}, o));
      final mr = await f.client.getMr('group/proj', 42);
      expect(mr?['iid'], 42);
      expect(mr?['title'], 'Sample MR');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/group%2Fproj/merge_requests/42'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f =
          mockGitlab((o) => routeByPath({'/merge_requests/1': '[1, 2]'}, o));
      expect(await f.client.getMr('1', 1), isNull);
    });
  });
}

/// `gitlab_list_mrs` — GET `/projects/{id}/merge_requests?state=...`.
void listMrsTests() {
  group('GitlabClient.listMrs', () {
    test('returns the decoded list', () async {
      final f =
          mockGitlab((o) => routeByPath({'/merge_requests': _mrListBody}, o));
      final mrs = await f.client.listMrs('1');
      expect(mrs.map((m) => m['iid']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/api/v4/projects/1/merge_requests'));
      expect(call.queryParameters['state'], 'opened');
      expect(call.queryParameters['per_page'], 20);
    });

    test('passes a custom state filter', () async {
      final f = mockGitlab((o) => routeByPath({'/merge_requests': '[]'}, o));
      await f.client.listMrs('1', 'merged');
      expect(f.adapter.calls.single.queryParameters['state'], 'merged');
    });

    test('returns empty list when body is not a JSON array', () async {
      final f = mockGitlab((o) => routeByPath({'/merge_requests': '{}'}, o));
      expect(await f.client.listMrs('1'), isEmpty);
    });
  });
}

/// `gitlab_create_mr_note` — POST `/projects/{id}/merge_requests/{iid}/notes`.
void createMrNoteTests() {
  group('GitlabClient.createMrNote', () {
    test('POSTs the note body and returns the created note', () async {
      final f = mockGitlab((o) => routeByPath({'/notes': _noteBody}, o));
      final note = await f.client.createMrNote('1', 42, 'hello world');
      expect(note?['body'], 'hello world');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/merge_requests/42/notes'));
      expect(jsonDecode(call.data as String), {'body': 'hello world'});
    });

    test('returns null when the response is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/notes': '[]'}, o));
      expect(await f.client.createMrNote('1', 42, 'x'), isNull);
    });
  });
}

/// `gitlab_get_issue` — GET `/projects/{id}/issues/{iid}`.
void getIssueTests() {
  group('GitlabClient.getIssue', () {
    test('returns the decoded issue map', () async {
      final f = mockGitlab((o) => routeByPath({'/issues/7': _issueBody}, o));
      final issue = await f.client.getIssue('1', 7);
      expect(issue?['iid'], 7);
      expect(issue?['title'], 'Sample issue');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/issues/7'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/issues/7': '[1]'}, o));
      expect(await f.client.getIssue('1', 7), isNull);
    });
  });
}

/// Canned `/api/v4/user` response body.
const _userBody =
    '{"name":"Dev User","username":"devuser","email":"dev@example.com"}';

/// Canned merge-request response body.
const _mrBody = '{"iid":42,"title":"Sample MR"}';

/// Canned merge-request list response body.
const _mrListBody = '[{"iid":1,"title":"MR 1"},{"iid":2,"title":"MR 2"}]';

/// Canned note response body.
const _noteBody = '{"id":99,"body":"hello world"}';

/// Canned issue response body.
const _issueBody = '{"iid":7,"title":"Sample issue"}';
