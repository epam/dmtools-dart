import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'xray_test_support.dart';

/// Coverage + behavior tests for [XrayClient] and [XrayHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  authenticateTests();
  testConnectionTests();
  getTestsTests();
  getTestExecutionsTests();
  getTestStepsTests();
  getTestPlanTests();
  createTestExecutionTests();
  updateTestExecutionTests();
  getTestRunsTests();
}

/// [XrayHttpClient]: URL building, auth headers, token state, config errors.
void httpClientTests() {
  group('XrayHttpClient', () {
    test('builds /api/v2/ URLs', () {
      final f = mockXrayHttp((o) => '{}');
      expect(
        f.http.buildUrl('authenticate'),
        'https://xray.example.com/api/v2/authenticate',
      );
      expect(
        f.http.buildUrl('tests'),
        'https://xray.example.com/api/v2/tests',
      );
    });

    test('omits Authorization before authentication', () {
      final f = mockXrayHttp((o) => '{}');
      expect(f.http.authHeaders, isEmpty);
      expect(f.http.isAuthenticated, isFalse);
    });

    test('emits Bearer token after setToken', () {
      final f = mockXrayHttp((o) => '{}');
      f.http.setToken('jwt-abc');
      expect(f.http.authHeaders['Authorization'], 'Bearer jwt-abc');
      expect(f.http.isAuthenticated, isTrue);
    });

    test('exposes clientId and clientSecret from config', () {
      final f = mockXrayHttp((o) => '{}');
      expect(f.http.clientId, 'client-123');
      expect(f.http.clientSecret, 'secret-456');
    });

    test('throws StateError when XRAY_BASE_PATH is missing', () {
      PropertyReader.clearOverrides();
      expect(() => XrayHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when XRAY_CLIENT_ID is missing', () {
      PropertyReader.setOverrides(
          {'XRAY_BASE_PATH': 'https://xray.example.com'});
      expect(() => XrayHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when XRAY_CLIENT_SECRET is missing', () {
      PropertyReader.setOverrides({
        'XRAY_BASE_PATH': 'https://xray.example.com',
        'XRAY_CLIENT_ID': 'client-123',
      });
      expect(() => XrayHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `authenticate` — POST `/api/v2/authenticate` and store the JWT.
void authenticateTests() {
  group('XrayClient.authenticate', () {
    test('POSTs credentials and stores the Bearer token', () async {
      final f = mockXrayHttp(
        (o) => routeByPath({'authenticate': '"jwt-token"'}, o),
      );
      final client = XrayClient(f.http);
      await client.authenticate('client-123', 'secret-456');
      expect(f.http.isAuthenticated, isTrue);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v2/authenticate'));
      expect(jsonDecode(call.data as String), {
        'client_id': 'client-123',
        'client_secret': 'secret-456',
      });
    });

    test('does not store token when body is not a string', () async {
      final f = mockXrayHttp(
        (o) => routeByPath({'authenticate': '{"error":"bad"}'}, o),
      );
      final client = XrayClient(f.http);
      await client.authenticate('client-123', 'secret-456');
      expect(f.http.isAuthenticated, isFalse);
    });
  });
}

/// `jira_xray_test` — connectivity check via OAuth2.
void testConnectionTests() {
  group('XrayClient.testConnection', () {
    test('returns success on valid authentication', () async {
      final f = mockXray(
        (o) => routeByPath({'authenticate': '"jwt-token"'}, o),
      );
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Xray connection successful');
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockXray((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `jira_xray_get_tests` — POST `/api/v2/tests`.
void getTestsTests() {
  group('XrayClient.getTests', () {
    test('auto-authenticates then POSTs test keys', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'tests': _testsBody,
        }, o),
      );
      final result = await f.client.getTests(['PROJ-1', 'PROJ-2']);
      expect(result.map((t) => t['key']).toList(), ['PROJ-1', 'PROJ-2']);
      expect(f.adapter.calls.length, 2);
      expect(f.adapter.calls[0].path, endsWith('authenticate'));
      expect(f.adapter.calls[1].method, 'POST');
      expect(f.adapter.calls[1].path, endsWith('tests'));
      expect(jsonDecode(f.adapter.calls[1].data as String), {
        'keys': ['PROJ-1', 'PROJ-2'],
      });
    });

    test('returns empty list for non-array body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'tests': '{"error":"x"}',
        }, o),
      );
      expect(await f.client.getTests(['PROJ-1']), isEmpty);
    });
  });
}

/// `getTestExecutions` — GET `/api/v2/test/{testKey}/testexecutions`.
void getTestExecutionsTests() {
  group('XrayClient.getTestExecutions', () {
    test('auto-authenticates then GETs test executions', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testexecutions': _execsBody,
        }, o),
      );
      final result = await f.client.getTestExecutions('PROJ-1');
      expect(result.map((t) => t['key']).toList(), ['EXEC-1']);
      final getCall = f.adapter.calls.where((c) => c.method == 'GET').single;
      expect(getCall.path, contains('test/PROJ-1/testexecutions'));
    });

    test('returns empty list for non-array body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testexecutions': '{"error":"x"}',
        }, o),
      );
      expect(await f.client.getTestExecutions('PROJ-1'), isEmpty);
    });
  });
}

/// `jira_xray_create_test_execution` — POST `/api/v2/import/execution`.
void createTestExecutionTests() {
  group('XrayClient.createTestExecution', () {
    test('auto-authenticates then POSTs merged payload', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'execution': _execResultBody,
        }, o),
      );
      final result = await f.client.createTestExecution(
        'PROJ',
        {
          'tests': [
            {'testKey': 'PROJ-1', 'status': 'PASS'}
          ]
        },
      );
      expect(result['id'], 'EXEC-100');
      final postCall =
          f.adapter.calls.where((c) => c.path.endsWith('execution')).single;
      expect(jsonDecode(postCall.data as String), {
        'tests': [
          {'testKey': 'PROJ-1', 'status': 'PASS'}
        ],
        'projectKey': 'PROJ',
      });
    });

    test('returns empty map for non-object body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'execution': '[1, 2]',
        }, o),
      );
      expect(await f.client.createTestExecution('PROJ', {}), isEmpty);
    });
  });
}

/// Canned `tests` response body.
const _testsBody = '[{"key":"PROJ-1"},{"key":"PROJ-2"}]';

/// Canned test-executions response body.
const _execsBody = '[{"key":"EXEC-1"}]';

/// `getTestSteps` — GET `/api/v2/test/{testKey}/steps`.
void getTestStepsTests() {
  group('XrayClient.getTestSteps', () {
    test('auto-authenticates then GETs test steps', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'steps': _stepsBody,
        }, o),
      );
      final result = await f.client.getTestSteps('PROJ-1');
      expect(result.map((s) => s['id']).toList(), [1, 2]);
      final getCall = f.adapter.calls.where((c) => c.method == 'GET').single;
      expect(getCall.path, contains('test/PROJ-1/steps'));
    });

    test('returns empty list for non-array body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'steps': '{"error":"x"}',
        }, o),
      );
      expect(await f.client.getTestSteps('PROJ-1'), isEmpty);
    });
  });
}

/// `getTestPlan` — GET `/api/v2/testplan/{testPlanKey}`.
void getTestPlanTests() {
  group('XrayClient.getTestPlan', () {
    test('auto-authenticates then GETs the test plan', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testplan/PROJ-100': _planBody,
        }, o),
      );
      final result = await f.client.getTestPlan('PROJ-100');
      expect(result['key'], 'PROJ-100');
      final getCall = f.adapter.calls.where((c) => c.method == 'GET').single;
      expect(getCall.path, contains('testplan/PROJ-100'));
    });

    test('returns empty map for non-object body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testplan/PROJ-100': '[1, 2]',
        }, o),
      );
      expect(await f.client.getTestPlan('PROJ-100'), isEmpty);
    });
  });
}

/// Canned test-steps response body.
const _stepsBody = '[{"id":1},{"id":2}]';

/// Canned test-plan response body.
const _planBody = '{"key":"PROJ-100"}';

/// Canned import/execution result body.
const _execResultBody = '{"id":"EXEC-100"}';

/// `jira_xray_update_test_execution` — POST `/api/v2/testexec/{executionId}`.
void updateTestExecutionTests() {
  group('XrayClient.updateTestExecution', () {
    test('auto-authenticates then POSTs the status', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testexec/100': _updateResultBody,
        }, o),
      );
      final result = await f.client.updateTestExecution('100', 'PASS');
      expect(result['id'], '100');
      final postCall = f.adapter.calls
          .where((c) => c.method == 'POST' && c.path.contains('testexec'))
          .single;
      expect(postCall.path, contains('testexec/100'));
      expect(jsonDecode(postCall.data as String), {'status': 'PASS'});
    });

    test('returns empty map for non-object body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testexec/100': '[1, 2]',
        }, o),
      );
      expect(await f.client.updateTestExecution('100', 'PASS'), isEmpty);
    });
  });
}

/// `jira_xray_get_test_runs` — GET `/api/v2/testrun?testKey={testKey}`.
void getTestRunsTests() {
  group('XrayClient.getTestRuns', () {
    test('auto-authenticates then GETs test runs', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testrun': _runsBody,
        }, o),
      );
      final result = await f.client.getTestRuns('PROJ-1');
      expect(result.map((r) => r['id']).toList(), [1, 2]);
      final getCall = f.adapter.calls.where((c) => c.method == 'GET').single;
      expect(getCall.path, contains('testrun'));
      expect(getCall.queryParameters['testKey'], 'PROJ-1');
    });

    test('returns empty list for non-array body', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'testrun': '{"error":"x"}',
        }, o),
      );
      expect(await f.client.getTestRuns('PROJ-1'), isEmpty);
    });
  });
}

/// Canned update-test-execution result body.
const _updateResultBody = '{"id":"100","status":"PASS"}';

/// Canned test-run response body.
const _runsBody = '[{"id":1,"status":"PASS"},{"id":2,"status":"FAIL"}]';
