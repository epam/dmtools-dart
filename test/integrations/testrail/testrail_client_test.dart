import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'testrail_test_support.dart';

/// Coverage + behavior tests for [TestRailClient] and [TestRailHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getCaseTests();
  getCasesTests();
  addResultTests();
}

/// The expected `Authorization` value produced by the fixture's config.
String get _expectedAuth =>
    'Basic ${base64Encode(utf8.encode('dev@example.com:key-123'))}';

/// [TestRailHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('TestRailHttpClient', () {
    test('builds index.php?/api/v2/ URLs', () {
      final f = mockTestRailHttp((o) => '{}');
      expect(
        f.http.buildUrl('get_case/1'),
        'https://tr.example.com/index.php?/api/v2/get_case/1',
      );
    });

    test('assembles Basic auth and content-type headers', () {
      final f = mockTestRailHttp((o) => '{}');
      expect(f.http.headers['Authorization'], _expectedAuth);
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/post return the response bodies', () async {
      final f = mockTestRailHttp(
        (o) => routeByPath({
          'get_case/1': 'GET-CASE',
          'add_result/3': 'POST-RESULT',
        }, o),
      );
      expect(await f.http.get('get_case/1'), 'GET-CASE');
      expect(await f.http.post('add_result/3'), 'POST-RESULT');
      f.http.close();
    });

    test('throws StateError when TESTRAIL_BASE_PATH is missing', () {
      PropertyReader.clearOverrides();
      expect(() => TestRailHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when TESTRAIL_USERNAME is missing', () {
      PropertyReader.setOverrides({
        'TESTRAIL_BASE_PATH': 'https://tr.example.com',
      });
      expect(() => TestRailHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when TESTRAIL_API_KEY is missing', () {
      PropertyReader.setOverrides({
        'TESTRAIL_BASE_PATH': 'https://tr.example.com',
        'TESTRAIL_USERNAME': 'dev@example.com',
      });
      expect(() => TestRailHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when TESTRAIL_PROJECT is missing', () {
      PropertyReader.setOverrides({
        'TESTRAIL_BASE_PATH': 'https://tr.example.com',
        'TESTRAIL_USERNAME': 'dev@example.com',
        'TESTRAIL_API_KEY': 'key-123',
      });
      expect(() => TestRailHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `testrail_test` — connectivity check via GET `get_user_by_email`.
void testConnectionTests() {
  group('TestRailClient.testConnection', () {
    test('returns success with the user profile', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_user_by_email': _userBody}, o),
      );
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'TestRail connection successful');
      expect(result['user'], 'Dev User');
      expect(result['email'], 'dev@example.com');
      expect(f.adapter.calls.single.path, contains('get_user_by_email'));
      expect(f.adapter.calls.single.path, contains('email=dev@example.com'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockTestRail((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `testrail_get_case` — GET `get_case/{id}`.
void getCaseTests() {
  group('TestRailClient.getCase', () {
    test('returns the decoded case map', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_case/1': _caseBody}, o),
      );
      final testCase = await f.client.getCase(1);
      expect(testCase?['id'], 1);
      expect(testCase?['title'], 'Sample case');
      expect(f.adapter.calls.single.path, contains('get_case/1'));
    });

    test('returns null when the body is not an object', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_case/1': '[1, 2]'}, o),
      );
      expect(await f.client.getCase(1), isNull);
    });
  });
}

/// `testrail_get_cases` — GET `get_cases/{projectId}&suite_id={suiteId}`.
void getCasesTests() {
  group('TestRailClient.getCases', () {
    test('returns the decoded list of cases', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_cases': _casesBody}, o),
      );
      final cases = await f.client.getCases(2);
      expect(cases.map((c) => c['id']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.path, contains('get_cases'));
      expect(call.path, contains('proj-1'));
      expect(call.path, contains('suite_id=2'));
    });

    test('returns empty list when the body is not an array', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_cases': '{"error": "x"}'}, o),
      );
      expect(await f.client.getCases(2), isEmpty);
    });
  });
}

/// `testrail_add_result` — POST `add_result/{testId}`.
void addResultTests() {
  group('TestRailClient.addResult', () {
    test('POSTs status_id and comment', () async {
      final f = mockTestRail(
        (o) => routeByPath({'add_result/3': _resultBody}, o),
      );
      final result = await f.client.addResult(3, 1, 'Passed');
      expect(result['id'], 9001);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, contains('add_result/3'));
      expect(jsonDecode(call.data as String), {
        'status_id': 1,
        'comment': 'Passed',
      });
    });

    test('returns empty map when the body is not an object', () async {
      final f = mockTestRail(
        (o) => routeByPath({'add_result/3': '[1, 2]'}, o),
      );
      expect(await f.client.addResult(3, 1, 'x'), isEmpty);
    });
  });
}

/// Canned `get_user_by_email` response body.
const _userBody = '{"name":"Dev User","email":"dev@example.com"}';

/// Canned `get_case` response body.
const _caseBody = '{"id":1,"title":"Sample case"}';

/// Canned `get_cases` response body.
const _casesBody = '[{"id":1},{"id":2}]';

/// Canned `add_result` response body.
const _resultBody = '{"id":9001}';
