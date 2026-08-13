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
  getBuildTests();
  getBuildLogTests();
  getLastBuildTests();
  getJobDetailsTests();
  getQueueTests();
  cancelBuildTests();
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

/// `jenkins_get_build` — GET `job/{name}/{buildNumber}/api/json`.
void getBuildTests() {
  group('JenkinsClient.getBuild', () {
    test('returns the decoded build object', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/job/job-a/5/api/json': _buildBody}, o),
      );
      final build = await f.client.getBuild('job-a', 5);
      expect(build?['number'], 5);
      expect(build?['result'], 'SUCCESS');
      expect(f.adapter.calls.single.path, endsWith('/job/job-a/5/api/json'));
    });

    test('returns null when the body is not an object', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/job/job-a/5/api/json': '[1]'}, o),
      );
      expect(await f.client.getBuild('job-a', 5), isNull);
    });
  });
}

/// `jenkins_get_build_log` — GET `job/{name}/{buildNumber}/consoleText`.
void getBuildLogTests() {
  group('JenkinsClient.getBuildLog', () {
    test('returns the raw console text', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/job/job-a/5/consoleText': _logBody}, o),
      );
      final log = await f.client.getBuildLog('job-a', 5);
      expect(log, _logBody);
      expect(f.adapter.calls.single.path, endsWith('/job/job-a/5/consoleText'));
    });
  });
}

/// `jenkins_get_last_build` — GET `job/{name}/lastBuild/api/json`.
void getLastBuildTests() {
  group('JenkinsClient.getLastBuild', () {
    test('returns the decoded last-build object', () async {
      final f = mockJenkins(
        (o) => routeByPath(
          {'/job/job-a/lastBuild/api/json': _lastBuildBody},
          o,
        ),
      );
      final build = await f.client.getLastBuild('job-a');
      expect(build?['number'], 10);
      expect(
        f.adapter.calls.single.path,
        endsWith('/job/job-a/lastBuild/api/json'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockJenkins(
        (o) => routeByPath(
          {'/job/job-a/lastBuild/api/json': '[1]'},
          o,
        ),
      );
      expect(await f.client.getLastBuild('job-a'), isNull);
    });
  });
}

/// Canned build-detail response body.
const _buildBody = '{"number":5,"result":"SUCCESS"}';

/// Canned console-log text.
const _logBody = 'Started by user admin\nFinished: SUCCESS';

/// Canned last-build response body.
const _lastBuildBody = '{"number":10,"result":"SUCCESS"}';

/// `jenkins_get_job_details` — GET `job/{name}/api/json?tree=builds[...]`.
void getJobDetailsTests() {
  group('JenkinsClient.getJobDetails', () {
    test('returns the decoded job details with the tree query', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/job/job-a/api/json': _jobDetailsBody}, o),
      );
      final details = await f.client.getJobDetails('job-a');
      expect(details?['builds'], isA<List>());
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/job/job-a/api/json'));
      expect(call.queryParameters['tree'], 'builds[number,result]');
    });

    test('returns null when the body is not an object', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/job/job-a/api/json': '[1]'}, o),
      );
      expect(await f.client.getJobDetails('job-a'), isNull);
    });
  });
}

/// `jenkins_get_queue` — GET `queue/api/json`.
void getQueueTests() {
  group('JenkinsClient.getQueue', () {
    test('returns the decoded queue object', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/queue/api/json': _queueBody}, o),
      );
      final queue = await f.client.getQueue();
      expect(queue?['items'], isA<List>());
      expect(f.adapter.calls.single.path, endsWith('/queue/api/json'));
    });

    test('returns null when the body is not an object', () async {
      final f = mockJenkins(
        (o) => routeByPath({'/queue/api/json': '[1]'}, o),
      );
      expect(await f.client.getQueue(), isNull);
    });
  });
}

/// `jenkins_cancel_build` — POST `cancelItem?id={queueId}`.
void cancelBuildTests() {
  group('JenkinsClient.cancelBuild', () {
    test('POSTs the cancel and reports success', () async {
      final f = mockJenkins((o) => '');
      final result = await f.client.cancelBuild(42);
      expect(result['success'], isTrue);
      expect(result['queueId'], 42);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/cancelItem?id=42'));
    });

    test('reports failure when the POST throws', () async {
      final f = mockJenkins(
        (o) => o.path.contains('cancelItem') ? throw StateError('boom') : '{}',
      );
      final result = await f.client.cancelBuild(42);
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// Canned job-details response body.
const _jobDetailsBody =
    '{"name":"job-a","builds":[{"number":1,"result":"SUCCESS"},'
    '{"number":2,"result":"FAILURE"}]}';

/// Canned queue response body.
const _queueBody = '{"items":[{"id":42},{"id":43}]}';
