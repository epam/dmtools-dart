import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Space coverage: list, get by key, update, get content, and create — plus
/// the matching tool definitions and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getSpacesTests();
  getSpaceByKeyTests();
  updateSpaceTests();
  getSpaceContentTests();
  createSpaceTests();
  spaceToolDefinitionTests();
  spaceExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_spaces` — GET `space`.
void getSpacesTests() {
  group('ConfluenceClient.getSpaces', () {
    test('returns the results array', () async {
      final f = mockConfluence((o) => routeByPath({'/space': _spacesBody}, o));
      final spaces = await f.client.getSpaces();
      expect(spaces, hasLength(2));
      expect(spaces[0]['key'], 'ENG');
      expect(spaces[1]['key'], 'OPS');
      expect(f.adapter.calls.single.path, endsWith('/space'));
    });
  });
}

/// `confluence_get_space_by_key` — GET `space/{spaceKey}`.
void getSpaceByKeyTests() {
  group('ConfluenceClient.getSpaceByKey', () {
    test('returns the space for the given key', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/space/ENG': _spaceByKeyBody}, o),
      );
      final space = await f.client.getSpaceByKey('ENG');
      expect(space['key'], 'ENG');
      expect(f.adapter.calls.single.path, endsWith('/space/ENG'));
    });
  });
}

/// `confluence_update_space` — PUT `space/{spaceKey}`.
void updateSpaceTests() {
  group('ConfluenceClient.updateSpace', () {
    test('PUTs name and description and returns the updated space', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/space/ENG': _spaceUpdatedBody}, o),
      );
      final result = await f.client.updateSpace('ENG', 'New Name', 'New desc');
      expect(result['name'], 'New Name');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/space/ENG'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['name'], 'New Name');
      final desc = sent['description']['plain'] as Map<String, dynamic>;
      expect(desc['value'], 'New desc');
      expect(desc['representation'], 'plain');
    });
  });
}

/// `confluence_get_space_content` — GET `space/{key}/content/{type}?depth=all`.
void getSpaceContentTests() {
  group('ConfluenceClient.getSpaceContent', () {
    test('returns the results array at depth all', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/page': _spaceContentBody}, o),
      );
      final pages = await f.client.getSpaceContent('ENG', 'page');
      expect(pages, hasLength(2));
      expect(pages[0]['title'], 'Home');
      expect(pages[1]['title'], 'Docs');
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/space/ENG/content/page'));
      expect(call.queryParameters['depth'], 'all');
    });
  });
}

/// `confluence_create_space` — POST `space`.
void createSpaceTests() {
  group('ConfluenceClient.createSpace', () {
    test('POSTs key and name and returns the created space', () async {
      final f =
          mockConfluence((o) => routeByPath({'/space': _createdSpaceBody}, o));
      final result = await f.client.createSpace('ENG', 'Engineering');
      expect(result['key'], 'ENG');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/space'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['key'], 'ENG');
      expect(sent['name'], 'Engineering');
    });
  });
}

/// Tool-definition shape for the space tools.
void spaceToolDefinitionTests() {
  group('confluence tool definitions (spaces)', () {
    test('confluence_get_spaces has no params', () {
      final tool = toolNamed('confluence_get_spaces');
      expect(tool.category, 'space');
      expect(tool.params, isEmpty);
    });

    test('confluence_get_space_by_key requires spaceKey', () {
      final tool = toolNamed('confluence_get_space_by_key');
      expect(tool.category, 'space');
      expect(tool.params.single.name, 'spaceKey');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_update_space requires spaceKey, name, description', () {
      final tool = toolNamed('confluence_update_space');
      expect(tool.category, 'space');
      expect(
          tool.params.map((p) => p.name), ['spaceKey', 'name', 'description']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('confluence_get_space_content requires spaceKey and type', () {
      final tool = toolNamed('confluence_get_space_content');
      expect(tool.category, 'space');
      expect(tool.params.map((p) => p.name), ['spaceKey', 'type']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('confluence_create_space requires key and name', () {
      final tool = toolNamed('confluence_create_space');
      expect(tool.category, 'space');
      expect(tool.params.map((p) => p.name), ['key', 'name']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each space tool name.
void spaceExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (spaces)', () {
    test('routes confluence_get_spaces', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_get_spaces', {});
      expect(f.client.calls, ['getSpaces']);
    });

    test('routes confluence_get_space_by_key', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_space_by_key',
        {'spaceKey': 'ENG'},
      );
      expect(f.client.calls, ['getSpaceByKey:ENG']);
    });

    test('routes confluence_update_space', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_update_space', {
        'spaceKey': 'ENG',
        'name': 'New',
        'description': 'Desc',
      });
      expect(f.client.calls, ['updateSpace:ENG:New:Desc']);
    });

    test('routes confluence_get_space_content', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_space_content',
        {'spaceKey': 'ENG', 'type': 'page'},
      );
      expect(f.client.calls, ['getSpaceContent:ENG:page']);
    });

    test('routes confluence_create_space', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_create_space',
        {'key': 'ENG', 'name': 'Engineering'},
      );
      expect(f.client.calls, ['createSpace:ENG:Engineering']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _SpacesSpy client}) _makeExecutor() {
  final client = _SpacesSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned `space` response body.
final _spacesBody = jsonEncode({
  'results': [
    {'key': 'ENG', 'name': 'Engineering'},
    {'key': 'OPS', 'name': 'Operations'},
  ],
});

/// Canned single-space response body.
final _spaceByKeyBody = jsonEncode({
  'key': 'ENG',
  'name': 'Engineering',
});

/// Canned updated-space response body.
final _spaceUpdatedBody = jsonEncode({
  'key': 'ENG',
  'name': 'New Name',
});

/// Canned space-content response body.
final _spaceContentBody = jsonEncode({
  'results': [
    {'id': '1', 'title': 'Home'},
    {'id': '2', 'title': 'Docs'},
  ],
});

/// Canned created-space response body.
final _createdSpaceBody = jsonEncode({
  'key': 'ENG',
  'name': 'Engineering',
});

/// Spy that records every space call then delegates to the real client.
class _SpacesSpy extends ConfluenceClient {
  _SpacesSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getSpaces() {
    calls.add('getSpaces');
    return super.getSpaces();
  }

  @override
  Future<Map<String, dynamic>> getSpaceByKey(String spaceKey) {
    calls.add('getSpaceByKey:$spaceKey');
    return super.getSpaceByKey(spaceKey);
  }

  @override
  Future<Map<String, dynamic>> updateSpace(
    String spaceKey,
    String name,
    String description,
  ) {
    calls.add('updateSpace:$spaceKey:$name:$description');
    return super.updateSpace(spaceKey, name, description);
  }

  @override
  Future<List<Map<String, dynamic>>> getSpaceContent(
    String spaceKey,
    String contentType,
  ) {
    calls.add('getSpaceContent:$spaceKey:$contentType');
    return super.getSpaceContent(spaceKey, contentType);
  }

  @override
  Future<Map<String, dynamic>> createSpace(String key, String name) {
    calls.add('createSpace:$key:$name');
    return super.createSpace(key, name);
  }
}
