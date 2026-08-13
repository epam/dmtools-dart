import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Batch-4 coverage: getSpaceContent, createSpace, archivePage,
/// getPageProperties, setPageProperty — plus the matching tool definitions
/// and executor dispatch.
///
/// Note: `getPageLabels` is intentionally not added — the existing
/// [ConfluenceClient.getLabels] (GET `content/{id}/label`) already covers it.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getSpaceContentTests();
  createSpaceTests();
  archivePageTests();
  getPagePropertiesTests();
  setPagePropertyTests();
  downloadAttachmentTests();
  batch4ToolDefinitionTests();
  batch4ExecutorTests();
  batch4ExecutorExtraTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

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

/// `confluence_archive_page` — PUT `content/{id}` with status `archived`.
void archivePageTests() {
  group('ConfluenceClient.archivePage', () {
    test('PUTs the archived status and returns the response', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/42': _archivedBody}, o),
      );
      final result = await f.client.archivePage('42');
      expect(result['status'], 'archived');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/content/42'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['status'], 'archived');
      expect(sent['id'], '42');
    });

    test('returns empty map on an empty response body', () async {
      final f = mockConfluence((o) => routeByPath({'/content/42': ''}, o));
      expect(await f.client.archivePage('42'), isEmpty);
    });
  });
}

/// `confluence_get_page_properties` — GET `content/{id}/property`.
void getPagePropertiesTests() {
  group('ConfluenceClient.getPageProperties', () {
    test('returns the property results', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/property': _propertiesBody}, o),
      );
      final props = await f.client.getPageProperties('42');
      expect(props, hasLength(2));
      expect(props[0]['key'], 'editor');
      expect(props[1]['key'], 'status');
      expect(f.adapter.calls.single.path, endsWith('/content/42/property'));
    });
  });
}

/// `confluence_set_page_property` — POST `content/{id}/property`.
void setPagePropertyTests() {
  group('ConfluenceClient.setPageProperty', () {
    test('POSTs key and value and returns the response', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/property': _propertySetBody}, o),
      );
      final Map<String, dynamic> value = {'state': 'draft'};
      final result = await f.client.setPageProperty('42', 'status', value);
      expect(result['key'], 'status');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/content/42/property'));
      final sent = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(sent['key'], 'status');
      expect((sent['value'] as Map<String, dynamic>)['state'], 'draft');
    });
  });
}

/// `confluence_download_attachment` — GET
/// `content/{pageId}/child/attachment/{attachmentId}/download`.
void downloadAttachmentTests() {
  group('ConfluenceClient.downloadAttachment', () {
    test('returns the raw download content', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/download': _downloadBody}, o),
      );
      final content = await f.client.downloadAttachment('42', 'att-1');
      expect(content, _downloadBody);
      expect(
        f.adapter.calls.single.path,
        endsWith('/content/42/child/attachment/att-1/download'),
      );
    });
  });
}

/// Tool-definition shape for the batch-4 tools.
void batch4ToolDefinitionTests() {
  group('batch4 tool definitions', () {
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

    test('confluence_archive_page requires id', () {
      final tool = toolNamed('confluence_archive_page');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_get_page_properties requires id', () {
      final tool = toolNamed('confluence_get_page_properties');
      expect(tool.category, 'properties');
      expect(tool.params.single.name, 'id');
    });

    test('confluence_set_page_property requires id, key, value', () {
      final tool = toolNamed('confluence_set_page_property');
      expect(tool.category, 'properties');
      expect(tool.params.map((p) => p.name), ['id', 'key', 'value']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('confluence_download_attachment requires pageId and attachmentId', () {
      final tool = toolNamed('confluence_download_attachment');
      expect(tool.category, 'attachments');
      expect(tool.params.map((p) => p.name), ['pageId', 'attachmentId']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each batch-4 tool name.
void batch4ExecutorTests() {
  group('ConfluenceToolExecutor batch4 dispatch', () {
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

    test('routes confluence_archive_page', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_archive_page',
        {'id': '42'},
      );
      expect(f.client.calls, ['archivePage:42']);
    });

    test('routes confluence_get_page_properties', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_page_properties',
        {'id': '42'},
      );
      expect(f.client.calls, ['getPageProperties:42']);
    });
  });
}

/// Extra batch-4 dispatch: setPageProperty, downloadAttachment.
void batch4ExecutorExtraTests() {
  group('ConfluenceToolExecutor batch4 dispatch (extra)', () {
    test('routes confluence_set_page_property', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_set_page_property',
        {
          'id': '42',
          'key': 'status',
          'value': {'state': 'draft'},
        },
      );
      expect(f.client.calls, ['setPageProperty:42:status']);
    });

    test('routes confluence_download_attachment', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_download_attachment',
        {'pageId': '42', 'attachmentId': 'att-1'},
      );
      expect(f.client.calls, ['downloadAttachment:42:att-1']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _Batch4Spy client}) _makeExecutor() {
  final client = _Batch4Spy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

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

/// Canned archive response body.
const _archivedBody = '{"id":"42","status":"archived"}';

/// Canned page-properties response body.
final _propertiesBody = jsonEncode({
  'results': [
    {'key': 'editor', 'value': {}},
    {'key': 'status', 'value': {}},
  ],
});

/// Canned set-property response body.
final _propertySetBody = jsonEncode({
  'key': 'status',
  'value': {'state': 'draft'},
});

/// Canned download-attachment raw content.
const _downloadBody = 'binary-content-here';

/// Spy that records every batch-4 call then delegates to the real client.
class _Batch4Spy extends ConfluenceClient {
  _Batch4Spy(super.http);

  final List<String> calls = [];

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

  @override
  Future<Map<String, dynamic>> archivePage(String id) {
    calls.add('archivePage:$id');
    return super.archivePage(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getPageProperties(String id) {
    calls.add('getPageProperties:$id');
    return super.getPageProperties(id);
  }

  @override
  Future<Map<String, dynamic>> setPageProperty(
    String id,
    String key,
    Map<String, dynamic> value,
  ) {
    calls.add('setPageProperty:$id:$key');
    return super.setPageProperty(id, key, value);
  }

  @override
  Future<String> downloadAttachment(String pageId, String attachmentId) {
    calls.add('downloadAttachment:$pageId:$attachmentId');
    return super.downloadAttachment(pageId, attachmentId);
  }
}
