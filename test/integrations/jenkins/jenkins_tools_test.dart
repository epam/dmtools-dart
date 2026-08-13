import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jenkins_test_support.dart';

/// Tests for the [jenkinsTools] catalog and [JenkinsToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    jenkinsTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('jenkinsTools catalog', () {
    final tools = jenkinsTools();

    test('registers the three tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'jenkins_test',
        'jenkins_get_jobs',
        'jenkins_trigger_job',
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
}
