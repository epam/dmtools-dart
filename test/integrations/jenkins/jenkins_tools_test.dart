import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jenkins_test_support.dart';

/// Tests for the [jenkinsTools] catalog and [JenkinsToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  jobQueueCatalogParamTests();
  artifactConfigCatalogParamTests();
  buildHistoryConsoleCatalogParamTests();
  executorDispatchTests();
  buildInspectionDispatchTests();
  jobQueueDispatchTests();
  artifactConfigDispatchTests();
  buildHistoryConsoleDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    jenkinsTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('jenkinsTools catalog', () {
    final tools = jenkinsTools();

    test('registers the fourteen tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'jenkins_test',
        'jenkins_get_jobs',
        'jenkins_trigger_job',
        'jenkins_get_job_details',
        'jenkins_get_job_builds',
        'jenkins_get_build',
        'jenkins_get_build_log',
        'jenkins_get_console_output',
        'jenkins_get_last_build',
        'jenkins_get_build_artifacts',
        'jenkins_get_queue',
        'jenkins_cancel_build',
        'jenkins_get_job_config',
        'jenkins_get_job_info',
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
}

/// Catalog params: last build, job details, queue, and build cancellation.
void jobQueueCatalogParamTests() {
  group('jenkins_get_last_build', () {
    final tool = toolNamed('jenkins_get_last_build');

    test('declares a required name', () {
      expect(tool.params.single.name, 'name');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('jenkins_get_job_details', () {
    final tool = toolNamed('jenkins_get_job_details');

    test('declares a required name', () {
      expect(tool.params.single.name, 'name');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('jenkins_get_queue', () {
    final tool = toolNamed('jenkins_get_queue');

    test('takes no parameters', () {
      expect(tool.params, isEmpty);
    });
  });

  group('jenkins_cancel_build', () {
    final tool = toolNamed('jenkins_cancel_build');

    test('declares a required numeric queueId', () {
      expect(tool.params.single.name, 'queueId');
      expect(tool.params.single.type, 'number');
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

/// Dispatch tests for build detail, build log, and last build.
void buildInspectionDispatchTests() {
  group('JenkinsToolExecutor.execute (build inspection)', () {
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

/// Dispatch tests for job details, queue, and build cancellation.
void jobQueueDispatchTests() {
  group('JenkinsToolExecutor.execute (job details and queue)', () {
    late _SpyJenkinsClient spy;
    late JenkinsToolExecutor executor;

    setUp(() {
      spy = _SpyJenkinsClient(mockHttp((o) => '{}').http);
      executor = JenkinsToolExecutor(spy);
    });

    test('routes jenkins_get_job_details with name', () async {
      await executor.execute('jenkins_get_job_details', {'name': 'job-a'});
      expect(spy.calls, ['getJobDetails:job-a']);
    });

    test('routes jenkins_get_queue', () async {
      await executor.execute('jenkins_get_queue', {});
      expect(spy.calls, ['getQueue']);
    });

    test('routes jenkins_cancel_build with queueId', () async {
      await executor.execute('jenkins_cancel_build', {'queueId': 42});
      expect(spy.calls, ['cancelBuild:42']);
    });

    test('accepts string queueId from the MCP protocol', () async {
      await executor.execute('jenkins_cancel_build', {'queueId': '42'});
      expect(spy.calls, ['cancelBuild:42']);
    });
  });
}

/// Catalog params: build artifacts and job config.
void artifactConfigCatalogParamTests() {
  group('jenkins_get_build_artifacts', () {
    final tool = toolNamed('jenkins_get_build_artifacts');

    test('declares required name and numeric buildNumber', () {
      expect(tool.params.map((p) => p.name), ['name', 'buildNumber']);
      expect(tool.params[1].type, 'number');
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('jenkins_get_job_config', () {
    final tool = toolNamed('jenkins_get_job_config');

    test('declares a required name', () {
      expect(tool.params.single.name, 'name');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// Catalog params: job build history and console output.
void buildHistoryConsoleCatalogParamTests() {
  group('jenkins_get_job_builds', () {
    final tool = toolNamed('jenkins_get_job_builds');

    test('declares required name and numeric limit', () {
      expect(tool.params.map((p) => p.name), ['name', 'limit']);
      expect(tool.params[1].type, 'number');
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('jenkins_get_console_output', () {
    final tool = toolNamed('jenkins_get_console_output');

    test('declares required name, numeric buildNumber and startByte', () {
      expect(
        tool.params.map((p) => p.name),
        ['name', 'buildNumber', 'startByte'],
      );
      expect(tool.params[1].type, 'number');
      expect(tool.params[2].type, 'number');
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Dispatch tests for build artifacts and job config.
void artifactConfigDispatchTests() {
  group('JenkinsToolExecutor.execute (artifacts and job config)', () {
    late _SpyJenkinsClient spy;
    late JenkinsToolExecutor executor;

    setUp(() {
      spy = _SpyJenkinsClient(mockHttp((o) => '{}').http);
      executor = JenkinsToolExecutor(spy);
    });

    test('routes jenkins_get_build_artifacts with name and buildNumber',
        () async {
      await executor.execute('jenkins_get_build_artifacts', {
        'name': 'job-a',
        'buildNumber': 5,
      });
      expect(spy.calls, ['getBuildArtifacts:job-a:5']);
    });

    test('routes jenkins_get_job_config with name', () async {
      await executor.execute('jenkins_get_job_config', {'name': 'job-a'});
      expect(spy.calls, ['getJobConfig:job-a']);
    });
  });
}

/// Dispatch tests for job build history and console output.
void buildHistoryConsoleDispatchTests() {
  group('JenkinsToolExecutor.execute (build history and console)', () {
    late _SpyJenkinsClient spy;
    late JenkinsToolExecutor executor;

    setUp(() {
      spy = _SpyJenkinsClient(mockHttp((o) => '{}').http);
      executor = JenkinsToolExecutor(spy);
    });

    test('routes jenkins_get_job_builds with name and limit', () async {
      await executor.execute('jenkins_get_job_builds', {
        'name': 'job-a',
        'limit': 3,
      });
      expect(spy.calls, ['getJobBuilds:job-a:3']);
    });

    test('accepts string limit from the MCP protocol', () async {
      await executor.execute('jenkins_get_job_builds', {
        'name': 'job-a',
        'limit': '3',
      });
      expect(spy.calls, ['getJobBuilds:job-a:3']);
    });

    test('routes jenkins_get_console_output with name, build, startByte',
        () async {
      await executor.execute('jenkins_get_console_output', {
        'name': 'job-a',
        'buildNumber': 5,
        'startByte': 1024,
      });
      expect(spy.calls, ['getConsoleOutput:job-a:5:1024']);
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

  @override
  Future<Map<String, dynamic>?> getJobDetails(String name) {
    calls.add('getJobDetails:$name');
    return super.getJobDetails(name);
  }

  @override
  Future<Map<String, dynamic>?> getJobBuilds(String name, int limit) {
    calls.add('getJobBuilds:$name:$limit');
    return super.getJobBuilds(name, limit);
  }

  @override
  Future<String> getConsoleOutput(
    String name,
    int buildNumber,
    int startByte,
  ) {
    calls.add('getConsoleOutput:$name:$buildNumber:$startByte');
    return super.getConsoleOutput(name, buildNumber, startByte);
  }

  @override
  Future<Map<String, dynamic>?> getQueue() {
    calls.add('getQueue');
    return super.getQueue();
  }

  @override
  Future<Map<String, dynamic>> cancelBuild(int queueId) {
    calls.add('cancelBuild:$queueId');
    return super.cancelBuild(queueId);
  }

  @override
  Future<Map<String, dynamic>?> getBuildArtifacts(
    String name,
    int buildNumber,
  ) {
    calls.add('getBuildArtifacts:$name:$buildNumber');
    return super.getBuildArtifacts(name, buildNumber);
  }

  @override
  Future<String> getJobConfig(String name) {
    calls.add('getJobConfig:$name');
    return super.getJobConfig(name);
  }
}
