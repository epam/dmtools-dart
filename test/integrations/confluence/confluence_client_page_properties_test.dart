import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Page-property coverage: get and set `content/{id}/property` — plus the
/// matching tool definitions and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPagePropertiesTests();
  setPagePropertyTests();
  pagePropertyToolDefinitionTests();
  pagePropertyExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

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

/// Tool-definition shape for the page-property tools.
void pagePropertyToolDefinitionTests() {
  group('confluence tool definitions (page properties)', () {
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
  });
}

/// [ConfluenceToolExecutor.execute] routes each page-property tool name.
void pagePropertyExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (page properties)', () {
    test('routes confluence_get_page_properties', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_page_properties',
        {'id': '42'},
      );
      expect(f.client.calls, ['getPageProperties:42']);
    });

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
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _PagePropertiesSpy client}) _makeExecutor() {
  final client = _PagePropertiesSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

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

/// Spy that records every page-property call then delegates to the real
/// client.
class _PagePropertiesSpy extends ConfluenceClient {
  _PagePropertiesSpy(super.http);

  final List<String> calls = [];

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
}
