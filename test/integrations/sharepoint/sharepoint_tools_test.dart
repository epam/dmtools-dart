import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'sharepoint_test_support.dart';

/// Tests for the [sharepointTools] catalog and [SharepointToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  toolCatalogParamTests();
  driveContentCatalogParamTests();
  siteCatalogParamTests();
  copyItemCatalogTests();
  executorDispatchTests();
  fileToolDispatchTests();
  driveContentDispatchTests();
  siteDispatchTests();
  copyItemDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    sharepointTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration.
void toolCatalogTests() {
  group('sharepointTools catalog', () {
    final tools = sharepointTools();

    test('registers the twelve tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'sharepoint_test',
        'sharepoint_get_drive',
        'sharepoint_get_site',
        'sharepoint_list_sites',
        'sharepoint_list_files',
        'sharepoint_get_file',
        'sharepoint_upload_file',
        'sharepoint_create_folder',
        'sharepoint_get_drive_items',
        'sharepoint_search_drive',
        'sharepoint_delete_drive_item',
        'sharepoint_copy_item',
      ]);
    });

    test('every tool belongs to the sharepoint integration', () {
      expect(tools.every((t) => t.integration == 'sharepoint'), isTrue);
    });
  });
}

/// Per-tool parameter declarations in the catalog (core tools).
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

/// Per-tool parameter declarations for the drive-content tools.
void driveContentCatalogParamTests() {
  group('sharepoint_get_drive_items', () {
    final tool = toolNamed('sharepoint_get_drive_items');

    test('declares required drive_id and folder_id', () {
      expect(tool.params.map((p) => p.name), ['drive_id', 'folder_id']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('sharepoint_search_drive', () {
    final tool = toolNamed('sharepoint_search_drive');

    test('declares required drive_id and query', () {
      expect(tool.params.map((p) => p.name), ['drive_id', 'query']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('sharepoint_delete_drive_item', () {
    final tool = toolNamed('sharepoint_delete_drive_item');

    test('declares required drive_id and item_id', () {
      expect(tool.params.map((p) => p.name), ['drive_id', 'item_id']);
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

/// Dispatch tests for the drive-content tools.
void driveContentDispatchTests() {
  group('SharepointToolExecutor.execute drive-content tools', () {
    late _SpySharepointClient spy;
    late SharepointToolExecutor executor;

    setUp(() {
      spy = _SpySharepointClient(mockSharepointHttp((o) => '{}').http);
      executor = SharepointToolExecutor(spy);
    });

    test('routes sharepoint_get_drive_items with drive_id and folder_id',
        () async {
      await executor.execute(
        'sharepoint_get_drive_items',
        {'drive_id': 'd1', 'folder_id': 'f1'},
      );
      expect(spy.calls, ['getDriveItems:d1:f1']);
    });

    test('routes sharepoint_search_drive with drive_id and query', () async {
      await executor.execute(
        'sharepoint_search_drive',
        {'drive_id': 'd1', 'query': 'report'},
      );
      expect(spy.calls, ['searchDrive:d1:report']);
    });

    test('routes sharepoint_delete_drive_item with drive_id and item_id',
        () async {
      await executor.execute(
        'sharepoint_delete_drive_item',
        {'drive_id': 'd1', 'item_id': 'i1'},
      );
      expect(spy.calls, ['deleteDriveItem:d1:i1']);
    });
  });
}

/// Per-tool parameter declarations for the site tools.
void siteCatalogParamTests() {
  group('sharepoint_get_site', () {
    final tool = toolNamed('sharepoint_get_site');

    test('takes no parameters', () {
      expect(tool.params, isEmpty);
      expect(tool.category, 'sites');
    });
  });

  group('sharepoint_list_sites', () {
    final tool = toolNamed('sharepoint_list_sites');

    test('declares a required query', () {
      expect(tool.params.single.name, 'query');
      expect(tool.params.single.required, isTrue);
      expect(tool.category, 'sites');
    });
  });
}

/// Per-tool parameter declarations for the copy-item tool.
void copyItemCatalogTests() {
  group('sharepoint_copy_item', () {
    final tool = toolNamed('sharepoint_copy_item');

    test('declares required src/dst drive and item ids', () {
      expect(
        tool.params.map((p) => p.name),
        ['src_drive_id', 'src_item_id', 'dst_drive_id', 'dst_folder_id'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Dispatch tests for the site tools.
void siteDispatchTests() {
  group('SharepointToolExecutor.execute site tools', () {
    late _SpySharepointClient spy;
    late SharepointToolExecutor executor;

    setUp(() {
      spy = _SpySharepointClient(mockSharepointHttp((o) => '{}').http);
      executor = SharepointToolExecutor(spy);
    });

    test('routes sharepoint_get_site with no params', () async {
      await executor.execute('sharepoint_get_site', {});
      expect(spy.calls, ['getSite']);
    });

    test('routes sharepoint_list_sites with query', () async {
      await executor.execute('sharepoint_list_sites', {'query': 'project'});
      expect(spy.calls, ['listSites:project']);
    });
  });
}

/// Dispatch tests for the copy-item tool.
void copyItemDispatchTests() {
  group('SharepointToolExecutor.execute copy item', () {
    late _SpySharepointClient spy;
    late SharepointToolExecutor executor;

    setUp(() {
      spy = _SpySharepointClient(mockSharepointHttp((o) => '{}').http);
      executor = SharepointToolExecutor(spy);
    });

    test('routes sharepoint_copy_item with all four params', () async {
      await executor.execute(
        'sharepoint_copy_item',
        {
          'src_drive_id': 'sd',
          'src_item_id': 'si',
          'dst_drive_id': 'dd',
          'dst_folder_id': 'df',
        },
      );
      expect(spy.calls, ['copyItem:sd:si:dd:df']);
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

  @override
  Future<Map<String, dynamic>> getDriveItems(String driveId, String folderId) {
    calls.add('getDriveItems:$driveId:$folderId');
    return super.getDriveItems(driveId, folderId);
  }

  @override
  Future<Map<String, dynamic>> searchDrive(String driveId, String query) {
    calls.add('searchDrive:$driveId:$query');
    return super.searchDrive(driveId, query);
  }

  @override
  Future<Map<String, dynamic>> deleteDriveItem(String driveId, String itemId) {
    calls.add('deleteDriveItem:$driveId:$itemId');
    return super.deleteDriveItem(driveId, itemId);
  }

  @override
  Future<Map<String, dynamic>> getSite() {
    calls.add('getSite');
    return super.getSite();
  }

  @override
  Future<Map<String, dynamic>> listSites(String query) {
    calls.add('listSites:$query');
    return super.listSites(query);
  }

  @override
  Future<Map<String, dynamic>> copyItem(
    String srcDriveId,
    String srcItemId,
    String dstDriveId,
    String dstFolderId,
  ) {
    calls.add('copyItem:$srcDriveId:$srcItemId:$dstDriveId:$dstFolderId');
    return super.copyItem(srcDriveId, srcItemId, dstDriveId, dstFolderId);
  }
}
