import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jenkins_test_support.dart';

/// Coverage + behavior tests for [JenkinsClient] and [JenkinsHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getJobsTests();
  triggerJobTests();
}

/// The expected `Basic` header value produced by the fixture's config.
final _expectedBasic = 'Basic ${base64Encode(utf8.encode('dev:token-123'))}';

/// [JenkinsHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('JenkinsHttpClient', () {
    test('builds URLs from the base path', () {
      final f = mockHttp((o) => '{}');
      expect(
          f.http.buildUrl('api/json'), 'http://jenkins.example.com/api/json');
    });

    test('assembles Basic auth and Content-Type headers', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.headers['Authorization'], _expectedBasic);
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/post/put/delete return the response bodies', () async {
      final f = mockHttp((o) => routeByPath({
            '/get': 'GET-BODY',
            '/post': 'POST-BODY',
            '/put': 'PUT-BODY',
            '/del': 'DELETE-BODY',
          }, o));
      expect(await f.http.get('get'), 'GET-BODY');
      expect(await f.http.post('post'), 'POST-BODY');
      expect(await f.http.put('put'), 'PUT-BODY');
      expect(await f.http.delete('del'), 'DELETE-BODY');
      f.http.close();
    });

    test('throws StateError when JENKINS_USER is missing', () {
      PropertyReader.clearOverrides();
      expect(() => JenkinsHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when JENKINS_API_TOKEN is missing', () {
      PropertyReader.setOverrides({'JENKINS_USER': 'dev'});
      expect(() => JenkinsHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `jenkins_test` — connectivity check via GET `api/json`.
void testConnectionTests() {
  group('JenkinsClient.testConnection', () {
    test('returns success with the node class', () async {
      final f = mockJenkins((o) => routeByPath({'/api/json': _rootBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Jenkins connection successful');
      expect(result['node'], 'hudson.model.Hudson');
      expect(f.adapter.calls.single.path, endsWith('/api/json'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockJenkins((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `jenkins_get_jobs` — GET `api/json?tree=jobs[name,url]`.
void getJobsTests() {
  group('JenkinsClient.getJobs', () {
    test('returns the decoded jobs list', () async {
      final f = mockJenkins((o) => routeByPath({'/api/json': _jobsBody}, o));
      final jobs = await f.client.getJobs();
      expect(jobs.map((j) => j['name']).toList(), ['job-a', 'job-b']);
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/api/json'));
      expect(call.queryParameters['tree'], 'jobs[name,url]');
    });

    test('returns empty list when the body has no jobs array', () async {
      final f = mockJenkins((o) => routeByPath({'/api/json': _noJobsBody}, o));
      expect(await f.client.getJobs(), isEmpty);
    });
  });
}

/// `jenkins_trigger_job` — POST `job/{name}/build`.
void triggerJobTests() {
  group('JenkinsClient.triggerJob', () {
    test('POSTs the build and reports success', () async {
      final f = mockJenkins((o) => '');
      final result = await f.client.triggerJob('job-a');
      expect(result['success'], isTrue);
      expect(result['job'], 'job-a');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/job/job-a/build'));
    });

    test('reports failure when the POST throws', () async {
      final f = mockJenkins(
        (o) => o.path.endsWith('/build') ? throw StateError('boom') : '{}',
      );
      final result = await f.client.triggerJob('job-a');
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// Canned root-node response body.
const _rootBody =
    '{"_class":"hudson.model.Hudson","description":"CI","mode":"NORMAL"}';

/// Canned jobs response body.
const _jobsBody = '{"jobs":['
    '{"name":"job-a","url":"http://jenkins.example.com/job/job-a/"},'
    '{"name":"job-b","url":"http://jenkins.example.com/job/job-b/"}'
    ']}';

/// Canned response with no `jobs` array.
const _noJobsBody = '{"_class":"hudson.model.Hudson","mode":"NORMAL"}';
