import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'figma_test_support.dart';

/// Tests for the [figmaTools] catalog and [FigmaToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogTests();
  catalogParamTests();
  executorRoutingTests();
  executorNewToolRoutingTests();
  executorEdgeCaseTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    figmaTools().firstWhere((t) => t.name == name);

/// Serves `{}` for every request.
String _spyRouter(RequestOptions o) => '{}';

/// Catalog shape: tool count, order, and integration ownership.
void catalogTests() {
  group('figmaTools catalog', () {
    final tools = figmaTools();

    test('registers the ten tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'figma_test',
        'figma_get_file',
        'figma_get_file_nodes',
        'figma_get_image',
        'figma_export_image',
        'figma_get_comments',
        'figma_post_comment',
        'figma_get_components',
        'figma_get_component_sets',
        'figma_get_styles',
      ]);
    });

    test('every tool belongs to the figma integration', () {
      expect(tools.every((t) => t.integration == 'figma'), isTrue);
    });
  });
}

/// Tools whose params are all required, checked data-driven.
const _requiredParamTools = <(String, List<String>)>[
  ('figma_get_file', ['key']),
  ('figma_get_file_nodes', ['key', 'node_ids']),
  ('figma_get_image', ['key', 'node_id']),
  ('figma_get_comments', ['key']),
  ('figma_post_comment', ['key', 'message']),
  ('figma_get_components', ['key']),
  ('figma_get_component_sets', ['key']),
  ('figma_get_styles', ['key']),
];

/// Param-shape checks for every tool.
void catalogParamTests() {
  group('param shapes (all required)', () {
    for (final (name, params) in _requiredParamTools) {
      test('$name declares ${params.join(', ')}', () {
        final tool = toolNamed(name);
        expect(tool.params.map((p) => p.name), params);
        expect(tool.params.every((p) => p.required), isTrue);
      });
    }
  });

  group('figma_export_image', () {
    final tool = toolNamed('figma_export_image');

    test('declares required key with optional format, scale', () {
      expect(tool.params.map((p) => p.name), ['key', 'format', 'scale']);
      expect(tool.params.first.required, isTrue);
      expect(tool.params[1].required, isFalse);
      expect(tool.params[2].required, isFalse);
      expect(tool.params[2].type, 'number');
    });
  });
}

/// [FigmaToolExecutor.execute] routes original tool names to client calls.
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

/// [FigmaToolExecutor.execute] routes batch-2 tool names to client calls.
void executorNewToolRoutingTests() {
  late _ExecutorFixture f;

  group('FigmaToolExecutor.execute (batch 2)', () {
    setUp(() => f = _executorFixture());

    test('routes figma_get_comments with key', () async {
      await f.executor.execute('figma_get_comments', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComments:aBc123']);
    });

    test('routes figma_post_comment with key, message', () async {
      await f.executor.execute('figma_post_comment', {
        'key': 'aBc123',
        'message': 'Nice work!',
      });
      expect(f.spy.calls, ['postComment:aBc123:Nice work!']);
    });

    test('routes figma_get_components with key', () async {
      await f.executor.execute('figma_get_components', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComponents:aBc123']);
    });

    test('routes figma_get_component_sets with key', () async {
      await f.executor.execute('figma_get_component_sets', {'key': 'aBc123'});
      expect(f.spy.calls, ['getComponentSets:aBc123']);
    });

    test('routes figma_get_styles with key', () async {
      await f.executor.execute('figma_get_styles', {'key': 'aBc123'});
      expect(f.spy.calls, ['getStyles:aBc123']);
    });

    test('routes figma_export_image with key, format, scale', () async {
      await f.executor.execute('figma_export_image', {
        'key': 'aBc123',
        'format': 'svg',
        'scale': 2,
      });
      expect(f.spy.calls, ['exportImage:aBc123:svg:2.0']);
    });

    test('routes figma_export_image without optional params', () async {
      await f.executor.execute('figma_export_image', {'key': 'aBc123'});
      expect(f.spy.calls, ['exportImage:aBc123:null:null']);
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

  @override
  Future<Map<String, dynamic>> getComments(String key) {
    calls.add('getComments:$key');
    return super.getComments(key);
  }

  @override
  Future<Map<String, dynamic>> postComment(String key, String message) {
    calls.add('postComment:$key:$message');
    return super.postComment(key, message);
  }

  @override
  Future<Map<String, dynamic>> getComponents(String key) {
    calls.add('getComponents:$key');
    return super.getComponents(key);
  }

  @override
  Future<Map<String, dynamic>> getComponentSets(String key) {
    calls.add('getComponentSets:$key');
    return super.getComponentSets(key);
  }

  @override
  Future<Map<String, dynamic>> getStyles(String key) {
    calls.add('getStyles:$key');
    return super.getStyles(key);
  }

  @override
  Future<Map<String, dynamic>> exportImage(
    String key, {
    String? format,
    double? scale,
  }) {
    calls.add('exportImage:$key:$format:$scale');
    return super.exportImage(key, format: format, scale: scale);
  }
}
