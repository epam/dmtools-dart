import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Blog-post coverage: `confluence_get_blog_posts` — client method, tool
/// definition, and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getBlogPostsTests();
  blogPostToolDefinitionTests();
  blogPostExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

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

/// Tool-definition shape for the blog-post tools.
void blogPostToolDefinitionTests() {
  group('confluence tool definitions (blog posts)', () {
    test('confluence_get_blog_posts requires spaceKey', () {
      final tool = toolNamed('confluence_get_blog_posts');
      expect(tool.category, 'blog_posts');
      expect(tool.params.single.name, 'spaceKey');
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each blog-post tool name.
void blogPostExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (blog posts)', () {
    test('routes confluence_get_blog_posts', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_blog_posts',
        {'spaceKey': 'ENG'},
      );
      expect(f.client.calls, ['getBlogPosts:ENG']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _BlogPostsSpy client}) _makeExecutor() {
  final client = _BlogPostsSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned blog-posts response body.
final _blogBody = jsonEncode({
  'results': [
    {'id': '1', 'title': 'Post A'},
    {'id': '2', 'title': 'Post B'},
  ],
});

/// Spy that records every blog-post call then delegates to the real client.
class _BlogPostsSpy extends ConfluenceClient {
  _BlogPostsSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getBlogPosts(String spaceKey) {
    calls.add('getBlogPosts:$spaceKey');
    return super.getBlogPosts(spaceKey);
  }
}
