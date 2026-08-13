import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'sharepoint_test_support.dart';

/// Coverage + behavior tests for [SharepointClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  testConnectionTests();
  getDriveTests();
  listFilesTests();
  getFileTests();
  uploadFileTests();
  createFolderTests();
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

/// Canned `me/drive` response body (the default drive object).
const _driveBody = '{"id":"drive-1","name":"MyDrive","driveType":"personal"}';

/// Canned files response body.
const _filesBody =
    '{"value":[{"id":"f1","name":"a.txt"},{"id":"f2","name":"b.txt"}]}';

/// Canned upload-file response body.
const _uploadedBody = '{"id":"item-9","name":"file.txt"}';

/// Canned create-folder response body.
const _folderBody = '{"id":"item-10","name":"New Folder","folder":{}}';
