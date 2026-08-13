import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'bitrise_test_support.dart';

/// Tests for the [bitriseTools] catalog and [BitriseToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  toolCatalogParamTests();
  toolCatalogBatch4ParamTests();
  toolCatalogBatch5ParamTests();
  executorDispatchTests();
  executorBatch2DispatchTests();
  executorBatch3DispatchTests();
  executorBatch4DispatchTests();
  executorBatch5DispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    bitriseTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration.
void toolCatalogShapeTests() {
  group('bitriseTools catalog', () {
    final tools = bitriseTools();

    test('registers the ten tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'bitrise_test',
        'bitrise_get_apps',
        'bitrise_get_builds',
        'bitrise_get_build_detail',
        'bitrise_trigger_build',
        'bitrise_trigger_build_with_params',
        'bitrise_abort_build',
        'bitrise_get_workflows',
        'bitrise_get_artifacts',
        'bitrise_get_artifact_detail',
      ]);
    });

    test('every tool belongs to the bitrise integration', () {
      expect(tools.every((t) => t.integration == 'bitrise'), isTrue);
    });
  });
}

/// Catalog params: each tool's parameter names and requiredness.
void toolCatalogParamTests() {
  group('bitrise_get_builds', () {
    final tool = toolNamed('bitrise_get_builds');

    test('declares a required app_slug', () {
      expect(tool.params.single.name, 'app_slug');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('bitrise_get_build_detail', () {
    final tool = toolNamed('bitrise_get_build_detail');

    test('declares required app_slug and build_slug', () {
      expect(tool.params.map((p) => p.name), ['app_slug', 'build_slug']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('bitrise_trigger_build', () {
    final tool = toolNamed('bitrise_trigger_build');

    test('declares a required app_slug', () {
      expect(tool.params.single.name, 'app_slug');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('bitrise_trigger_build_with_params', () {
    final tool = toolNamed('bitrise_trigger_build_with_params');

    test('requires app_slug and workflow, optional environments array', () {
      expect(tool.params.map((p) => p.name), [
        'app_slug',
        'workflow',
        'environments',
      ]);
      expect(tool.params[2].type, 'array');
      expect(tool.params[2].required, isFalse);
      expect(tool.params[0].required, isTrue);
      expect(tool.params[1].required, isTrue);
    });
  });
}

/// [BitriseToolExecutor.execute] routes each tool name to the right client call.
void executorDispatchTests() {
  group('BitriseToolExecutor.execute', () {
    late _SpyBitriseClient spy;
    late BitriseToolExecutor executor;

    setUp(() {
      spy = _SpyBitriseClient(mockHttp((o) => '{}').http);
      executor = BitriseToolExecutor(spy);
    });

    test('routes bitrise_test to testConnection', () async {
      await executor.execute('bitrise_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes bitrise_get_builds with app_slug', () async {
      await executor.execute('bitrise_get_builds', {'app_slug': 'app-1'});
      expect(spy.calls, ['getBuilds:app-1']);
    });

    test('routes bitrise_trigger_build with app_slug', () async {
      await executor.execute('bitrise_trigger_build', {'app_slug': 'app-1'});
      expect(spy.calls, ['triggerBuild:app-1']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => executor.execute('bitrise_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// Batch-2 dispatch tests for apps, build detail, and parameterized triggers.
void executorBatch2DispatchTests() {
  group('BitriseToolExecutor.execute (batch 2)', () {
    late _SpyBitriseClient spy;
    late BitriseToolExecutor executor;

    setUp(() {
      spy = _SpyBitriseClient(mockHttp((o) => '{}').http);
      executor = BitriseToolExecutor(spy);
    });

    test('routes bitrise_get_build_detail with app_slug and build_slug',
        () async {
      await executor.execute('bitrise_get_build_detail', {
        'app_slug': 'app-1',
        'build_slug': 'build-2',
      });
      expect(spy.calls, ['getBuildDetail:app-1:build-2']);
    });

    test('routes bitrise_trigger_build_with_params with workflow', () async {
      await executor.execute('bitrise_trigger_build_with_params', {
        'app_slug': 'app-1',
        'workflow': 'primary',
      });
      expect(spy.calls, ['triggerBuildWithParams:app-1:primary:null']);
    });

    test('routes bitrise_trigger_build_with_params with environments',
        () async {
      await executor.execute('bitrise_trigger_build_with_params', {
        'app_slug': 'app-1',
        'workflow': 'primary',
        'environments': [
          {'mapped_to': 'ENV', 'value': 'prod'},
        ],
      });
      expect(spy.calls, ['triggerBuildWithParams:app-1:primary:1']);
    });
  });
}

/// Batch-3 dispatch tests for the build-abort tool.
void executorBatch3DispatchTests() {
  group('BitriseToolExecutor.execute (batch 3)', () {
    late _SpyBitriseClient spy;
    late BitriseToolExecutor executor;

    setUp(() {
      spy = _SpyBitriseClient(mockHttp((o) => '{}').http);
      executor = BitriseToolExecutor(spy);
    });

    test('routes bitrise_abort_build with app_slug and build_slug', () async {
      await executor.execute('bitrise_abort_build', {
        'app_slug': 'app-1',
        'build_slug': 'build-2',
      });
      expect(spy.calls, ['abortBuild:app-1:build-2']);
    });
  });
}

/// Batch-4 catalog params: workflows and artifacts.
void toolCatalogBatch4ParamTests() {
  group('bitrise_get_workflows', () {
    final tool = toolNamed('bitrise_get_workflows');

    test('declares a required app_slug', () {
      expect(tool.params.single.name, 'app_slug');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('bitrise_get_artifacts', () {
    final tool = toolNamed('bitrise_get_artifacts');

    test('declares required app_slug and build_slug', () {
      expect(tool.params.map((p) => p.name), ['app_slug', 'build_slug']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Batch-4 dispatch tests for workflows and artifacts.
void executorBatch4DispatchTests() {
  group('BitriseToolExecutor.execute (batch 4)', () {
    late _SpyBitriseClient spy;
    late BitriseToolExecutor executor;

    setUp(() {
      spy = _SpyBitriseClient(mockHttp((o) => '{}').http);
      executor = BitriseToolExecutor(spy);
    });

    test('routes bitrise_get_workflows with app_slug', () async {
      await executor.execute('bitrise_get_workflows', {'app_slug': 'app-1'});
      expect(spy.calls, ['getWorkflows:app-1']);
    });

    test('routes bitrise_get_artifacts with app_slug and build_slug', () async {
      await executor.execute('bitrise_get_artifacts', {
        'app_slug': 'app-1',
        'build_slug': 'build-2',
      });
      expect(spy.calls, ['getArtifacts:app-1:build-2']);
    });
  });
}

/// Batch-5 catalog params: artifact detail.
void toolCatalogBatch5ParamTests() {
  group('bitrise_get_artifact_detail', () {
    final tool = toolNamed('bitrise_get_artifact_detail');

    test('declares required app_slug, build_slug, and artifact_slug', () {
      expect(
        tool.params.map((p) => p.name),
        ['app_slug', 'build_slug', 'artifact_slug'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Batch-5 dispatch tests for artifact detail.
void executorBatch5DispatchTests() {
  group('BitriseToolExecutor.execute (batch 5)', () {
    late _SpyBitriseClient spy;
    late BitriseToolExecutor executor;

    setUp(() {
      spy = _SpyBitriseClient(mockHttp((o) => '{}').http);
      executor = BitriseToolExecutor(spy);
    });

    test('routes bitrise_get_artifact_detail with the three slugs', () async {
      await executor.execute('bitrise_get_artifact_detail', {
        'app_slug': 'app-1',
        'build_slug': 'build-2',
        'artifact_slug': 'art-1',
      });
      expect(spy.calls, ['getArtifactDetail:app-1:build-2:art-1']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyBitriseClient extends BitriseClient {
  _SpyBitriseClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<List<Map<String, dynamic>>> getApps() {
    calls.add('getApps');
    return super.getApps();
  }

  @override
  Future<Map<String, dynamic>> getBuilds(String appSlug) {
    calls.add('getBuilds:$appSlug');
    return super.getBuilds(appSlug);
  }

  @override
  Future<Map<String, dynamic>?> getBuildDetail(
    String appSlug,
    String buildSlug,
  ) {
    calls.add('getBuildDetail:$appSlug:$buildSlug');
    return super.getBuildDetail(appSlug, buildSlug);
  }

  @override
  Future<Map<String, dynamic>?> triggerBuild(String appSlug) {
    calls.add('triggerBuild:$appSlug');
    return super.triggerBuild(appSlug);
  }

  @override
  Future<Map<String, dynamic>?> triggerBuildWithParams(
    String appSlug,
    String workflow,
    List<Map<String, dynamic>>? environments,
  ) {
    final envCount = environments?.length;
    calls.add('triggerBuildWithParams:$appSlug:$workflow:$envCount');
    return super.triggerBuildWithParams(appSlug, workflow, environments);
  }

  @override
  Future<Map<String, dynamic>?> abortBuild(
    String appSlug,
    String buildSlug,
  ) {
    calls.add('abortBuild:$appSlug:$buildSlug');
    return super.abortBuild(appSlug, buildSlug);
  }

  @override
  Future<Map<String, dynamic>> getWorkflows(String appSlug) {
    calls.add('getWorkflows:$appSlug');
    return super.getWorkflows(appSlug);
  }

  @override
  Future<Map<String, dynamic>> getArtifacts(
    String appSlug,
    String buildSlug,
  ) {
    calls.add('getArtifacts:$appSlug:$buildSlug');
    return super.getArtifacts(appSlug, buildSlug);
  }

  @override
  Future<Map<String, dynamic>?> getArtifactDetail(
    String appSlug,
    String buildSlug,
    String artifactSlug,
  ) {
    calls.add('getArtifactDetail:$appSlug:$buildSlug:$artifactSlug');
    return super.getArtifactDetail(appSlug, buildSlug, artifactSlug);
  }
}
