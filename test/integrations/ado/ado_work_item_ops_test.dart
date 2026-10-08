import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Async-client (CLI path) tests for the dm.ai #661 ticket operations.
void main() {
  tearDown(PropertyReader.clearOverrides);
  _fieldUpdateTests();
  _linkCreateTests();
  _fieldCodeTests();
  _attachTests();
}

String router(RequestOptions o) => routeByPath({
      '/wit/fields': jsonEncode({
        'value': [
          {'name': 'Solution Design', 'referenceName': 'Custom.SD'},
        ],
      }),
      '/wit/attachments': jsonEncode({'id': 'a', 'url': 'http://x/a'}),
      '/workitems/\$Task': jsonEncode({'id': 321}),
    }, o);

List patchBody(dynamic data) => jsonDecode(data as String) as List;

void _fieldUpdateTests() {
  group('field updates via the executor', () {
    test('ado_update_field maps names and PATCHes json-patch', () async {
      final f = mockAdo(router);
      final ex = AdoToolExecutor(f.client);
      await ex.execute(
          'ado_update_field', {'id': 5, 'field': 'summary', 'value': 'N'});
      final c = f.adapter.calls.single;
      expect(c.method, 'PATCH');
      expect(c.path, endsWith('/wit/workitems/5'));
      expect(c.headers['Content-Type'], 'application/json-patch+json');
      expect(patchBody(c.data), [
        {'op': 'add', 'path': '/fields/System.Title', 'value': 'N'}
      ]);
    });

    test('state/assign/description/tags/priority tools', () async {
      final f = mockAdo(router);
      final ex = AdoToolExecutor(f.client);
      await ex.execute('ado_move_to_state', {'id': 1, 'state': 'Done'});
      await ex.execute('ado_assign_work_item', {'id': 1, 'userEmail': 'a@b'});
      await ex.execute('ado_update_description', {'id': 1, 'description': 'd'});
      await ex.execute('ado_update_tags', {'id': 1, 'tags': 'a;b'});
      await ex.execute('ado_set_priority', {'id': 1, 'priority': 'High'});
      final fields = [
        for (final c in f.adapter.calls) (patchBody(c.data).single as Map)
      ].map((m) => '${m['path']}=${m['value']}');
      expect(fields, [
        '/fields/System.State=Done',
        '/fields/System.AssignedTo=a@b',
        '/fields/System.Description=d',
        '/fields/System.Tags=a;b',
        '/fields/Microsoft.VSTS.Common.Priority=2',
      ]);
    });

    test('ado_set_priority rejects unknown names', () {
      final ex = AdoToolExecutor(mockAdo(router).client);
      expect(
          () => ex.execute('ado_set_priority', {'id': 1, 'priority': 'zzz'}),
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, 'message', startsWith('Unknown pri'))));
    });
  });
}

void _linkCreateTests() {
  group('links, create, field code', () {
    test('ado_link_work_items maps the relationship', () async {
      final f = mockAdo(router);
      await AdoToolExecutor(f.client).execute('ado_link_work_items',
          {'sourceId': 1, 'targetId': '2', 'relationship': 'blocked by'});
      final op = patchBody(f.adapter.calls.single.data).single as Map;
      expect(op['value']['rel'], 'System.LinkTypes.Dependency-Reverse');
      expect(op['value']['url'], endsWith('/contoso/_apis/wit/workItems/2'));
    });

    test('ado_create_work_item with parentId links parent -> child', () async {
      final f = mockAdo(router);
      final out =
          await AdoToolExecutor(f.client).execute('ado_create_work_item', {
        'project': 'dmtools',
        'workItemType': 'Task',
        'title': 'T',
        'description': 'd',
        'fieldsJson': '{"Custom.X": 1}',
        'parentId': 9
      });
      expect((out as Map)['id'], 321);
      final calls = f.adapter.calls;
      expect(calls, hasLength(2));
      expect(calls[0].path, endsWith('/dmtools/_apis/wit/workitems/\$Task'));
      expect(patchBody(calls[0].data).map((o) => o['path']), [
        '/fields/System.Title',
        '/fields/System.Description',
        '/fields/Custom.X'
      ]);
      expect(calls[1].path, endsWith('/wit/workitems/9'));
      expect((patchBody(calls[1].data).single as Map)['value']['rel'],
          'System.LinkTypes.Hierarchy-Forward');
    });

    test('create without id in the response fails when a parent is given', () {
      final f = mockAdo((_) => '{}');
      expect(
          () => f.client.workItemOps.createWorkItem(
              project: '', workItemType: 'Task', title: 't', parentId: 1),
          throwsStateError);
    });
  });
}

void _fieldCodeTests() {
  group('ado_get_field_code', () {
    test('hit, miss and blank', () async {
      final f = mockAdo(router);
      final ex = AdoToolExecutor(f.client);
      expect(
          await ex
              .execute('ado_get_field_code', {'fieldName': 'solution design'}),
          'Custom.SD');
      expect(
          f.adapter.calls.single.path, endsWith('/dmtools/_apis/wit/fields'));
      expect(
          await ex.execute(
              'ado_get_field_code', {'project': 'P', 'fieldName': 'nope'}),
          isNull);
      expect(f.adapter.calls.last.path, endsWith('/P/_apis/wit/fields'));
      expect(
          await ex.execute('ado_get_field_code', {'fieldName': ' '}), isNull);
      expect(f.adapter.calls, hasLength(2));
    });
  });
}

void _attachTests() {
  group('ado_attach_file', () {
    late File file;
    setUp(() {
      final dir = Directory.systemTemp.createTempSync('ado_async_');
      addTearDown(() => dir.deleteSync(recursive: true));
      file = File('${dir.path}/r.png')..writeAsStringSync('bytes');
    });

    test('upload then link (3 requests)', () async {
      final f = mockAdo(
          (o) => o.method == 'GET' ? '{"id":4,"relations":[]}' : router(o));
      final out = await AdoToolExecutor(f.client).execute(
          'ado_attach_file', {'id': 4, 'name': 'r.png', 'filePath': file.path});
      expect(out, {'status': 'success', 'id': '4', 'name': 'r.png'});
      final calls = f.adapter.calls;
      expect(calls.map((c) => c.method), ['GET', 'POST', 'PATCH']);
      expect(calls[1].queryParameters['fileName'], 'r.png');
      expect(calls[1].headers['Content-Type'], 'application/octet-stream');
      final op = patchBody(calls[2].data).single as Map;
      expect(op['value'], {
        'rel': 'AttachedFile',
        'url': 'http://x/a',
        'attributes': {'name': 'r.png'},
      });
    });

    test('same-named attachment is a no-op', () async {
      final f = mockAdo((_) => jsonEncode({
            'relations': [
              {
                'rel': 'AttachedFile',
                'attributes': {'name': 'R.PNG'}
              }
            ]
          }));
      await AdoToolExecutor(f.client).execute(
          'ado_attach_file', {'id': 4, 'name': 'r.png', 'filePath': file.path});
      expect(f.adapter.calls, hasLength(1));
    });

    test('missing file and missing upload url fail', () async {
      final f = mockAdo((o) => o.method == 'GET' ? '{}' : '{}');
      final ex = AdoToolExecutor(f.client);
      await expectLater(
          ex.execute('ado_attach_file',
              {'id': 4, 'name': 'r', 'filePath': '/no/such'}),
          throwsA(isA<FileSystemException>()));
      expect(f.adapter.calls, isEmpty);
      await expectLater(
          ex.execute(
              'ado_attach_file', {'id': 4, 'name': 'r', 'filePath': file.path}),
          throwsStateError);
    });
  });
}
