import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Label coverage: add and list page labels — plus the matching tool
/// definitions and executor dispatch.
///
/// Note: `getPageLabels` is intentionally not added — the existing
/// [ConfluenceClient.getLabels] (GET `content/{id}/label`) already covers it.
void main() {
  tearDown(PropertyReader.clearOverrides);
  addLabelTests();
  getLabelsTests();
  labelToolDefinitionTests();
  labelExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_add_label` — POST `content/{id}/label`.
void addLabelTests() {
  group('ConfluenceClient.addLabel', () {
    test('POSTs a global-prefix label and returns the response', () async {
      final f =
          mockConfluence((o) => routeByPath({'/label': _labelAddedBody}, o));
      final result = await f.client.addLabel('42', 'important');
      expect(result['results'], hasLength(1));
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/content/42/label'));
      final sent = jsonDecode(call.data as String) as List;
      final entry = sent.single as Map<String, dynamic>;
      expect(entry['prefix'], 'global');
      expect(entry['name'], 'important');
    });
  });
}

/// `confluence_get_labels` — GET `content/{id}/label`.
void getLabelsTests() {
  group('ConfluenceClient.getLabels', () {
    test('returns the label results', () async {
      final f = mockConfluence((o) => routeByPath({'/label': _labelsBody}, o));
      final labels = await f.client.getLabels('42');
      expect(labels, hasLength(2));
      expect(labels[0]['name'], 'bug');
      expect(labels[1]['name'], 'feature');
    });
  });
}

/// Tool-definition shape for the label tools.
void labelToolDefinitionTests() {
  group('confluence tool definitions (labels)', () {
    test('confluence_add_label requires pageId and label', () {
      final tool = toolNamed('confluence_add_label');
      expect(tool.category, 'labels');
      expect(tool.params.map((p) => p.name), ['pageId', 'label']);
      expect(tool.params.every((p) => p.required), isTrue);
    });

    test('confluence_get_labels requires pageId', () {
      final tool = toolNamed('confluence_get_labels');
      expect(tool.category, 'labels');
      expect(tool.params.single.name, 'pageId');
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each label tool name.
void labelExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (labels)', () {
    test('routes confluence_add_label', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_add_label',
        {'pageId': '42', 'label': 'bug'},
      );
      expect(f.client.calls, ['addLabel:42:bug']);
    });

    test('routes confluence_get_labels', () async {
      final f = _makeExecutor();
      await f.executor.execute('confluence_get_labels', {'pageId': '42'});
      expect(f.client.calls, ['getLabels:42']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _LabelsSpy client}) _makeExecutor() {
  final client = _LabelsSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned add-label response body.
final _labelAddedBody = jsonEncode({
  'results': [
    {'prefix': 'global', 'name': 'important'},
  ],
});

/// Canned labels response body.
final _labelsBody = jsonEncode({
  'results': [
    {'prefix': 'global', 'name': 'bug'},
    {'prefix': 'global', 'name': 'feature'},
  ],
});

/// Spy that records every label call then delegates to the real client.
class _LabelsSpy extends ConfluenceClient {
  _LabelsSpy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> addLabel(String pageId, String label) {
    calls.add('addLabel:$pageId:$label');
    return super.addLabel(pageId, label);
  }

  @override
  Future<List<Map<String, dynamic>>> getLabels(String pageId) {
    calls.add('getLabels:$pageId');
    return super.getLabels(pageId);
  }
}
