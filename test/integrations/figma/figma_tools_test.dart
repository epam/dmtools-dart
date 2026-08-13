import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'figma_test_support.dart';

/// Tests for the [figmaTools] catalog and [FigmaToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogTests();
  executorRoutingTests();
  executorEdgeCaseTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    figmaTools().firstWhere((t) => t.name == name);

/// Serves `{}` for every request.
String _spyRouter(RequestOptions o) => '{}';

/// Catalog shape: tool count, order, integration, and params.
void catalogTests() {
  group('figmaTools catalog', () {
    final tools = figmaTools();

    test('registers the four tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'figma_test',
        'figma_get_file',
        'figma_get_file_nodes',
        'figma_get_image',
      ]);
    });

    test('every tool belongs to the figma integration', () {
      expect(tools.every((t) => t.integration == 'figma'), isTrue);
    });
  });

  group('figma_get_file', () {
    final tool = toolNamed('figma_get_file');

    test('declares required key', () {
      expect(tool.params.map((p) => p.name), ['key']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('figma_get_file_nodes', () {
    final tool = toolNamed('figma_get_file_nodes');

    test('declares required key, node_ids', () {
      expect(tool.params.map((p) => p.name), ['key', 'node_ids']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('figma_get_image', () {
    final tool = toolNamed('figma_get_image');

    test('declares required key, node_id', () {
      expect(tool.params.map((p) => p.name), ['key', 'node_id']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [FigmaToolExecutor.execute] routes tool names to client calls.
void executorRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute', () {
    setUp(() => f = _executorFixture());

    test('routes figma_test to testConnection', () async {
      await f.executor.execute('figma_test', {});
      expect(f.spy.calls, ['testConnection']);
    });

    test('routes figma_get_file with key', () async {
      await f.executor.execute('figma_get_file', {'key': 'aBc123'});
      expect(f.spy.calls, ['getFile:aBc123']);
    });

    test('routes figma_get_file_nodes with key, node_ids', () async {
      await f.executor.execute('figma_get_file_nodes', {
        'key': 'aBc123',
        'node_ids': '1:2,3:4',
      });
      expect(f.spy.calls, ['getFileNodes:aBc123:1:2,3:4']);
    });

    test('routes figma_get_image with key, node_id', () async {
      await f.executor.execute('figma_get_image', {
        'key': 'aBc123',
        'node_id': '1:2',
      });
      expect(f.spy.calls, ['getImage:aBc123:1:2']);
    });
  });
}

/// [FigmaToolExecutor.execute] error cases.
void executorEdgeCaseTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (edge cases)', () {
    setUp(() => f = _executorFixture());

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => f.executor.execute('figma_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _ExecutorFixture = ({FigmaToolExecutor executor, _SpyFigmaClient spy});

/// Builds a [_SpyFigmaClient] over the mocked transport and wraps it.
_ExecutorFixture _executorFixture() {
  final spy = _SpyFigmaClient(mockFigmaHttp(_spyRouter).http);
  return (executor: FigmaToolExecutor(spy), spy: spy);
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyFigmaClient extends FigmaClient {
  _SpyFigmaClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>> getFile(String key) {
    calls.add('getFile:$key');
    return super.getFile(key);
  }

  @override
  Future<Map<String, dynamic>> getFileNodes(String key, String nodeIds) {
    calls.add('getFileNodes:$key:$nodeIds');
    return super.getFileNodes(key, nodeIds);
  }

  @override
  Future<Map<String, dynamic>> getImage(String key, String nodeId) {
    calls.add('getImage:$key:$nodeId');
    return super.getImage(key, nodeId);
  }
}
