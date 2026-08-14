import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Work-item tests: the `wit/workitems` client methods, tool-catalog
/// shape, and executor routing (update/get/list, types, revisions,
/// comments, links).
void main() {
  tearDown(PropertyReader.clearOverrides);
  updateWorkItemTests();
  getWorkItemsTests();
  listWorkItemsTests();
  getWorkItemTypesTests();
  getWorkItemRevisionsTests();
  getWorkItemCommentsTests();
  addWorkItemCommentTests();
  createWorkItemLinkTests();
  workItemCatalogRegistrationTests();
  workItemCatalogParamShapeTests();
  workItemUpdateExecutorTests();
  workItemReadExecutorTests();
  workItemWriteExecutorTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned updated work item.
const _updatedItem = '{"id":42,"rev":3}';

/// Canned work-item array.
const _itemArray = '[{"id":1},{"id":2}]';

/// Canned work-item-type array.
const _typeArray = '[{"name":"Bug"},{"name":"Task"}]';

/// Canned revision array.
const _revArray = '[{"rev":1},{"rev":2}]';

/// Canned comment array.
const _commentArray = '[{"id":1,"text":"looks good"}]';

/// Canned created comment object.
const _comment = '{"id":1,"text":"nice"}';

/// Canned created link object.
const _link = '{"id":1,"rev":2}';

/// `ado_update_work_item` — PATCH with JSON-Patch field ops.
void updateWorkItemTests() {
  group('AdoClient.updateWorkItem', () {
    test('PATCHes one add-op per field with the json-patch content type',
        () async {
      final f = mockAdo((o) => routeByPath({'/workitems/42': _updatedItem}, o));
      final result = await f.client.updateWorkItem(
        42,
        <String, dynamic>{'System.Title': 'New', 'System.State': 'Active'},
      );
      expect(result['rev'], 3);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/contoso/dmtools/_apis/wit/workitems/42'));
      expect(call.headers['Content-Type'], 'application/json-patch+json');
      final ops = jsonDecode(call.data as String) as List;
      expect(ops, [
        {'op': 'add', 'path': '/fields/System.Title', 'value': 'New'},
        {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
      ]);
    });
  });
}

/// `ado_get_work_items` — GET `wit/workitems?ids=`.
void getWorkItemsTests() {
  group('AdoClient.getWorkItems', () {
    test('GETs the ids query and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/workitems': _itemArray}, o));
      final items = await f.client.getWorkItems([1, 2]);
      expect(items.map((i) => i['id']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.queryParameters['ids'], '1,2');
      expect(call.queryParameters['api-version'], '7.0');
    });
  });
}

/// `ado_list_work_items` — POST `wit/wiql`.
void listWorkItemsTests() {
  group('AdoClient.listWorkItems', () {
    test('POSTs the WIQL query body and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/wiql': _itemArray}, o));
      final items = await f.client.listWorkItems('Select [System.Id]');
      expect(items.map((i) => i['id']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/contoso/dmtools/_apis/wit/wiql'));
      expect(jsonDecode(call.data as String), {'query': 'Select [System.Id]'});
    });
  });
}

/// `ado_get_work_item_types` — GET `wit/workitemtypes`.
void getWorkItemTypesTests() {
  group('AdoClient.getWorkItemTypes', () {
    test('GETs workitemtypes and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/workitemtypes': _typeArray}, o));
      final types = await f.client.getWorkItemTypes(_project);
      expect(types.map((t) => t['name']).toList(), ['Bug', 'Task']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/dmtools/_apis/wit/workitemtypes'));
    });
  });
}

/// `ado_get_work_item_revisions` — GET `wit/workitems/{id}/revisions`.
void getWorkItemRevisionsTests() {
  group('AdoClient.getWorkItemRevisions', () {
    test('GETs revisions and decodes the list', () async {
      final f = mockAdo(
        (o) => routeByPath({'/workitems/42/revisions': _revArray}, o),
      );
      final revs = await f.client.getWorkItemRevisions(42);
      expect(revs.map((r) => r['rev']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/wit/workitems/42/revisions'),
      );
    });
  });
}

/// `ado_get_work_item_comments` — GET `wit/workitems/{id}/comments`.
void getWorkItemCommentsTests() {
  group('AdoClient.getWorkItemComments', () {
    test('GETs comments and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/comments': _commentArray}, o));
      final comments = await f.client.getWorkItemComments(42);
      expect(comments.single['text'], 'looks good');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/wit/workitems/42/comments'),
      );
    });
  });
}

/// `ado_add_work_item_comment` — POST `wit/workitems/{id}/comments`.
void addWorkItemCommentTests() {
  group('AdoClient.addWorkItemComment', () {
    test('POSTs a comment and decodes the object', () async {
      final f = mockAdo((o) => o.method == 'POST' ? _comment : '[]');
      final result = await f.client.addWorkItemComment(42, 'nice');
      expect(result['text'], 'nice');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/wit/workitems/42/comments'),
      );
      expect(jsonDecode(call.data as String), {'text': 'nice'});
    });
  });
}

/// `ado_create_work_item_link` — POST `wit/workitems/{sourceId}/links`.
void createWorkItemLinkTests() {
  group('AdoClient.createWorkItemLink', () {
    test('POSTs a JSON-Patch relation add and decodes the object', () async {
      const linkType = 'System.LinkTypes.Hierarchy-Forward';
      final f = mockAdo((o) => o.method == 'POST' ? _link : '{}');
      final result = await f.client.createWorkItemLink(1, 2, linkType);
      expect(result['id'], 1);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.headers['Content-Type'], 'application/json-patch+json');
      expect(
          call.path, endsWith('/contoso/dmtools/_apis/wit/workitems/1/links'));
      final sent = jsonDecode(call.data as String) as List<dynamic>;
      expect(sent.single['op'], 'add');
      expect(sent.single['path'], '/relations/-');
      final value = sent.single['value'] as Map<String, dynamic>;
      expect(value['rel'], linkType);
      expect(value['url'], endsWith('/_apis/wit/workitems/2'));
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-catalog registration for the work-item tools.
void workItemCatalogRegistrationTests() {
  group('adoTools catalog (work items)', () {
    test('registers all eight work-item tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_update_work_item',
        'ado_get_work_item_revisions',
        'ado_create_work_item_link',
        'ado_get_work_items',
        'ado_list_work_items',
        'ado_get_work_item_types',
        'ado_get_work_item_comments',
        'ado_add_work_item_comment',
      ]) {
        expect(names, contains(name));
      }
    });
  });
}

/// Tool-catalog parameter shapes for the work-item tools.
void workItemCatalogParamShapeTests() {
  group('adoTools catalog (work items)', () {
    test('ado_update_work_item declares id and fields', () {
      final tool = toolNamed('ado_update_work_item');
      expect(tool.params.map((p) => p.name), ['id', 'fields']);
      expect(tool.params.first.type, 'number');
      expect(tool.params.last.type, 'object');
    });

    test('ado_get_work_items declares a required ids array', () {
      final tool = toolNamed('ado_get_work_items');
      expect(tool.params.single.name, 'ids');
      expect(tool.params.single.type, 'array');
    });

    test('ado_list_work_items declares a required wiql string', () {
      final tool = toolNamed('ado_list_work_items');
      expect(tool.params.single.name, 'wiql');
    });

    test('ado_get_work_item_revisions declares a numeric id', () {
      final tool = toolNamed('ado_get_work_item_revisions');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.type, 'number');
    });

    test('ado_get_work_item_comments declares a numeric id', () {
      final tool = toolNamed('ado_get_work_item_comments');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.type, 'number');
    });

    test('ado_add_work_item_comment declares id and text', () {
      final tool = toolNamed('ado_add_work_item_comment');
      expect(tool.params.map((p) => p.name), ['id', 'text']);
    });

    test('ado_create_work_item_link declares numeric ids and linkType', () {
      final tool = toolNamed('ado_create_work_item_link');
      expect(
        tool.params.map((p) => p.name),
        ['sourceId', 'targetId', 'linkType'],
      );
      expect(tool.params[0].type, 'number');
      expect(tool.params[1].type, 'number');
    });
  });
}

/// Serves `[]` for the list GETs and `{}` for mutations; the WIQL search
/// is a POST that answers a list.
String _workItemRouter(RequestOptions o) {
  if (o.path.endsWith('/wiql')) return _itemArray;
  return o.method == 'GET' ? '[]' : '{}';
}

/// [AdoToolExecutor.execute] routing for the update tool.
void workItemUpdateExecutorTests() {
  late _WorkItemFixture f;

  group('AdoToolExecutor.execute (work items)', () {
    setUp(() => f = _workItemFixture());

    test('routes ado_update_work_item with id and fields', () async {
      await f.executor.execute('ado_update_work_item', {
        'id': 42,
        'fields': <String, dynamic>{'System.Title': 'New'},
      });
      expect(f.spy.calls.single, 'updateWorkItem:42:System.Title=New');
    });
  });
}

/// [AdoToolExecutor.execute] routing for the read tools.
void workItemReadExecutorTests() {
  late _WorkItemFixture f;

  group('AdoToolExecutor.execute (work items)', () {
    setUp(() => f = _workItemFixture());

    test('routes ado_get_work_items with an int list', () async {
      await f.executor.execute('ado_get_work_items', {
        'ids': [1, 2]
      });
      expect(f.spy.calls.single, 'getWorkItems:1,2');
    });

    test('routes ado_list_work_items with the wiql query', () async {
      await f.executor.execute('ado_list_work_items', {'wiql': 'Select [Id]'});
      expect(f.spy.calls.single, 'listWorkItems:Select [Id]');
    });

    test('routes ado_get_work_item_types with the project', () async {
      await f.executor.execute('ado_get_work_item_types', {'project': 'p'});
      expect(f.spy.calls.single, 'getWorkItemTypes:p');
    });

    test('routes ado_get_work_item_revisions with id', () async {
      await f.executor.execute('ado_get_work_item_revisions', {'id': 42});
      expect(f.spy.calls.single, 'getWorkItemRevisions:42');
    });

    test('routes ado_get_work_item_comments with id', () async {
      await f.executor.execute('ado_get_work_item_comments', {'id': 42});
      expect(f.spy.calls.single, 'getWorkItemComments:42');
    });
  });
}

/// [AdoToolExecutor.execute] routing for the comment and link tools.
void workItemWriteExecutorTests() {
  late _WorkItemFixture f;

  group('AdoToolExecutor.execute (work items)', () {
    setUp(() => f = _workItemFixture());

    test('routes ado_add_work_item_comment with id and text', () async {
      await f.executor
          .execute('ado_add_work_item_comment', {'id': 42, 'text': 'nice'});
      expect(f.spy.calls.single, 'addWorkItemComment:42:nice');
    });

    test('routes ado_create_work_item_link with numeric ids', () async {
      await f.executor.execute('ado_create_work_item_link', {
        'sourceId': 1,
        'targetId': 2,
        'linkType': 'rel',
      });
      expect(f.spy.calls.single, 'createWorkItemLink:1:2:rel');
    });

    test('parses numeric-string ids on create_work_item_link', () async {
      await f.executor.execute('ado_create_work_item_link', {
        'sourceId': '1',
        'targetId': '2',
        'linkType': 'rel',
      });
      expect(f.spy.calls.single, 'createWorkItemLink:1:2:rel');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _WorkItemFixture = ({AdoToolExecutor executor, _WorkItemSpy spy});

/// Builds a [_WorkItemSpy] over the mocked transport and wraps it.
_WorkItemFixture _workItemFixture() {
  final spy = _WorkItemSpy(mockAdoHttp(_workItemRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched work-item call then delegates to the real client.
class _WorkItemSpy extends AdoClient {
  _WorkItemSpy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> updateWorkItem(
    int id,
    Map<String, dynamic> fields,
  ) {
    final summary = fields.entries.map((e) => '${e.key}=${e.value}').join(',');
    calls.add('updateWorkItem:$id:$summary');
    return super.updateWorkItem(id, fields);
  }

  @override
  Future<List<Map<String, dynamic>>> getWorkItems(List<int> ids) {
    calls.add('getWorkItems:${ids.join(',')}');
    return super.getWorkItems(ids);
  }

  @override
  Future<List<Map<String, dynamic>>> listWorkItems(String wiql) {
    calls.add('listWorkItems:$wiql');
    return super.listWorkItems(wiql);
  }

  @override
  Future<List<Map<String, dynamic>>> getWorkItemTypes(String project) {
    calls.add('getWorkItemTypes:$project');
    return super.getWorkItemTypes(project);
  }

  @override
  Future<List<Map<String, dynamic>>> getWorkItemRevisions(int id) {
    calls.add('getWorkItemRevisions:$id');
    return super.getWorkItemRevisions(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getWorkItemComments(int id) {
    calls.add('getWorkItemComments:$id');
    return super.getWorkItemComments(id);
  }

  @override
  Future<Map<String, dynamic>> addWorkItemComment(int id, String text) {
    calls.add('addWorkItemComment:$id:$text');
    return super.addWorkItemComment(id, text);
  }

  @override
  Future<Map<String, dynamic>> createWorkItemLink(
    int sourceId,
    int targetId,
    String linkType,
  ) {
    calls.add('createWorkItemLink:$sourceId:$targetId:$linkType');
    return super.createWorkItemLink(sourceId, targetId, linkType);
  }
}
