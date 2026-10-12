import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/ado_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

late EchoServer server;
const tools = AdoSyncTools();

Map<String, dynamic> call(String tool, Map<String, dynamic> args) =>
    jsonDecode(tools.handlers[tool]!(args)) as Map<String, dynamic>;

Future<List<Map<String, dynamic>>> fullLog() async {
  final client = HttpClient();
  try {
    final request = await client.get('127.0.0.1', server.port, '/__full_log');
    final text = await utf8.decoder.bind(await request.close()).join();
    return (jsonDecode(text) as List).cast<Map<String, dynamic>>();
  } finally {
    client.close();
  }
}

List<dynamic> patchOf(Map<String, dynamic> body) =>
    jsonDecode(body['body'] as String) as List;

File tempFile(String name) {
  final dir = Directory.systemTemp.createTempSync('ado_ops_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/$name')..writeAsStringSync('bytes');
}

/// Echo-server tests for the dm.ai #661 ADO ticket operations.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  if (!hasPython3()) return;
  setUp(() async {
    server = EchoServer();
    await server.start();
    PropertyReader.setOverrides({
      'ADO_BASE_PATH': 'http://127.0.0.1:${server.port}',
      'ADO_ORGANIZATION': 'org',
      'ADO_PROJECT': 'proj',
      'ADO_PAT_TOKEN': 'pat-token',
    });
  });
  tearDown(() {
    PropertyReader.clearOverrides();
    server.stop();
  });

  _commentTests();
  _simpleFieldTests();
  _fieldMappingTests();
  _priorityTests();
  _linkTests();
  _createTests();
  _createParentTests();
  _fieldCodeTests();
  _attachTests();
}

/// Wire shape of a PATCH echo: method, path, content type and patch ops.
Map<String, Object?> wire(Map<String, dynamic> echo) => {
      'method': echo['method'],
      'path': echo['path'],
      'type': echo['headers']['Content-Type'],
      'patch': patchOf(echo),
    };

/// Expected [wire] of a work-item PATCH of [id] applying [ops].
Map<String, Object?> patched(String id, List ops) => {
      'method': 'PATCH',
      'path': '/org/proj/_apis/wit/workitems/$id?api-version=7.0',
      'type': 'application/json-patch+json',
      'patch': ops,
    };

List<Map<String, Object>> _setOp(String field, Object value) => [
      {'op': 'add', 'path': '/fields/$field', 'value': value}
    ];

void _commentTests() {
  group('comments', () {
    test('add comment accepts `comment` and the `text` alias', () {
      for (final key in ['comment', 'text']) {
        final echo = call('ado_add_work_item_comment', {'id': 5, key: 'hi'});
        expect(echo['method'], 'POST');
        expect(echo['path'],
            '/org/proj/_apis/wit/workItems/5/comments?api-version=7.0-preview');
        expect(jsonDecode(echo['body'] as String), {'text': 'hi'});
      }
    });

    test('get comments GETs the comments endpoint', () {
      final echo = call('ado_get_work_item_comments', {'id': 5});
      expect(echo['method'], 'GET');
      expect(echo['path'],
          '/org/proj/_apis/wit/workItems/5/comments?api-version=7.0-preview');
    });
  });
}

void _simpleFieldTests() {
  group('simple field tools', () {
    test('move_to_state sets System.State (statusName/key aliases)', () {
      expect(wire(call('ado_move_to_state', {'id': 4, 'state': 'Active'})),
          patched('4', _setOp('System.State', 'Active')));
      expect(
          wire(call('ado_move_to_state', {'key': '4', 'statusName': 'Done'})),
          patched('4', _setOp('System.State', 'Done')));
    });

    test('assign sets System.AssignedTo (userEmail/accountId)', () {
      expect(wire(call('ado_assign_work_item', {'id': 4, 'userEmail': 'a@b'})),
          patched('4', _setOp('System.AssignedTo', 'a@b')));
      expect(wire(call('ado_assign_work_item', {'id': 4, 'accountId': 'c@d'})),
          patched('4', _setOp('System.AssignedTo', 'c@d')));
    });

    test('update_description and update_tags', () {
      expect(
          wire(call(
              'ado_update_description', {'id': 4, 'description': '<p>x</p>'})),
          patched('4', _setOp('System.Description', '<p>x</p>')));
      expect(wire(call('ado_update_tags', {'id': 4, 'tags': 'a;b'})),
          patched('4', _setOp('System.Tags', 'a;b')));
    });
  });
}

void _fieldMappingTests() {
  group('ado_update_field name mapping', () {
    const table = {
      'summary': 'System.Title',
      'Title': 'System.Title',
      'description': 'System.Description',
      'state': 'System.State',
      'assignedTo': 'System.AssignedTo',
      'priority': 'Microsoft.VSTS.Common.Priority',
      'tags': 'System.Tags',
      'areaPath': 'System.AreaPath',
      'iterationPath': 'System.IterationPath',
      'storyPoints': 'Microsoft.VSTS.Scheduling.StoryPoints',
      'effort': 'Microsoft.VSTS.Scheduling.Effort',
      'id': 'System.Id',
      'Custom.SolutionDesign': 'Custom.SolutionDesign',
      'unknownThing': 'unknownThing',
    };
    table.forEach((input, ref) {
      test('$input -> $ref', () {
        expect(
            wire(call(
                'ado_update_field', {'id': 3, 'field': input, 'value': 'v'})),
            patched('3', _setOp(ref, 'v')));
      });
    });
  });
}

void _priorityTests() {
  group('ado_set_priority', () {
    test('names and numbers map to a numeric patch value', () {
      const cases = {
        '1': 1,
        ' Blocker ': 1,
        'HIGH': 2,
        'major': 2,
        'Medium': 3,
        'normal': 3,
        'trivial': 4,
        'lowest': 4,
        '4': 4,
      };
      cases.forEach((input, number) {
        expect(wire(call('ado_set_priority', {'id': 8, 'priority': input})),
            patched('8', _setOp('Microsoft.VSTS.Common.Priority', number)));
      });
    });

    test('unknown priority errors without a request', () async {
      final result = call('ado_set_priority', {'id': 8, 'priority': 'urgent'});
      expect(result['error'], startsWith("Unknown priority 'urgent'. Use 1-4"));
      expect(result['error'], contains('Trivial'));
      expect(await fullLog(), isEmpty);
    });

    test('blank priority errors', () {
      expect(call('ado_set_priority', {'id': 8})['error'],
          'Priority must not be empty');
    });
  });
}

void _linkTests() {
  group('ado_link_work_items', () {
    const rels = {
      'parent': 'System.LinkTypes.Hierarchy-Reverse',
      'child': 'System.LinkTypes.Hierarchy-Forward',
      'blocks': 'System.LinkTypes.Dependency-Forward',
      'Blocked By': 'System.LinkTypes.Dependency-Reverse',
      'tested by': 'Microsoft.VSTS.Common.TestedBy-Forward',
      'tests': 'Microsoft.VSTS.Common.TestedBy-Forward',
      'related': 'System.LinkTypes.Related',
      'whatever': 'System.LinkTypes.Related',
      'System.LinkTypes.Hierarchy-Forward':
          'System.LinkTypes.Hierarchy-Forward',
    };
    rels.forEach((input, rel) {
      test('$input -> $rel', () {
        final echo = call('ado_link_work_items',
            {'sourceId': 1, 'targetId': 2, 'relationship': input});
        expect(
            wire(echo),
            patched('1', [
              {
                'op': 'add',
                'path': '/relations/-',
                'value': {
                  'rel': rel,
                  'url':
                      'http://127.0.0.1:${server.port}/org/_apis/wit/workItems/2'
                },
              }
            ]));
      });
    });

    test('sourceKey/anotherKey aliases are accepted', () {
      final echo = call('ado_link_work_items',
          {'sourceKey': '1', 'anotherKey': '2', 'relationship': 'related'});
      expect(echo['path'], contains('/wit/workitems/1?'));
      expect(patchOf(echo).single['value']['url'], endsWith('/workItems/2'));
    });
  });
}

void _createTests() {
  group('ado_create_work_item', () {
    test('POSTs a JSON-Patch with title, description and extra fields',
        () async {
      final echo = call('ado_create_work_item', {
        'project': 'Other',
        'workItemType': 'User Story',
        'title': 'T',
        'description': '<p>d</p>',
        'fieldsJson': {
          'Microsoft.VSTS.Common.Priority': 1,
          'System.Title': 'skipped',
          'System.WorkItemType': 'skipped',
        },
      });
      expect(echo['method'], 'POST');
      expect(
          echo['path'],
          '/org/Other/_apis/wit/workitems/\$User Story?api-version=7.0'
              .replaceAll(' ', '%20'));
      expect(echo['headers']['Content-Type'], 'application/json-patch+json');
      expect(patchOf(echo), [
        {'op': 'add', 'path': '/fields/System.Title', 'value': 'T'},
        {
          'op': 'add',
          'path': '/fields/System.Description',
          'value': '<p>d</p>'
        },
        {
          'op': 'add',
          'path': '/fields/Microsoft.VSTS.Common.Priority',
          'value': 1
        },
      ]);
      expect((await fullLog()).length, 1, reason: 'no parent => one request');
    });

    test('aliases issueType/summary and fieldsJson as a JSON string', () {
      final echo = call('ado_create_work_item', {
        'project': 'proj',
        'issueType': 'Bug',
        'summary': 'S',
        'fieldsJson': '{"Custom.X":"y"}',
      });
      expect(
          echo['path'], '/org/proj/_apis/wit/workitems/\$Bug?api-version=7.0');
      expect(patchOf(echo).last['path'], '/fields/Custom.X');
    });
  });
}

void _createParentTests() {
  group('ado_create_work_item parent link', () {
    test(
        'parentId links the new item as child via Hierarchy-Forward on the '
        'parent', () async {
      call('ado_create_work_item', {
        'project': 'proj',
        'workItemType': 'Task',
        'title': 'T',
        'parentId': '77',
      });
      final log = await fullLog();
      expect(log, hasLength(2));
      expect(log[0]['method'], 'POST');
      expect(log[1]['method'], 'PATCH');
      expect(
          log[1]['path'], '/org/proj/_apis/wit/workitems/77?api-version=7.0');
      final op = patchOf(log[1]).single as Map;
      expect(op['value']['rel'], 'System.LinkTypes.Hierarchy-Forward');
      expect(op['value']['url'], endsWith('/_apis/wit/workItems/321'));
    });

    test('non-object fieldsJson is rejected before any request', () async {
      final r = call('ado_create_work_item', {
        'project': 'p',
        'workItemType': 'Bug',
        'title': 't',
        'fieldsJson': '[1]'
      });
      expect(r['error'], 'fieldsJson must be a JSON object');
      expect(await fullLog(), isEmpty);
    });
  });
}

void _fieldCodeTests() {
  group('ado_get_field_code', () {
    test('matches name or referenceName case-insensitively', () {
      for (final input in ['solution design', 'Custom.SolutionDesign']) {
        final out = tools.handlers['ado_get_field_code']!(
            {'project': 'Other', 'fieldName': input});
        expect(jsonDecode(out), 'Custom.SolutionDesign');
      }
    });

    test('requests {org}/{project}/_apis/wit/fields', () async {
      tools.handlers['ado_get_field_code']!({'fieldName': 'Title'});
      final log = await fullLog();
      expect(log.single['method'], 'GET');
      expect(log.single['path'], '/org/proj/_apis/wit/fields?api-version=7.0');
    });

    test('unknown or blank names yield null', () async {
      expect(
          tools.handlers['ado_get_field_code']!({'fieldName': 'Nope'}), 'null');
      expect(
          tools.handlers['ado_get_field_code']!({'fieldName': '  '}), 'null');
      expect((await fullLog()).length, 1, reason: 'blank name: no request');
    });
  });
}

void _attachTests() {
  group('ado_attach_file', () {
    test('uploads, then links an AttachedFile relation (3 steps)', () async {
      final file = tempFile('report.png');
      final out = call('ado_attach_file', {
        'id': 9,
        'name': 'report.png',
        'filePath': file.path,
      });
      expect(out, {'status': 'success', 'id': '9', 'name': 'report.png'});
      final log = await fullLog();
      expect(log.map((e) => e['method']), ['GET', 'POST', 'PATCH']);
      expect(log[0]['path'], contains('/wit/workitems/9?'));
      expect(log[1]['path'],
          '/org/proj/_apis/wit/attachments?fileName=report.png&api-version=7.0');
      expect(log[1]['body'], 'bytes');
      expect(log[1]['headers']['Content-Type'], 'application/octet-stream');
      expect(log[2]['path'], '/org/proj/_apis/wit/workitems/9?api-version=7.0');
      expect(jsonDecode(log[2]['body'] as String), [
        {
          'op': 'add',
          'path': '/relations/-',
          'value': {
            'rel': 'AttachedFile',
            'url': 'http://ado.example/_apis/wit/attachments/att-1',
            'attributes': {'name': 'report.png'},
          },
        }
      ]);
    });

    test('is a no-op success when a same-named attachment exists', () async {
      final file = tempFile('shot.png');
      final out = call('ado_attach_file', {
        'id': 55,
        'name': 'shot.png',
        'filePath': file.path,
      });
      expect(out, {'status': 'success', 'id': '55', 'name': 'shot.png'});
      expect((await fullLog()).map((e) => e['method']), ['GET']);
    });

    test('missing file errors before any request', () async {
      final out = call('ado_attach_file',
          {'id': 9, 'name': 'x', 'filePath': '/nonexistent/x.bin'});
      expect(out['error'], 'File does not exist: /nonexistent/x.bin');
      expect(await fullLog(), isEmpty);
    });
  });
}
