import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'sharepoint_test_support.dart';

/// Tests for the [sharepointTools] catalog and [SharepointToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  toolCatalogParamTests();
  executorDispatchTests();
  fileToolDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    sharepointTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration.
void toolCatalogTests() {
  group('sharepointTools catalog', () {
    final tools = sharepointTools();

    test('registers the six tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'sharepoint_test',
        'sharepoint_get_drive',
        'sharepoint_list_files',
        'sharepoint_get_file',
        'sharepoint_upload_file',
        'sharepoint_create_folder',
      ]);
    });

    test('every tool belongs to the sharepoint integration', () {
      expect(tools.every((t) => t.integration == 'sharepoint'), isTrue);
    });
  });
}

/// Per-tool parameter declarations in the catalog.
void toolCatalogParamTests() {
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

  group('sharepoint_get_file', () {
    final tool = toolNamed('sharepoint_get_file');

    test('declares required drive_id and item_id', () {
      expect(tool.params.map((p) => p.name), ['drive_id', 'item_id']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('sharepoint_upload_file', () {
    final tool = toolNamed('sharepoint_upload_file');

    test('declares required drive_id, folder_id, file_name, content', () {
      expect(
        tool.params.map((p) => p.name),
        ['drive_id', 'folder_id', 'file_name', 'content'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('sharepoint_create_folder', () {
    final tool = toolNamed('sharepoint_create_folder');

    test('declares required drive_id, parent_id, name', () {
      expect(tool.params.map((p) => p.name), ['drive_id', 'parent_id', 'name']);
      expect(tool.params.every((p) => p.required), isTrue);
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

/// Dispatch tests for file-operation tools.
void fileToolDispatchTests() {
  group('SharepointToolExecutor.execute file tools', () {
    late _SpySharepointClient spy;
    late SharepointToolExecutor executor;

    setUp(() {
      spy = _SpySharepointClient(mockSharepointHttp((o) => '{}').http);
      executor = SharepointToolExecutor(spy);
    });

    test('routes sharepoint_get_file with drive_id and item_id', () async {
      await executor.execute(
        'sharepoint_get_file',
        {'drive_id': 'd1', 'item_id': 'i1'},
      );
      expect(spy.calls, ['getFile:d1:i1']);
    });

    test('routes sharepoint_upload_file with all params', () async {
      await executor.execute(
        'sharepoint_upload_file',
        {
          'drive_id': 'd1',
          'folder_id': 'f1',
          'file_name': 'n.txt',
          'content': 'c'
        },
      );
      expect(spy.calls, ['uploadFile:d1:f1:n.txt:c']);
    });

    test('routes sharepoint_create_folder with all params', () async {
      await executor.execute(
        'sharepoint_create_folder',
        {'drive_id': 'd1', 'parent_id': 'p1', 'name': 'New'},
      );
      expect(spy.calls, ['createFolder:d1:p1:New']);
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

  @override
  Future<String> getFile(String driveId, String itemId) {
    calls.add('getFile:$driveId:$itemId');
    return super.getFile(driveId, itemId);
  }

  @override
  Future<Map<String, dynamic>> uploadFile(
    String driveId,
    String folderId,
    String fileName,
    String content,
  ) {
    calls.add('uploadFile:$driveId:$folderId:$fileName:$content');
    return super.uploadFile(driveId, folderId, fileName, content);
  }

  @override
  Future<Map<String, dynamic>> createFolder(
    String driveId,
    String parentId,
    String name,
  ) {
    calls.add('createFolder:$driveId:$parentId:$name');
    return super.createFolder(driveId, parentId, name);
  }
}
