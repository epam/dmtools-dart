import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// Echo-server tests for the GitLab, Confluence, and ADO tools on
/// [SyncToolDispatcher].
///
/// Split out of `sync_tool_dispatch_test.dart` so that file stays under the
/// 800-line `loc` quality gate (`crap4dart.yaml`). Each test asserts the URL
/// shape, auth header, and request body that the dispatcher produces — these
/// mirror the async `GitlabHttpClient` / `ConfluenceHttpClient` /
/// `AdoHttpClient` transports so both paths hit the same endpoints.
void main() {
  if (hasPython3()) {
    _testGitlabReadTools();
    _testGitlabWriteTools();
    _testConfluenceReadTools();
    _testConfluenceWriteTools();
    _testAdoTools();
  }
}

void _testGitlabReadTools() {
  group('SyncToolDispatcher GitLab read tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'GITLAB_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'GITLAB_TOKEN': 'glpat-testtoken',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('gitlab_get_mr hits merge_requests endpoint with encoded project', () {
      final body = jsonDecode(dispatcher.execute('gitlab_get_mr', {
        'project': 'group/repo',
        'iid': 7,
      })!);
      expect(body['method'], 'GET');
      expect(body['path'], '/api/v4/projects/group%2Frepo/merge_requests/7');
    });

    test('gitlab_get_mr sends PRIVATE-TOKEN header', () {
      final body = jsonDecode(dispatcher.execute('gitlab_get_mr', {
        'project': '42',
        'iid': 1,
      })!);
      expect(body['headers']['PRIVATE-TOKEN'], 'glpat-testtoken');
    });

    test('gitlab_list_mrs hits the list endpoint with state query', () {
      final body = jsonDecode(dispatcher.execute('gitlab_list_mrs', {
        'project': 'group/repo',
      })!);
      expect(body['method'], 'GET');
      expect(
        body['path'],
        '/api/v4/projects/group%2Frepo/merge_requests'
        '?state=opened&per_page=20',
      );
    });
  });
}

void _testGitlabWriteTools() {
  group('SyncToolDispatcher GitLab write tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'GITLAB_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'GITLAB_TOKEN': 'glpat-testtoken',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('gitlab_create_mr_note POSTs note body', () {
      final body = jsonDecode(dispatcher.execute('gitlab_create_mr_note', {
        'project': 'group/repo',
        'iid': 7,
        'body': 'Looks good!',
      })!);
      expect(body['method'], 'POST');
      expect(
        body['path'],
        '/api/v4/projects/group%2Frepo/merge_requests/7/notes',
      );
      expect(jsonDecode(body['body'] as String)['body'], 'Looks good!');
    });
  });
}

void _testConfluenceReadTools() {
  group('SyncToolDispatcher Confluence read tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
        'CONFLUENCE_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('confluence_search encodes cql and sends Basic auth', () {
      final body =
          jsonDecode(dispatcher.execute('confluence_search', {'cql': 'a=b'})!);
      expect(body['method'], 'GET');
      expect(body['path'].startsWith('/wiki/rest/api/content/search'), isTrue);
      expect(body['path'], contains('cql=a%3Db'));
      expect(body['headers']['Authorization'], 'Basic conf-token');
      expect(body['headers']['Accept'], 'application/json');
    });

    test('confluence_get_page hits content with space/title/expand', () {
      final body = jsonDecode(dispatcher.execute('confluence_get_page', {
        'spaceKey': 'DEV',
        'title': 'Home Page',
      })!);
      expect(body['method'], 'GET');
      expect(body['path'].startsWith('/wiki/rest/api/content?'), isTrue);
      expect(body['path'], contains('spaceKey=DEV'));
      expect(body['path'], contains('title=Home+Page'));
      expect(body['path'], contains('expand=body.storage'));
    });
  });
}

void _testConfluenceWriteTools() {
  group('SyncToolDispatcher Confluence write tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
        'CONFLUENCE_AUTH_TYPE': 'Bearer',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('confluence_create_page POSTs the storage-format page payload', () {
      final body = jsonDecode(dispatcher.execute('confluence_create_page', {
        'space': 'DEV',
        'title': 'New Page',
        'body': '<p>hello</p>',
      })!);
      expect(body['method'], 'POST');
      expect(body['path'], '/wiki/rest/api/content');
      final payload = jsonDecode(body['body'] as String);
      expect(payload['type'], 'page');
      expect(payload['title'], 'New Page');
      expect(payload['space']['key'], 'DEV');
      expect(payload['body']['storage']['value'], '<p>hello</p>');
      expect(payload['body']['storage']['representation'], 'storage');
      expect(body['headers']['Authorization'], 'Bearer conf-token');
    });
  });
}

void _testAdoTools() {
  group('SyncToolDispatcher ADO tools', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'ADO_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'ADO_ORGANIZATION': 'myorg',
        'ADO_PROJECT': 'myproj',
        'ADO_PAT_TOKEN': 'pat-token',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('ado_get_work_item hits the workitems endpoint with api-version', () {
      final body =
          jsonDecode(dispatcher.execute('ado_get_work_item', {'id': 42})!);
      expect(body['method'], 'GET');
      expect(
        body['path'],
        '/myorg/myproj/_apis/wit/workitems/42?api-version=7.0',
      );
    });

    test('ado_get_work_item sends Basic PAT auth', () {
      final body =
          jsonDecode(dispatcher.execute('ado_get_work_item', {'id': 1})!);
      final expected = 'Basic ${base64Encode(utf8.encode(':pat-token'))}';
      expect(body['headers']['Authorization'], expected);
    });

    test('ado_list_work_items POSTs WIQL query to the wiql endpoint', () {
      final body = jsonDecode(dispatcher.execute('ado_list_work_items', {
        'wiql': 'SELECT [System.Id] FROM WorkItems',
      })!);
      expect(body['method'], 'POST');
      expect(body['path'], '/myorg/myproj/_apis/wit/wiql?api-version=7.0');
      final payload = jsonDecode(body['body'] as String);
      expect(payload['query'], 'SELECT [System.Id] FROM WorkItems');
    });
  });
}
