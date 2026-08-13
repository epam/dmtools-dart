import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'bitrise_test_support.dart';

/// Tests for the [bitriseTools] catalog and [BitriseToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    bitriseTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('bitriseTools catalog', () {
    final tools = bitriseTools();

    test('registers the three tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'bitrise_test',
        'bitrise_get_builds',
        'bitrise_trigger_build',
      ]);
    });

    test('every tool belongs to the bitrise integration', () {
      expect(tools.every((t) => t.integration == 'bitrise'), isTrue);
    });
  });

  group('bitrise_get_builds', () {
    final tool = toolNamed('bitrise_get_builds');

    test('declares a required app_slug', () {
      expect(tool.params.single.name, 'app_slug');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('bitrise_trigger_build', () {
    final tool = toolNamed('bitrise_trigger_build');

    test('declares a required app_slug', () {
      expect(tool.params.single.name, 'app_slug');
      expect(tool.params.single.required, isTrue);
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
  Future<Map<String, dynamic>> getBuilds(String appSlug) {
    calls.add('getBuilds:$appSlug');
    return super.getBuilds(appSlug);
  }

  @override
  Future<Map<String, dynamic>?> triggerBuild(String appSlug) {
    calls.add('triggerBuild:$appSlug');
    return super.triggerBuild(appSlug);
  }
}
