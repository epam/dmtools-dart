import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Batch-2 coverage: spaces, page-by-id, delete, attachments, labels, blog
/// posts, and content children — plus the matching tool definitions and
/// executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getSpacesTests();
  getPageByIdTests();
  deletePageTests();
  getPageAttachmentsTests();
  addLabelTests();
  getLabelsTests();
  getBlogPostsTests();
  getContentChildrenTests();
  batch2ToolDefinitionTests();
  batch2ExecutorTests();
  batch2ExecutorDispatchTests();
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

/// `confluence_get_page_by_id` — GET `content/{id}?expand=body.storage,version`.
void getPageByIdTests() {
  group('ConfluenceClient.getPageById', () {
    test('returns the page with body and version expanded', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content/42': _pageByIdBody}, o));
      final page = await f.client.getPageById('42');
      expect(page['id'], '42');
      expect(f.adapter.calls.single.queryParameters['expand'],
          'body.storage,version');
    });
  });
}

/// `confluence_delete_page` — DELETE `content/{id}`.
void deletePageTests() {
  group('ConfluenceClient.deletePage', () {
    test('DELETEs the page', () async {
      final f =
          mockConfluence((o) => routeByPath({'/content/42': _deletedBody}, o));
      final result = await f.client.deletePage('42');
      expect(result, {'removed': true});
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/content/42'));
    });

    test('returns empty map on an empty response body', () async {
      final f = mockConfluence((o) => routeByPath({'/content/42': ''}, o));
      expect(await f.client.deletePage('42'), isEmpty);
    });
  });
}

/// `confluence_get_page_attachments` — GET `content/{id}/child/attachment`.
void getPageAttachmentsTests() {
  group('ConfluenceClient.getPageAttachments', () {
    test('returns the attachment results', () async {
      final f = mockConfluence(
          (o) => routeByPath({'/child/attachment': _attachmentsBody}, o));
      final attachments = await f.client.getPageAttachments('42');
      expect(attachments, hasLength(1));
      expect(attachments[0]['title'], 'file.pdf');
      expect(f.adapter.calls.single.path,
          endsWith('/content/42/child/attachment'));
    });
  });
}

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

/// `confluence_get_blog_posts` — GET `content?type=blogpost&spaceKey=`.
void getBlogPostsTests() {
  group('ConfluenceClient.getBlogPosts', () {
    test('returns blog posts filtered by spaceKey', () async {
      final f = mockConfluence((o) => routeByPath({'/content': _blogBody}, o));
      final posts = await f.client.getBlogPosts('ENG');
      expect(posts, hasLength(2));
      expect(posts[0]['id'], '1');
      expect(posts[1]['id'], '2');
      final qp = f.adapter.calls.single.queryParameters;
      expect(qp['type'], 'blogpost');
      expect(qp['spaceKey'], 'ENG');
    });
  });
}

/// `confluence_get_content_children` — GET `content/{id}/child/page`.
void getContentChildrenTests() {
  group('ConfluenceClient.getContentChildren', () {
    test('returns the child page results', () async {
      final f =
          mockConfluence((o) => routeByPath({'/child/page': _childrenBody}, o));
      final children = await f.client.getContentChildren('42');
      expect(children, hasLength(2));
      expect(children[0]['title'], 'Child A');
      expect(children[1]['title'], 'Child B');
      expect(f.adapter.calls.single.path, endsWith('/content/42/child/page'));
    });
  });
}

/// Tool-definition shape for the batch-2 tools.
void batch2ToolDefinitionTests() {
  group('batch2 tool definitions', () {
    test('confluence_get_page_by_id requires id', () {
      final tool = toolNamed('confluence_get_page_by_id');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_delete_page requires id', () {
      final tool = toolNamed('confluence_delete_page');
      expect(tool.category, 'page_management');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.required, isTrue);
    });

    test('confluence_get_spaces has no params', () {
      final tool = toolNamed('confluence_get_spaces');
      expect(tool.category, 'space');
      expect(tool.params, isEmpty);
    });

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

    test('confluence_get_page_attachments requires pageId', () {
      final tool = toolNamed('confluence_get_page_attachments');
      expect(tool.category, 'attachments');
      expect(tool.params.single.name, 'pageId');
    });

    test('confluence_get_blog_posts requires spaceKey', () {
      final tool = toolNamed('confluence_get_blog_posts');
      expect(tool.category, 'blog_posts');
      expect(tool.params.single.name, 'spaceKey');
    });

    test('confluence_get_content_children requires id', () {
      final tool = toolNamed('confluence_get_content_children');
      expect(tool.category, 'content_hierarchy');
      expect(tool.params.single.name, 'id');
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each batch-2 tool name (part 1).
void batch2ExecutorTests() {
  test('routes confluence_get_spaces', () async {
    final f = _makeExecutor();
    await f.executor.execute('confluence_get_spaces', {});
    expect(f.client.calls, ['getSpaces']);
  });

  test('routes confluence_get_page_by_id', () async {
    final f = _makeExecutor();
    await f.executor.execute('confluence_get_page_by_id', {'id': '42'});
    expect(f.client.calls, ['getPageById:42']);
  });

  test('routes confluence_delete_page', () async {
    final f = _makeExecutor();
    await f.executor.execute('confluence_delete_page', {'id': '42'});
    expect(f.client.calls, ['deletePage:42']);
  });

  test('routes confluence_get_page_attachments', () async {
    final f = _makeExecutor();
    await f.executor.execute(
      'confluence_get_page_attachments',
      {'pageId': '42'},
    );
    expect(f.client.calls, ['getPageAttachments:42']);
  });
}

/// [ConfluenceToolExecutor.execute] routes each batch-2 tool name (part 2).
void batch2ExecutorDispatchTests() {
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

  test('routes confluence_get_blog_posts', () async {
    final f = _makeExecutor();
    await f.executor.execute(
      'confluence_get_blog_posts',
      {'spaceKey': 'ENG'},
    );
    expect(f.client.calls, ['getBlogPosts:ENG']);
  });

  test('routes confluence_get_content_children', () async {
    final f = _makeExecutor();
    await f.executor.execute(
      'confluence_get_content_children',
      {'id': '42'},
    );
    expect(f.client.calls, ['getContentChildren:42']);
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _Batch2Spy client}) _makeExecutor() {
  final client = _Batch2Spy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned `space` response body.
final _spacesBody = jsonEncode({
  'results': [
    {'key': 'ENG', 'name': 'Engineering'},
    {'key': 'OPS', 'name': 'Operations'},
  ],
});

/// Canned page-by-id response body.
final _pageByIdBody = jsonEncode({
  'id': '42',
  'title': 'Design Doc',
  'body': {
    'storage': {'value': '<p>x</p>'}
  },
  'version': {'number': 3},
});

/// Canned delete response body.
const _deletedBody = '{"removed":true}';

/// Canned attachments response body.
final _attachmentsBody = jsonEncode({
  'results': [
    {'title': 'file.pdf', 'id': 'att1'},
  ],
});

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

/// Canned blog-posts response body.
final _blogBody = jsonEncode({
  'results': [
    {'id': '1', 'title': 'Post A'},
    {'id': '2', 'title': 'Post B'},
  ],
});

/// Canned child-pages response body.
final _childrenBody = jsonEncode({
  'results': [
    {'title': 'Child A', 'id': 'c1'},
    {'title': 'Child B', 'id': 'c2'},
  ],
});

/// Spy that records every batch-2 call then delegates to the real client.
class _Batch2Spy extends ConfluenceClient {
  _Batch2Spy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getSpaces() {
    calls.add('getSpaces');
    return super.getSpaces();
  }

  @override
  Future<Map<String, dynamic>> getPageById(String id) {
    calls.add('getPageById:$id');
    return super.getPageById(id);
  }

  @override
  Future<Map<String, dynamic>> deletePage(String id) {
    calls.add('deletePage:$id');
    return super.deletePage(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getPageAttachments(String pageId) {
    calls.add('getPageAttachments:$pageId');
    return super.getPageAttachments(pageId);
  }

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

  @override
  Future<List<Map<String, dynamic>>> getBlogPosts(String spaceKey) {
    calls.add('getBlogPosts:$spaceKey');
    return super.getBlogPosts(spaceKey);
  }

  @override
  Future<List<Map<String, dynamic>>> getContentChildren(String id) {
    calls.add('getContentChildren:$id');
    return super.getContentChildren(id);
  }
}
