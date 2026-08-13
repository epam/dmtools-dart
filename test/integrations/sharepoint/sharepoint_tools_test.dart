import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'sharepoint_test_support.dart';

/// Tests for the [sharepointTools] catalog and [SharepointToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    sharepointTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('sharepointTools catalog', () {
    final tools = sharepointTools();

    test('registers the three tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'sharepoint_test',
        'sharepoint_get_drive',
        'sharepoint_list_files',
      ]);
    });

    test('every tool belongs to the sharepoint integration', () {
      expect(tools.every((t) => t.integration == 'sharepoint'), isTrue);
    });
  });

  group('sharepoint_get_drive', () {
    final tool = toolNamed('sharepoint_get_drive');

    test('takes no parameters', () {
      expect(tool.params, isEmpty);
    });
  });

  group('sharepoint_list_files', () {
    final tool = toolNamed('sharepoint_list_files');

    test('declares a required drive_id', () {
      expect(tool.params.single.name, 'drive_id');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// [SharepointToolExecutor.execute] routes each tool name to the right call.
void executorDispatchTests() {
  group('SharepointToolExecutor.execute', () {
    late _SpySharepointClient spy;
    late SharepointToolExecutor executor;

    setUp(() {
      spy = _SpySharepointClient(mockSharepointHttp((o) => '{}').http);
      executor = SharepointToolExecutor(spy);
    });

    test('routes sharepoint_test to testConnection (delegates to getDrive)',
        () async {
      await executor.execute('sharepoint_test', {});
      expect(spy.calls, ['testConnection', 'getDrive']);
    });

    test('routes sharepoint_get_drive to getDrive', () async {
      await executor.execute('sharepoint_get_drive', {});
      expect(spy.calls, ['getDrive']);
    });

    test('routes sharepoint_list_files with drive_id', () async {
      await executor.execute('sharepoint_list_files', {'drive_id': 'd1'});
      expect(spy.calls, ['listFiles:d1']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => executor.execute('sharepoint_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpySharepointClient extends SharepointClient {
  _SpySharepointClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>> getDrive() {
    calls.add('getDrive');
    return super.getDrive();
  }

  @override
  Future<Map<String, dynamic>> listFiles(String driveId) {
    calls.add('listFiles:$driveId');
    return super.listFiles(driveId);
  }
}
