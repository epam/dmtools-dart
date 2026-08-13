import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jenkins_test_support.dart';

/// Tests for the [jenkinsTools] catalog and [JenkinsToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
  executorBatch2DispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    jenkinsTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('jenkinsTools catalog', () {
    final tools = jenkinsTools();

    test('registers the six tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'jenkins_test',
        'jenkins_get_jobs',
        'jenkins_trigger_job',
        'jenkins_get_build',
        'jenkins_get_build_log',
        'jenkins_get_last_build',
      ]);
    });

    test('every tool belongs to the jenkins integration', () {
      expect(tools.every((t) => t.integration == 'jenkins'), isTrue);
    });
  });

  group('jenkins_trigger_job', () {
    final tool = toolNamed('jenkins_trigger_job');

    test('declares a required name', () {
      expect(tool.params.single.name, 'name');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('jenkins_get_build', () {
    final tool = toolNamed('jenkins_get_build');

    test('declares required name and numeric buildNumber', () {
      expect(tool.params.map((p) => p.name), ['name', 'buildNumber']);
      expect(tool.params[1].type, 'number');
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('jenkins_get_build_log', () {
    final tool = toolNamed('jenkins_get_build_log');

    test('declares required name and numeric buildNumber', () {
      expect(tool.params.map((p) => p.name), ['name', 'buildNumber']);
      expect(tool.params[1].type, 'number');
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('jenkins_get_last_build', () {
    final tool = toolNamed('jenkins_get_last_build');

    test('declares a required name', () {
      expect(tool.params.single.name, 'name');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// [JenkinsToolExecutor.execute] routes each tool name to the right client call.
void executorDispatchTests() {
  group('JenkinsToolExecutor.execute', () {
    late _SpyJenkinsClient spy;
    late JenkinsToolExecutor executor;

    setUp(() {
      spy = _SpyJenkinsClient(mockHttp((o) => '{}').http);
      executor = JenkinsToolExecutor(spy);
    });

    test('routes jenkins_test to testConnection', () async {
      await executor.execute('jenkins_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes jenkins_get_jobs', () async {
      await executor.execute('jenkins_get_jobs', {});
      expect(spy.calls, ['getJobs']);
    });

    test('routes jenkins_trigger_job with name', () async {
      await executor.execute('jenkins_trigger_job', {'name': 'job-a'});
      expect(spy.calls, ['triggerJob:job-a']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => executor.execute('jenkins_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// Batch-2 dispatch tests for build detail, build log, and last build.
void executorBatch2DispatchTests() {
  group('JenkinsToolExecutor.execute (batch 2)', () {
    late _SpyJenkinsClient spy;
    late JenkinsToolExecutor executor;

    setUp(() {
      spy = _SpyJenkinsClient(mockHttp((o) => '{}').http);
      executor = JenkinsToolExecutor(spy);
    });

    test('routes jenkins_get_build with name and buildNumber', () async {
      await executor.execute('jenkins_get_build', {
        'name': 'job-a',
        'buildNumber': 5,
      });
      expect(spy.calls, ['getBuild:job-a:5']);
    });

    test('accepts string buildNumber from the MCP protocol', () async {
      await executor.execute('jenkins_get_build', {
        'name': 'job-a',
        'buildNumber': '5',
      });
      expect(spy.calls, ['getBuild:job-a:5']);
    });

    test('routes jenkins_get_build_log with name and buildNumber', () async {
      await executor.execute('jenkins_get_build_log', {
        'name': 'job-a',
        'buildNumber': 5,
      });
      expect(spy.calls, ['getBuildLog:job-a:5']);
    });

    test('routes jenkins_get_last_build with name', () async {
      await executor.execute('jenkins_get_last_build', {'name': 'job-a'});
      expect(spy.calls, ['getLastBuild:job-a']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyJenkinsClient extends JenkinsClient {
  _SpyJenkinsClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<List<Map<String, dynamic>>> getJobs() {
    calls.add('getJobs');
    return super.getJobs();
  }

  @override
  Future<Map<String, dynamic>> triggerJob(String name) {
    calls.add('triggerJob:$name');
    return super.triggerJob(name);
  }

  @override
  Future<Map<String, dynamic>?> getBuild(String name, int buildNumber) {
    calls.add('getBuild:$name:$buildNumber');
    return super.getBuild(name, buildNumber);
  }

  @override
  Future<String> getBuildLog(String name, int buildNumber) {
    calls.add('getBuildLog:$name:$buildNumber');
    return super.getBuildLog(name, buildNumber);
  }

  @override
  Future<Map<String, dynamic>?> getLastBuild(String name) {
    calls.add('getLastBuild:$name');
    return super.getLastBuild(name);
  }
}
