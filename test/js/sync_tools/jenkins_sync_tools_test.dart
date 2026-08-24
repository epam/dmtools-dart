import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/jenkins_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

/// Tests for [JenkinsSyncTools] — the Jenkins section of the sync tool
/// bridge (Java `Jenkins.java` @MCPTool parity, incl. folder job paths).
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _testJobPathSegments();
  _testRoutingAndConfig();
  if (hasPython3()) {
    _testTools();
  }
}

Map<String, String> _config(int port) => {
      'JENKINS_BASE_PATH': 'http://127.0.0.1:$port',
      'JENKINS_USER': 'jenkins-user',
      'JENKINS_API_TOKEN': 'jenkins-token',
    };

void _testJobPathSegments() {
  group('apiJobPath (Java Jenkins.toApiJobPath)', () {
    test('plain job name becomes a single job/ segment', () {
      expect(apiJobPath('my-job'), '/job/my-job/');
    });

    test('folder paths become one job/ segment per element', () {
      expect(apiJobPath('team/service'), '/job/team/job/service/');
    });

    test('already-encoded /job/ paths pass through', () {
      expect(apiJobPath('/job/team/job/service'), '/job/team/job/service/');
      expect(apiJobPath('job/team'), '/job/team/');
    });

    test('blank paths resolve to the root', () {
      expect(apiJobPath(''), '/');
      expect(apiJobPath('  '), '/');
    });

    test('segments are URL-encoded individually (never %2F as one)', () {
      expect(apiJobPath('a b/c'), '/job/a%20b/job/c/');
    });
  });
}

void _testRoutingAndConfig() {
  group('JenkinsSyncTools routing and config', () {
    late JenkinsSyncTools tools;

    setUp(() {
      PropertyReader.setOverrides({
        'JENKINS_BASE_PATH': 'http://localhost:8080',
        'JENKINS_USER': '',
        'JENKINS_API_TOKEN': '',
      });
      tools = JenkinsSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('unsupported tool returns error JSON', () {
      expect(
        jsonDecode(tools.dispatch('jenkins_mystery', {})),
        {'error': 'Unsupported Jenkins tool: jenkins_mystery'},
      );
    });

    test('handlers map exposes the Java tool names', () {
      expect(tools.handlers.keys, contains('jenkins_get_job_info'));
      expect(tools.handlers.keys, contains('jenkins_get_build_log'));
    });

    test('missing credentials return not-configured error', () {
      expect(
        jsonDecode(tools.dispatch(
          'jenkins_get_job_info',
          {'jobPath': 'j', 'buildNumber': 1},
        )),
        {'error': 'Jenkins not configured'},
      );
    });
  });
}

void _testTools() {
  group('JenkinsSyncTools tools', () {
    late EchoServer server;
    late JenkinsSyncTools tools;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides(_config(server.port));
      tools = JenkinsSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('jenkins_get_job_info hits {jobPath}/{n}/api/json', () {
      final body = jsonDecode(tools.dispatch('jenkins_get_job_info', {
        'jobPath': 'team/service',
        'buildNumber': 42,
      }));
      expect(body['method'], 'GET');
      expect(body['path'], '/job/team/job/service/42/api/json');
    });

    test('jenkins_get_job_info sends Basic auth', () {
      final body = jsonDecode(tools.dispatch(
        'jenkins_get_job_info',
        {'jobPath': 'j', 'buildNumber': 1},
      ));
      final expected = base64Encode(utf8.encode('jenkins-user:jenkins-token'));
      expect(body['headers']['Authorization'], 'Basic $expected');
      expect(body['headers']['Accept'], 'application/json');
    });

    test('jenkins_get_build_log hits {jobPath}/{n}/consoleText', () {
      final body = jsonDecode(tools.dispatch('jenkins_get_build_log', {
        'jobPath': 'team/service',
        'buildNumber': 7,
      }));
      expect(body['method'], 'GET');
      expect(body['path'], '/job/team/job/service/7/consoleText');
    });

    test('buildNumber as string is coerced', () {
      final body = jsonDecode(tools.dispatch('jenkins_get_build_log', {
        'jobPath': 'j',
        'buildNumber': '9',
      }));
      expect(body['path'], '/job/j/9/consoleText');
    });
  });
}
