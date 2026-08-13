import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'sharepoint_test_support.dart';

/// Coverage + behavior tests for [SharepointClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  testConnectionTests();
  getDriveTests();
  listFilesTests();
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

/// Canned `me/drive` response body (the default drive object).
const _driveBody = '{"id":"drive-1","name":"MyDrive","driveType":"personal"}';

/// Canned files response body.
const _filesBody =
    '{"value":[{"id":"f1","name":"a.txt"},{"id":"f2","name":"b.txt"}]}';
