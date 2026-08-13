import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'sharepoint_test_support.dart';

/// Coverage + behavior tests for [SharepointClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  testConnectionTests();
  getDriveTests();
  getSiteTests();
  listSitesTests();
  listFilesTests();
  getFileTests();
  uploadFileTests();
  createFolderTests();
  getDriveItemsTests();
  searchDriveTests();
  deleteDriveItemTests();
  copyItemTests();
}

/// `sharepoint_test` — connectivity check via GET `me/drive`.
void testConnectionTests() {
  group('SharepointClient.testConnection', () {
    test('returns success with the drive name', () async {
      final f = mockSharepoint((o) => routeByPath({'/drive': _driveBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'SharePoint connection successful');
      expect(result['drive'], 'MyDrive');
      expect(f.adapter.calls.single.path, endsWith('/v1.0/me/drive'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockSharepoint((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `sharepoint_get_drive` — GET `me/drive`.
void getDriveTests() {
  group('SharepointClient.getDrive', () {
    test('returns the decoded drive object', () async {
      final f = mockSharepoint((o) => routeByPath({'/drive': _driveBody}, o));
      final drive = await f.client.getDrive();
      expect(drive['id'], 'drive-1');
      expect(drive['name'], 'MyDrive');
      expect(f.adapter.calls.single.path, endsWith('/v1.0/me/drive'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'/drive': '[1]'}, o));
      expect(await f.client.getDrive(), isEmpty);
    });
  });
}

/// `sharepoint_get_site` — GET `sites/root`.
void getSiteTests() {
  group('SharepointClient.getSite', () {
    test('returns the decoded root site object', () async {
      final f =
          mockSharepoint((o) => routeByPath({'sites/root': _siteBody}, o));
      final site = await f.client.getSite();
      expect(site['id'], 'site-1');
      expect(site['displayName'], 'Root Site');
      expect(f.adapter.calls.single.path, endsWith('/v1.0/sites/root'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'sites/root': '[1]'}, o));
      expect(await f.client.getSite(), isEmpty);
    });
  });
}

/// `sharepoint_list_sites` — GET `sites?search={query}`.
void listSitesTests() {
  group('SharepointClient.listSites', () {
    test('returns the decoded search results', () async {
      final f = mockSharepoint((o) => routeByPath({'sites': _sitesBody}, o));
      final result = await f.client.listSites('project');
      expect(result['value'], isA<List>());
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/v1.0/sites'));
      expect(call.queryParameters['search'], 'project');
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'sites': '[1]'}, o));
      expect(await f.client.listSites('project'), isEmpty);
    });
  });
}

/// `sharepoint_list_files` — GET `drives/{driveId}/root/children`.
void listFilesTests() {
  group('SharepointClient.listFiles', () {
    test('returns the decoded files object', () async {
      final f =
          mockSharepoint((o) => routeByPath({'/children': _filesBody}, o));
      final files = await f.client.listFiles('drive-1');
      expect(files['value'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v1.0/drives/drive-1/root/children'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'/children': '[1]'}, o));
      expect(await f.client.listFiles('drive-1'), isEmpty);
    });
  });
}

/// `sharepoint_get_file` — GET `drives/{driveId}/items/{itemId}/content`.
void getFileTests() {
  group('SharepointClient.getFile', () {
    test('returns the raw file content', () async {
      final f = mockSharepoint((o) => routeByPath({'/content': 'RAW'}, o));
      final content = await f.client.getFile('drive-1', 'item-1');
      expect(content, 'RAW');
      expect(
        f.adapter.calls.single.path,
        endsWith('/v1.0/drives/drive-1/items/item-1/content'),
      );
    });
  });
}

/// `sharepoint_upload_file` — PUT `drives/{driveId}/items/{folderId}:/{fileName}:/content`.
void uploadFileTests() {
  group('SharepointClient.uploadFile', () {
    test('PUTs the content and returns the decoded item object', () async {
      final f =
          mockSharepoint((o) => routeByPath({'/content': _uploadedBody}, o));
      final item = await f.client.uploadFile(
        'drive-1',
        'folder-1',
        'file.txt',
        'HELLO',
      );
      expect(item['id'], 'item-9');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/v1.0/drives/drive-1/items/folder-1:/file.txt:/content'),
      );
      expect(call.data, 'HELLO');
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'/content': '[1]'}, o));
      expect(
        await f.client.uploadFile('d1', 'f1', 'n.txt', 'x'),
        isEmpty,
      );
    });
  });
}

/// `sharepoint_create_folder` — POST `drives/{driveId}/items/{parentId}/children`.
void createFolderTests() {
  group('SharepointClient.createFolder', () {
    test('POSTs the folder payload and returns the decoded item', () async {
      final f =
          mockSharepoint((o) => routeByPath({'/children': _folderBody}, o));
      final folder =
          await f.client.createFolder('drive-1', 'root', 'New Folder');
      expect(folder['id'], 'item-10');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/v1.0/drives/drive-1/items/root/children'),
      );
      expect(
        jsonDecode(call.data as String),
        {
          'name': 'New Folder',
          'folder': {},
          '@microsoft.graph.conflictBehavior': 'fail',
        },
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'/children': '[1]'}, o));
      expect(
        await f.client.createFolder('d1', 'root', 'x'),
        isEmpty,
      );
    });
  });
}

/// `sharepoint_get_drive_items` — GET `drives/{driveId}/items/{folderId}/children`.
void getDriveItemsTests() {
  group('SharepointClient.getDriveItems', () {
    test('returns the decoded items object', () async {
      final f =
          mockSharepoint((o) => routeByPath({'/children': _itemsBody}, o));
      final items = await f.client.getDriveItems('drive-1', 'folder-1');
      expect(items['value'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v1.0/drives/drive-1/items/folder-1/children'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint((o) => routeByPath({'/children': '[1]'}, o));
      expect(await f.client.getDriveItems('drive-1', 'folder-1'), isEmpty);
    });
  });
}

/// `sharepoint_search_drive` — GET `drives/{driveId}/root/search(q='{query}')`.
void searchDriveTests() {
  group('SharepointClient.searchDrive', () {
    test('returns the decoded search results', () async {
      final f = mockSharepoint(
        (o) => routeByPath({"search(q='report')": _searchBody}, o),
      );
      final results = await f.client.searchDrive('drive-1', 'report');
      expect(results['value'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith("/v1.0/drives/drive-1/root/search(q='report')"),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockSharepoint(
        (o) => routeByPath({"search(q='report')": '[1]'}, o),
      );
      expect(await f.client.searchDrive('drive-1', 'report'), isEmpty);
    });
  });
}

/// `sharepoint_delete_drive_item` — DELETE `drives/{driveId}/items/{itemId}`.
void deleteDriveItemTests() {
  group('SharepointClient.deleteDriveItem', () {
    test('DELETEs the item and returns success', () async {
      final f = mockSharepoint((o) => '');
      final result = await f.client.deleteDriveItem('drive-1', 'item-1');
      expect(result['success'], isTrue);
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(
        call.path,
        endsWith('/v1.0/drives/drive-1/items/item-1'),
      );
    });
  });
}

/// `sharepoint_copy_item` — POST `drives/{srcDriveId}/items/{srcItemId}/copy`.
void copyItemTests() {
  group('SharepointClient.copyItem', () {
    test('POSTs the copy payload and returns success', () async {
      final f = mockSharepoint((o) => '');
      final result = await f.client.copyItem(
        'drive-1',
        'item-1',
        'drive-2',
        'folder-2',
      );
      expect(result['success'], isTrue);
      expect(result['message'], contains('item-1'));
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/v1.0/drives/drive-1/items/item-1/copy'),
      );
      expect(
        jsonDecode(call.data as String),
        {
          'parentReference': {'driveId': 'drive-2', 'id': 'folder-2'},
        },
      );
    });
  });
}

/// Canned `me/drive` response body (the default drive object).
const _driveBody = '{"id":"drive-1","name":"MyDrive","driveType":"personal"}';

/// Canned files response body.
const _filesBody =
    '{"value":[{"id":"f1","name":"a.txt"},{"id":"f2","name":"b.txt"}]}';

/// Canned drive-items response body.
const _itemsBody =
    '{"value":[{"id":"i1","name":"doc.docx"},{"id":"i2","name":"sub"}]}';

/// Canned search-results response body.
const _searchBody =
    '{"value":[{"id":"s1","name":"report.xlsx"},{"id":"s2","name":"report.pdf"}]}';

/// Canned upload-file response body.
const _uploadedBody = '{"id":"item-9","name":"file.txt"}';

/// Canned create-folder response body.
const _folderBody = '{"id":"item-10","name":"New Folder","folder":{}}';

/// Canned `sites/root` response body.
const _siteBody = '{"id":"site-1","displayName":"Root Site","name":"root"}';

/// Canned sites search response body.
const _sitesBody = '{"value":[{"id":"s1","displayName":"Project A"},'
    '{"id":"s2","displayName":"Project B"}]}';
