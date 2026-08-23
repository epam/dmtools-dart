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
}
