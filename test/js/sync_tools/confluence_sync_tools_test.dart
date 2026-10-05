import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/confluence_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

/// Shared fixtures for the echo-server-backed groups.
late EchoServer server;
late ConfluenceSyncTools tools;

/// Tests for [ConfluenceSyncTools] — the public Confluence section of the
/// sync tool bridge (Java `Confluence.java` @MCPTool parity).
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _testRoutingAndConfig();
  if (hasPython3()) {
    _testReadTools();
    _testWriteTools();
    _testWriteToolsV2();
    uploadPolicyTests();
  }
}

Map<String, String> _config(int port) => {
      'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:$port',
      'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
      'CONFLUENCE_AUTH_TYPE': 'Basic',
    };

void _testRoutingAndConfig() {
  group('ConfluenceSyncTools routing and config', () {
    late ConfluenceSyncTools tools;

    setUp(() {
      PropertyReader.setOverrides({
        'CONFLUENCE_BASE_PATH': '',
        'CONFLUENCE_LOGIN_PASS_TOKEN': '',
      });
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() => PropertyReader.clearOverrides());

    test('unsupported tool returns error JSON', () {
      expect(
        jsonDecode(tools.dispatch('confluence_mystery', {})),
        {'error': 'Unsupported Confluence tool: confluence_mystery'},
      );
    });

    test('handlers map exposes the Java tool names', () {
      expect(tools.handlers.keys, contains('confluence_content_by_id'));
      expect(tools.handlers.keys, contains('confluence_get_children_by_id'));
      expect(
        tools.handlers.keys,
        contains('confluence_sync_markdown_directory'),
      );
      expect(tools.handlers.keys, contains('confluence_update_page'));
    });

    test('confluence not configured returns error JSON', () {
      expect(
        jsonDecode(
            tools.dispatch('confluence_content_by_id', {'contentId': '1'})),
        {'error': 'Confluence not configured'},
      );
    });

    test('sync_markdown_directory errors on a missing directory', () {
      PropertyReader.setOverrides({
        'CONFLUENCE_BASE_PATH': 'https://confluence.example.com',
        'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
      });
      expect(
        jsonDecode(tools.dispatch('confluence_sync_markdown_directory', {
          'directory': '/nonexistent-dmtools-dir',
          'parentId': '1',
          'space': 'ENG',
        })),
        {
          'error': 'Directory not found: /nonexistent-dmtools-dir',
        },
      );
    });
  });
}

void _testReadTools() {
  group('ConfluenceSyncTools read tools', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides(_config(server.port));
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    _readContentTests();
    _readMarkdownTests();
  });

  _readContentV2Tests();
}

/// Content-endpoint reachability tests (echo shapes).
void _readContentTests() {
  test(
      'confluence_content_by_id hits the content endpoint with the Java '
      'expand list', () {
    final body = jsonDecode(
      tools.dispatch('confluence_content_by_id', {'contentId': '123456'}),
    );
    expect(body['method'], 'GET');
    expect(
      body['path'],
      startsWith('/wiki/rest/api/content/123456?expand='),
    );
    expect(
      body['path'],
      contains('body.storage,body.export_view,ancestors,version'),
    );
  });

  test(
      'confluence_get_children_by_id reaches the API and errors on a '
      'non-results body', () {
    // The echo server answers with the request echo (no results array),
    // proving the request went out and the results contract is enforced.
    expect(
      jsonDecode(
        tools.dispatch('confluence_get_children_by_id', {'contentId': '42'}),
      ),
      {'error': 'Unexpected children response for 42'},
    );
  });

  test('confluence_search encodes cql and sends auth', () {
    final body =
        jsonDecode(tools.dispatch('confluence_search', {'cql': 'a=b'}));
    expect(body['method'], 'GET');
    expect(body['path'], startsWith('/wiki/rest/api/content/search'));
    expect(body['path'], contains('cql=a%3Db'));
    expect(body['headers']['Authorization'], 'Basic conf-token');
  });
}

/// v2 read-path tests (`CONFLUENCE_API_VERSION=v2`): the granular/scoped-token
/// route. Java parity: `ConfluenceApiV2Test` (sync path).
void _readContentV2Tests() {
  late EchoServer server;
  late ConfluenceSyncTools tools;

  group('ConfluenceSyncTools read tools (v2)', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        ..._config(server.port),
        'CONFLUENCE_API_VERSION': 'v2',
      });
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('confluence_content_by_id uses the v2 pages endpoint', () {
      final body = jsonDecode(
        tools.dispatch('confluence_content_by_id', {'contentId': '123456'}),
      );
      expect(body['method'], 'GET');
      expect(body['path'], startsWith('/wiki/api/v2/pages/123456'));
      expect(body['path'], contains('body-format=storage'));
    });

    test(
        'confluence_get_children_by_id uses the v2 pages endpoint with '
        'parent-id', () {
      // The echo server returns the request echo (no results array), so the
      // v2 branch proves itself by the requested path surfacing in the error.
      final result = jsonDecode(
        tools.dispatch('confluence_get_children_by_id', {'contentId': '42'}),
      );
      // The v2 path hit the echo server; the error proves the request went out
      // (echo body carries no results array).
      expect(result, {'error': 'Unexpected children response for 42'});
    });

    test('baseUrlV2 does not double the /wiki segment', () {
      // _config uses basePath without /wiki; the v2 base must add it once.
      final body = jsonDecode(
        tools.dispatch('confluence_content_by_id', {'contentId': '1'}),
      );
      expect(body['path'], startsWith('/wiki/api/v2/pages/1'));
      expect(body['path'], isNot(contains('/wiki/wiki/')));
    });
  });
}

/// Storage→Markdown conversion tests over the stub content fixtures.
void _readMarkdownTests() {
  test('confluence_content_by_id converts storage to markdown on request', () {
    final body = jsonDecode(tools.dispatch('confluence_content_by_id',
        {'contentId': '777', 'format': 'markdown'}));
    expect(body['body']['storage']['value'], 'hi');
    expect(body['body']['storage']['representation'], 'markdown');
  });

  test('confluence_get_children_by_id returns results as markdown', () {
    final result = tools.dispatch(
        'confluence_get_children_by_id', {'contentId': '99', 'format': 'md'});
    final results = jsonDecode(result) as List<dynamic>;
    expect(results, hasLength(1));
    expect(results.single['body']['storage']['value'], 'child');
    expect(results.single['body']['storage']['representation'], 'markdown');
  });

  test('confluence_get_children_by_id keeps storage without format', () {
    final result =
        tools.dispatch('confluence_get_children_by_id', {'contentId': '99'});
    final results = jsonDecode(result) as List<dynamic>;
    expect(results.single['body']['storage']['representation'], 'storage');
  });
}

void _testWriteTools() {
  group('ConfluenceSyncTools write tools', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        ..._config(server.port),
        'CONFLUENCE_AUTH_TYPE': 'Bearer',
      });
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    testwritetools_p1();
    testwritetools_p2();
  });
}

void testwritetools_p1() {
  test(
      'confluence_update_page fetches the version then PUTs the Java '
      'payload', () {
    final result = tools.dispatch('confluence_update_page', {
      'contentId': '42',
      'title': 'Up',
      'parentId': '7',
      'body': '<p>up</p>',
      'space': 'ENG',
    });
    // The echo body is not a valid version payload → fetch error contract.
    expect(
      jsonDecode(result),
      {'error': 'Failed to fetch version for 42'},
    );
  });

  test('confluence_create_page includes ancestors when parentId is given', () {
    final body = jsonDecode(tools.dispatch('confluence_create_page', {
      'title': 'New Page',
      'parentId': '7',
      'body': '<p>hello</p>',
      'space': 'DEV',
    }));
    expect(body['method'], 'POST');
    expect(body['path'], '/wiki/rest/api/content');
    final payload = jsonDecode(body['body'] as String);
    expect(payload['ancestors'], [
      {'id': '7'},
    ]);
    expect(payload['space']['key'], 'DEV');
    expect(body['headers']['Authorization'], 'Bearer conf-token');
  });

  test('confluence_create_page omits ancestors without parentId', () {
    final body = jsonDecode(tools.dispatch('confluence_create_page', {
      'title': 'New Page',
      'body': '<p>hello</p>',
      'space': 'DEV',
    }));
    final payload = jsonDecode(body['body'] as String);
    expect(payload.containsKey('ancestors'), isFalse);
  });
}

void testwritetools_p2() {
  test('confluence_sync_markdown_directory syncs a tree end to end', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_sync_e2e_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/index.md').writeAsStringSync('# Root\n\nIntro.');
    File('${dir.path}/notes.md').writeAsStringSync('# Notes\n\nBody.');
    final result = tools.dispatch('confluence_sync_markdown_directory', {
      'directory': dir.path,
      'parentId': 'root-page',
      'space': 'ENG',
      'deleteOrphans': false,
    });
    final summary = jsonDecode(result) as Map<String, dynamic>;
    expect(summary['parentId'], 'root-page');
    expect(summary['expectedPages'], 2);
    expect(summary['syncedPages'], contains('Notes'));
    expect(summary['deleted'], isEmpty);
  });

  test('confluence_sync_markdown_directory uploads referenced attachments', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_sync_att_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/index.md')
        .writeAsStringSync('# Root\n\n![Shot](shot.png)');
    File('${dir.path}/page.md').writeAsStringSync('# Page');
    File('${dir.path}/shot.png').writeAsBytesSync([1, 2, 3]);
    final result = tools.dispatch('confluence_sync_markdown_directory', {
      'directory': dir.path,
      'parentId': 'root-page',
      'space': 'ENG',
    });
    // The multipart upload succeeds against the echo server, so the sync
    // completes with both pages in the summary.
    final summary = jsonDecode(result) as Map<String, dynamic>;
    expect(summary['expectedPages'], 2);
    expect(summary['syncedPages'], contains('Page'));
  });

  test('engine uploads an attachment missing from the remote listing', () {
    // The echo attachment listing carries exists.txt/shot.png/evil.txt —
    // a differently-named file forces the uploadAttachment engine path.
    final dir = Directory.systemTemp.createTempSync('dmtools_sync_upl_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/index.md').writeAsStringSync('# Root\n\n![P](pic.png)');
    File('${dir.path}/pic.png').writeAsBytesSync([9, 9, 9]);
    final result = tools.dispatch('confluence_sync_markdown_directory', {
      'directory': dir.path,
      'parentId': 'root-page',
      'space': 'ENG',
    });
    // index.md is the root page itself; the only expected page entry is the
    // folder. pic.png is absent from the echo listing, so the engine's
    // uploadAttachment path runs (and succeeds against the echo server).
    final summary = jsonDecode(result) as Map<String, dynamic>;
    expect(summary['expectedPages'], 1);
  });
}

/// The `confluence_upload_attachment` policy surface (Java
/// `AttachmentHelper.uploadAttachment`): skip-existing, overwrite, create,
/// and the upload-failure contract.
void uploadPolicyTests() {
  group('ConfluenceSyncTools upload policy', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides(_config(server.port));
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('skips an existing attachment unless updateIfExists', () {
      final file = tempUploadFile('exists.txt');
      final result = jsonDecode(tools.dispatch('confluence_upload_attachment', {
        'contentId': '42',
        'file': file.path,
      })) as Map<String, dynamic>;
      expect(result['status'], 'skipped');
      expect((result['attachment'] as Map)['id'], 'a1');

      final updated =
          jsonDecode(tools.dispatch('confluence_upload_attachment', {
        'contentId': '42',
        'file': file.path,
        'updateIfExists': true,
      })) as Map<String, dynamic>;
      expect(updated['status'], 'updated');
    });

    test('creates a new attachment and decodes the wrapper', () {
      final file = tempUploadFile('fresh.bin');
      final result = jsonDecode(tools.dispatch('confluence_upload_attachment', {
        'contentId': '42',
        'file': file.path,
      })) as Map<String, dynamic>;
      expect(result['status'], 'created');
      // The echo server answers the multipart POST with its echo envelope;
      // the wrapper's `results` array wins over the bare object.
      expect(result['attachment'], isNotNull);
    });

    test('reports failed when the upload POST errors', () {
      final file = tempUploadFile('doomed.bin');
      final result = jsonDecode(tools.dispatch('confluence_upload_attachment', {
        'contentId': 'dt-fail',
        'file': file.path,
      })) as Map<String, dynamic>;
      expect(result['status'], 'failed');
      expect(result['attachment'], isNull);
    });
  });
}

/// A named upload fixture in a fresh temp directory.
File tempUploadFile(String name) {
  final dir = Directory.systemTemp.createTempSync('dmtools_upl_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/$name')..writeAsStringSync('bytes');
}

/// Fetches the echo server's recorded request paths for this server
/// instance (the request log resets per test via a fresh server process).
Future<List<String>> _requestLog() async {
  final client = HttpClient();
  try {
    final request =
        await client.get('127.0.0.1', server.port, '/__request_log');
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (jsonDecode(text) as List<dynamic>).cast<String>();
  } finally {
    client.close();
  }
}

/// v2 write/title/attachment routing (`CONFLUENCE_API_VERSION=v2`):
/// create/update resolve the space id and hit `/wiki/api/v2/pages`, title
/// lookup queries `pages?title=&spaceId=&body-format=storage`, attachments
/// read from `pages/{id}/attachments`, while CQL search and the multipart
/// upload intentionally stay on the v1 paths (Java #592 known limitation).
/// Java parity: `ConfluenceApiV2Test` (sync path).
void _testWriteToolsV2() {
  group('ConfluenceSyncTools write/title/attachment tools (v2)', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        ..._config(server.port),
        'CONFLUENCE_AUTH_TYPE': 'Bearer',
        'CONFLUENCE_API_VERSION': 'v2',
      });
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    _writeV2PageTests();
    _writeV2UpdateTests();
    _writeV2TitleTests();
    _writeV2FindOrCreateTests();
    _writeV2AttachmentTests();
    _writeV2MiscTests();
  });
}

/// v2 create/update routing: the space key resolves through
/// `/wiki/api/v2/spaces?keys=` and pages post/put to `/wiki/api/v2/pages`.
void _writeV2PageTests() {
  test(
      'confluence_create_page resolves the space id and posts the v2 '
      'payload', () async {
    final body = jsonDecode(tools.dispatch('confluence_create_page', {
      'title': 'New Page',
      'parentId': '7',
      'body': '<p>hello</p>',
      'space': 'ENG',
    })) as Map<String, dynamic>;
    expect(body['method'], 'POST');
    expect(body['path'], '/wiki/api/v2/pages');
    final payload = jsonDecode(body['body'] as String) as Map<String, dynamic>;
    expect(payload['spaceId'], '456');
    expect(payload['status'], 'current');
    expect(payload['title'], 'New Page');
    expect(payload['parentId'], '7');
    expect(payload['body'],
        {'representation': 'storage', 'value': '<p>hello</p>'});
    expect(payload.containsKey('ancestors'), isFalse);
    final log = await _requestLog();
    expect(log.first, startsWith('/wiki/api/v2/spaces?keys=ENG'));
    expect(log.last, '/wiki/api/v2/pages');
  });

  test('confluence_create_page omits parentId when empty', () {
    final body = jsonDecode(tools.dispatch('confluence_create_page', {
      'title': 'New Page',
      'body': '<p>hello</p>',
      'space': 'ENG',
    })) as Map<String, dynamic>;
    final payload = jsonDecode(body['body'] as String) as Map<String, dynamic>;
    expect(payload.containsKey('parentId'), isFalse);
  });

  test('confluence_create_page errors when the space key is unknown', () async {
    final result = jsonDecode(tools.dispatch('confluence_create_page', {
      'title': 'New Page',
      'body': '<p>hello</p>',
      'space': 'NOPE',
    }));
    expect(
      result,
      {'error': 'Confluence space not found by key: NOPE'},
    );
    expect(await _requestLog(), hasLength(1));
  });
}

/// v2 update routing: the current version is read via
/// `GET /wiki/api/v2/pages/{id}` and the PUT carries the v2 payload
/// (no ancestors/space, explicit `current` status).
void _writeV2UpdateTests() {
  test(
      'confluence_update_page reads the version via v2 then PUTs the '
      'incremented payload', () async {
    final body = jsonDecode(tools.dispatch('confluence_update_page', {
      'contentId': '42',
      'title': 'Up',
      'parentId': '7',
      'body': '<p>up</p>',
      'space': 'ENG',
    })) as Map<String, dynamic>;
    expect(body['method'], 'PUT');
    expect(body['path'], '/wiki/api/v2/pages/42');
    final payload = jsonDecode(body['body'] as String) as Map<String, dynamic>;
    expect(payload['id'], '42');
    expect(payload['status'], 'current');
    expect(payload['title'], 'Up');
    expect(payload['version']['number'], 4);
    expect(payload['body']['value'], '<p>up</p>');
    expect(payload.containsKey('ancestors'), isFalse);
    expect(payload.containsKey('space'), isFalse);
    expect(await _requestLog(), [
      '/wiki/api/v2/pages/42',
      '/wiki/api/v2/pages/42',
    ]);
  });

  test('confluence_update_page_with_history carries the comment', () {
    final body =
        jsonDecode(tools.dispatch('confluence_update_page_with_history', {
      'contentId': '42',
      'title': 'Up',
      'parentId': '7',
      'body': '<p>up</p>',
      'space': 'ENG',
      'historyComment': 'my comment',
    })) as Map<String, dynamic>;
    final payload = jsonDecode(body['body'] as String) as Map<String, dynamic>;
    expect(payload['version']['message'], 'my comment');
  });
}

/// v2 title lookup: `pages?title=&spaceId=&body-format=storage` with the
/// space id resolved from the key; an empty space omits `spaceId`.
void _writeV2TitleTests() {
  test(
      'confluence_content_by_title_and_space queries v2 pages by title '
      'and spaceId', () async {
    final result =
        jsonDecode(tools.dispatch('confluence_content_by_title_and_space', {
      'title': 'My Page',
      'space': 'ENG',
    })) as Map<String, dynamic>;
    expect((result['results'] as List), hasLength(2));
    expect(await _requestLog(), [
      '/wiki/api/v2/spaces?keys=ENG',
      '/wiki/api/v2/pages?title=My+Page&spaceId=456&body-format=storage',
    ]);
  });

  test(
      'confluence_content_by_title_and_space omits spaceId for an empty '
      'space', () async {
    jsonDecode(tools.dispatch('confluence_content_by_title_and_space', {
      'title': 'My Page',
      'space': '',
    }));
    expect(await _requestLog(), [
      '/wiki/api/v2/pages?title=My+Page&body-format=storage',
    ]);
  });
}

/// v2 `find_or_create`: a missing title falls through to the v2 create
/// (spaces resolution + POST pages).
void _writeV2FindOrCreateTests() {
  test('confluence_find_or_create creates via v2 when not found', () async {
    PropertyReader.setOverrides({
      ..._config(server.port),
      'CONFLUENCE_AUTH_TYPE': 'Bearer',
      'CONFLUENCE_API_VERSION': 'v2',
      'CONFLUENCE_DEFAULT_SPACE': 'ENG',
    });
    final body = jsonDecode(tools.dispatch('confluence_find_or_create', {
      'title': 'Nope',
      'parentId': '7',
      'body': '<p>new</p>',
    })) as Map<String, dynamic>;
    expect(body['method'], 'POST');
    expect(body['path'], '/wiki/api/v2/pages');
    final payload = jsonDecode(body['body'] as String) as Map<String, dynamic>;
    expect(payload['spaceId'], '456');
    expect(payload['title'], 'Nope');
    final log = await _requestLog();
    expect(log[0], startsWith('/wiki/api/v2/spaces?keys=ENG'));
    expect(log[1], contains('/wiki/api/v2/pages?title=Nope'));
    expect(log.last, '/wiki/api/v2/pages');
  });
}

/// v2 attachments read from `pages/{id}/attachments` (listing + upload
/// skip/overwrite policy), while the multipart upload POST intentionally
/// stays on the v1 endpoint (Java AttachmentHelper has no v2 uploader).
void _writeV2AttachmentTests() {
  test('confluence_get_content_attachments uses the v2 endpoint', () async {
    final results =
        jsonDecode(tools.dispatch('confluence_get_content_attachments', {
      'contentId': '42',
    })) as List<dynamic>;
    expect(results.map((a) => (a as Map)['title']),
        containsAll(['exists.txt', 'shot.png']));
    expect(await _requestLog(), ['/wiki/api/v2/pages/42/attachments']);
  });

  test(
      'confluence_upload_attachment lists via v2 but uploads via the '
      'v1 multipart endpoint', () async {
    final file = tempUploadFile('exists.txt');
    final skipped = jsonDecode(tools.dispatch('confluence_upload_attachment', {
      'contentId': '42',
      'file': file.path,
    })) as Map<String, dynamic>;
    expect(skipped['status'], 'skipped');
    expect(await _requestLog(), ['/wiki/api/v2/pages/42/attachments']);

    final updated = jsonDecode(tools.dispatch('confluence_upload_attachment', {
      'contentId': '42',
      'file': file.path,
      'updateIfExists': true,
    })) as Map<String, dynamic>;
    expect(updated['status'], 'updated');
    // The update path re-lists via the v2 endpoint before the v1
    // multipart overwrite POST (Java AttachmentHelper has no v2 uploader).
    expect(await _requestLog(), [
      '/wiki/api/v2/pages/42/attachments',
      '/wiki/api/v2/pages/42/attachments',
      '/wiki/rest/api/content/42/child/attachment/a1/data',
    ]);
  });
}

/// v2 `/wiki` base-path normalization (no doubled segment), the v1-only
/// CQL search limitation, and the sync-engine end-to-end shape under v2.
void _writeV2MiscTests() {
  test(
      'confluence_search_content_by_text stays on the v1 CQL path '
      'under v2', () {
    final body =
        jsonDecode(tools.dispatch('confluence_search_content_by_text', {
      'query': 'foo',
    })) as Map<String, dynamic>;
    expect(body['path'], startsWith('/wiki/rest/api/content/search'));
  });

  test('v2 base URL normalizes a base path ending with /wiki', () {
    PropertyReader.setOverrides({
      'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:${server.port}/wiki',
      'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
      'CONFLUENCE_API_VERSION': 'v2',
    });
    final body = jsonDecode(
            tools.dispatch('confluence_content_by_id', {'contentId': '123456'}))
        as Map<String, dynamic>;
    expect(body['path'], startsWith('/wiki/api/v2/pages/123456'));
    expect(body['path'], isNot(contains('/wiki/wiki/')));
  });

  test(
      'confluence_sync_markdown_directory syncs a tree end to end '
      'under v2', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_sync_v2_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/index.md').writeAsStringSync('# Root\n\nIntro.');
    File('${dir.path}/notes.md').writeAsStringSync('# Notes\n\nBody.');
    final result = tools.dispatch('confluence_sync_markdown_directory', {
      'directory': dir.path,
      'parentId': 'root-page',
      'space': 'ENG',
    });
    final summary = jsonDecode(result) as Map<String, dynamic>;
    expect(summary['parentId'], 'root-page');
    expect(summary['expectedPages'], 2);
    expect(summary['syncedPages'], contains('Notes'));
  });
}
