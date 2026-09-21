import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// gh-191: the Java-named Confluence tools ported from the frozen gap
/// snapshot — client behavior plus the matching tool definitions and
/// executor dispatch (`confluenceTools()` names must carry Java parameter
/// names, enforced by the catalog parity fixtures).
void main() {
  tearDown(PropertyReader.clearOverrides);

  titleToolTests();
  findToolTests();
  profileAndSearchTests();
  uploadAndDownloadTests();
  executorAndDefinitionTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

MockConfluenceFixture mockWithDefaultSpace(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides({
    'CONFLUENCE_BASE_PATH': 'https://confluence.example.com/wiki',
    'CONFLUENCE_EMAIL': 'dev@example.com',
    'CONFLUENCE_API_TOKEN': 'tok-123',
    'CONFLUENCE_DEFAULT_SPACE': 'ENG',
  });
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    client: ConfluenceClient(
      ConfluenceHttpClient(PropertyReader(), dio: dio),
      defaultSpace: 'ENG',
    ),
    adapter: adapter,
  );
}

/// `contentByTitle` / `contentByTitleAndSpace`.
void titleToolTests() {
  group('ConfluenceClient.contentByTitle*', () {
    test('contentByTitle lists in the default space', () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({'/content': _listingBody}, o),
      );
      final listing = await f.client.contentByTitle('Docs');
      expect(_results(listing), hasLength(2));
      final call = f.adapter.calls.single;
      expect(call.queryParameters['title'], 'Docs');
      expect(call.queryParameters['spaceKey'], 'ENG');
    });

    test('contentByTitle throws without a default space', () async {
      final f = mockConfluence((o) => '{}');
      expect(
        f.client.contentByTitle('Docs'),
        throwsA(isA<StateError>()),
      );
    });

    test('contentByTitleAndSpace converts storage to markdown', () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({'/content': _listingBody}, o),
      );
      final listing =
          await f.client.contentByTitleAndSpace('Docs', 'DEV', 'md');
      expect(_results(listing).first['body']['storage']['value'], 'found');
      expect(
        _results(listing).first['body']['storage']['representation'],
        'markdown',
      );
    });
  });
}

/// `findContent` / `findOrCreate` / `getChildrenByName`.
void findToolTests() {
  group('ConfluenceClient.find* tools', () {
    test('findContent returns the first match or null', () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({'/content': _listingBody}, o),
      );
      expect((await f.client.findContent('Docs'))?['id'], '801');
    });

    test('findContent by explicit space hits spaceKey', () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({'/content': _emptyListingBody}, o),
      );
      final found = await f.client.findContent('Docs', space: 'DEV');
      expect(found, isNull);
      expect(f.adapter.calls.single.queryParameters['spaceKey'], 'DEV');
    });

    test('findOrCreate returns the existing page', () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({'/content': _listingBody}, o),
      );
      final page = await f.client.findOrCreate('Docs', '7', '<p>new</p>');
      expect(page['id'], '801');
    });

    test('findOrCreate creates under the parent when not found', () async {
      final f = mockWithDefaultSpace((o) => o.method == 'POST'
          ? '{"id":"909","title":"Docs"}'
          : _emptyListingBody);
      final page = await f.client.findOrCreate('Docs', '7', '<p>new</p>');
      expect(page['id'], '909');
      final post = f.adapter.calls.last;
      expect(post.method, 'POST');
      final payload = jsonDecode(post.data as String) as Map;
      expect(payload['ancestors'], [
        {'id': '7'},
      ]);
      expect(payload['space']['key'], 'ENG');
    });

    test('getChildrenByName resolves the parent then fetches children',
        () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({
          '/child/page': '{"results":[{"id":"902","title":"Child"}]}',
          '/content': '{"results":[{"id":"555","title":"Parent"}]}',
        }, o),
      );
      final children = await f.client.getChildrenByName('ENG', 'Parent');
      expect(children.single['id'], '902');
    });

    test('getChildrenByName throws when the parent is missing', () async {
      final f = mockWithDefaultSpace(
        (o) => routeByPath({'/content': _emptyListingBody}, o),
      );
      expect(
        f.client.getChildrenByName('ENG', 'Ghost'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// Profiles, text search, URL fetch, history-aware update.
void profileAndSearchTests() {
  group('ConfluenceClient profile/search/URL tools', () {
    test('getContentAttachments returns the results', () async {
      final f = mockConfluence((o) => routeByPath({
        '/child/attachment':
            '{"results":[{"id":"a1","title":"x.png"}]}',
      }, o));
      final attachments = await f.client.getContentAttachments('42');
      expect(attachments.single['id'], 'a1');
    });

    test('getCurrentUserProfile GETs user/current', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/user/current': '{"displayName":"Dev"}'}, o),
      );
      expect((await f.client.getCurrentUserProfile())['displayName'], 'Dev');
    });

    test('getUserProfileById sends the accountId', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/user': '{"accountId":"1234:abc"}'}, o),
      );
      final user = await f.client.getUserProfileById('1234:abc');
      expect(user['accountId'], '1234:abc');
      expect(f.adapter.calls.single.queryParameters['accountId'], '1234:abc');
    });

    test('searchContentByText builds the Java CQL with the limit', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/content/search': '{"results":[{"id":"9"}]}'}, o),
      );
      final results = await f.client.searchContentByText('docs', 5);
      expect(results.single['id'], '9');
      final call = f.adapter.calls.single;
      expect(
        call.queryParameters['cql'],
        '(title ~ "docs" OR text ~ "docs") ORDER BY lastModified ASC',
      );
      expect(call.queryParameters['limit'], '5');
      expect(call.queryParameters['expand'],
          'title,body.excerpt,history,space,body.storage');
    });

    test('updatePageWithHistory sends the version message', () async {
      final f = mockConfluence((o) => o.method == 'GET'
          ? '{"version":{"number":3}}'
          : '{"id":"555"}');
      final updated = await f.client.updatePageWithHistory(
        contentId: '555',
        title: 'Up',
        parentId: '7',
        body: '<p>up</p>',
        space: 'ENG',
        historyComment: 'gh-191',
      );
      expect(updated['id'], '555');
      final put = f.adapter.calls.last;
      expect(put.method, 'PUT');
      final payload = jsonDecode(put.data as String) as Map;
      expect(payload['version']['number'], 4);
      expect(payload['version']['message'], 'gh-191');
    });

    test('contentsByUrls resolves ids and skips failures', () async {
      final f = mockConfluence((o) => routeByPath({
        '/content/777': _page777,
      }, o, fallback: '{}'));
      final contents = await f.client.contentsByUrls([
        'https://conf.example.com/wiki/spaces/ENG/pages/777/Hi',
        'https://conf.example.com/not-a-page',
      ]);
      expect(contents, hasLength(1));
      expect(contents.single['id'], '777');
    });

    test('contentByUrl follows a short-link redirect then fetches the page',
        () async {
      final f = mockConfluence((o) {
        if (o.path.contains('/l/redirect')) {
          return _page777; // the routing adapter cannot answer 3xx; the
          // redirect branch is exercised by the echo-server sync tests.
        }
        return routeByPath({'/content/777': _page777}, o, fallback: '{}');
      });
      final content = await f.client
          .contentByUrl('https://conf.example.com/wiki/spaces/ENG/pages/777');
      expect(content?['id'], '777');
    });

    test('contentByUrl follows a chained short link sending auth headers',
        () async {
      final f = mockRedirectConfluence({
        '/l/chain': (
          status: 302,
          location: 'https://conf.example.com/wiki/x/AB12',
          body: ''
        ),
        '/wiki/x/AB12': (
          status: 302,
          location:
              'https://conf.example.com/wiki/spaces/ENG/pages/777/Hi',
          body: ''
        ),
        '/content/777': (status: 200, location: null, body: _page777),
      });
      final content =
          await f.client.contentByUrl('https://conf.example.com/l/chain');
      expect(content?['id'], '777');
      // Every redirect probe travels authenticated — on instances with
      // anonymous access disabled an unauthenticated probe 302s to the
      // login page and short links silently stop resolving.
      final probes = f.adapter.calls
          .where((c) =>
              c.uri.path.contains('/l/') || c.uri.path.contains('/wiki/x/'))
          .toList();
      expect(probes, hasLength(2));
      for (final probe in probes) {
        expect(probe.headers['Authorization'], startsWith('Basic '),
            reason: 'unauthenticated probe on ${probe.uri}');
      }
    });

    test('downloadPages skips a dead short link without aborting', () async {
      final f = mockRedirectConfluence({
        '/l/dead': (status: 404, location: null, body: 'gone'),
        '/content/777': (status: 200, location: null, body: _page777),
      });
      final out = Directory.systemTemp.createTempSync('dmtools_adl_dead_');
      addTearDown(() => out.deleteSync(recursive: true));
      final result = await f.client.downloadPages([
        'https://conf.example.com/l/dead',
        'https://conf.example.com/wiki/spaces/ENG/pages/777/Hi',
      ], out.path);
      // The 404 short link degrades to a per-URL skip (sync-surface
      // behavior); the healthy URL still downloads.
      expect(result, 'Downloaded 1 Confluence page(s) to ${out.path}');
    });
  });
}

/// Uploads and the page downloader (real temp dirs, canned listings).
void uploadAndDownloadTests() {
  group('ConfluenceClient upload/download tools', () {
    test('uploadAttachment skips an existing name by default', () async {
      final f = mockConfluence((o) => routeByPath({
        '/child/attachment':
            '{"results":[{"id":"a1","title":"exists.txt"}]}',
      }, o));
      final dir = Directory.systemTemp.createTempSync('dmtools_au_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/exists.txt').writeAsStringSync('data');
      final result = await f.client.uploadAttachment('42', '${dir.path}/exists.txt');
      expect(result['status'], 'skipped');
    });

    test('uploadAttachments summarizes created and skipped files', () async {
      final f = mockConfluence((o) => routeByPath({
        '/child/attachment':
            '{"results":[{"id":"a1","title":"exists.txt"}]}',
        '/data': '{"results":[{"id":"a1"}]}',
        '/attachment': '{"id":"a2"}',
      }, o, fallback: '{"id":"a9"}'));
      final dir = Directory.systemTemp.createTempSync('dmtools_aus_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/exists.txt').writeAsStringSync('a');
      File('${dir.path}/fresh.txt').writeAsStringSync('b');
      final summary = await f.client.uploadAttachments('42', dir.path);
      expect(summary['skipped'], ['exists.txt']);
      expect(summary['uploaded'], ['fresh.txt']);
      expect(summary['failed'], isEmpty);
    });

    test('downloadPages writes markdown and follows children', () async {
      final f = mockConfluence((o) {
        if (o.uri.path.endsWith('/child/page')) {
          // Real Confluence only returns body.storage when the request
          // carries the expand param — the downloader must ask for it.
          final wantsBody =
              (o.queryParameters['expand'] ?? '').contains('body.storage');
          return wantsBody
              ? '{"results":[{"id":"902","title":"Child Page","body":{"storage":{"value":"<p>kid</p>","representation":"storage"}}}]}'
              : '{"results":[{"id":"902","title":"Child Page"}]}';
        }
        return routeByPath({'/content/777': _page777}, o, fallback: '{}');
      });
      final out = Directory.systemTemp.createTempSync('dmtools_adl_');
      addTearDown(() => out.deleteSync(recursive: true));
      final result = await f.client.downloadPages(
        ['https://conf.example.com/wiki/spaces/ENG/pages/777/Hi'],
        out.path,
        2,
      );
      expect(result, 'Downloaded 2 Confluence page(s) to ${out.path}');
      expect(File('${out.path}/Hi Page.md').readAsStringSync(), 'hi');
      expect(File('${out.path}/Child Page.md').readAsStringSync(), 'kid');
    });
  });
}

/// Executor routing + fixture classification for the new names.
void executorAndDefinitionTests() {
  group('Confluence gh-191 executor and definitions', () {
    final f = mockWithDefaultSpace(
      (o) => routeByPath({
        '/user/current': '{"displayName":"Dev"}',
      }, o, fallback: '{}'),
    );

    test('executor dispatches the Java names', () async {
      final profile = await ConfluenceToolExecutor(f.client)
          .execute('confluence_get_current_user_profile', {});
      expect((profile as Map)['displayName'], 'Dev');
    });

    test('every new tool definition carries Java parameter names', () {
      final expected = {
        'confluence_content_by_title': ['title', 'format'],
        'confluence_content_by_title_and_space': ['title', 'space', 'format'],
        'confluence_contents_by_urls': ['urlStrings', 'format'],
        'confluence_download_pages': [
          'urlStrings',
          'outputPath',
          'depth',
          'downloadAttachments'
        ],
        'confluence_find_content': ['title', 'format'],
        'confluence_find_content_by_title_and_space': [
          'title',
          'space',
          'format'
        ],
        'confluence_find_or_create': ['title', 'parentId', 'body'],
        'confluence_get_children_by_name': ['spaceKey', 'contentName', 'format'],
        'confluence_get_content_attachments': ['contentId'],
        'confluence_get_current_user_profile': <String>[],
        'confluence_get_user_profile_by_id': ['userId'],
        'confluence_search_content_by_text': ['query', 'limit'],
        'confluence_update_page_with_history': [
          'contentId',
          'title',
          'parentId',
          'body',
          'space',
          'historyComment'
        ],
        'confluence_upload_attachment': ['contentId', 'file', 'updateIfExists'],
        'confluence_upload_attachments': [
          'contentId',
          'directory',
          'updateIfExists'
        ],
      };
      final registered = confluenceTools();
      for (final entry in expected.entries) {
        final tool = registered.firstWhere((t) => t.name == entry.key);
        expect(
          tool.params.map((p) => p.name).toSet(),
          entry.value.toSet(),
          reason: entry.key,
        );
        expect(
          tool.params.where((p) => p.required).map((p) => p.name).toSet(),
          // Java declares everything except format/limit/depth flags required.
          entry.value
              .where((p) => !const {
                    'format',
                    'limit',
                    'depth',
                    'downloadAttachments',
                    'updateIfExists',
                  }.contains(p))
              .toSet(),
          reason: '${entry.key} required flags',
        );
      }
    });
  });
}

/// The canned title listing (two results, storage bodies).
const _listingBody =
    '{"results":[{"id":"801","title":"Found Page","body":{"storage":{"value":"<p>found</p>","representation":"storage"}}},'
    '{"id":"802","title":"Second Page","body":{"storage":{"value":"<p>second</p>","representation":"storage"}}}]}';

const _emptyListingBody = '{"results":[]}';

const _page777 =
    '{"id":"777","title":"Hi Page","body":{"storage":{"value":"<p>hi</p>","representation":"storage"}}}';

List<Map<String, dynamic>> _results(Map<String, dynamic> listing) =>
    (listing['results'] as List)
        .whereType<Map<String, dynamic>>()
        .toList();
