import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/gitlab_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

late EchoServer server;
const tools = GitLabSyncTools();

Map<String, dynamic> echo(String tool, Map<String, dynamic> args) =>
    jsonDecode(tools.handlers[tool]!(args)) as Map<String, dynamic>;

/// Java #574 tool echo tests — split from [testmrtools_p1] for the
/// crap4dart method-size gate.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() => PropertyReader.testIsolation = false);
  if (!hasPython3()) return;

  group('gitlab Java #574 additions', () {
    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'GITLAB_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'GITLAB_TOKEN': 'glpat-test',
      });
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('gitlab_get_mr_pipelines GETs the MR pipelines path', () {
      final body = echo('gitlab_get_mr_pipelines', {
        'workspace': 'mygroup',
        'repository': 'myrepo',
        'pullRequestId': '42',
      });
      expect(body['method'], 'GET');
      expect(
        body['path'],
        '/api/v4/projects/mygroup%2Fmyrepo/merge_requests/42/pipelines',
      );
    });

    test('gitlab_list_issues lists opened issues by default', () {
      final body = echo('gitlab_list_issues', {
        'workspace': 'mygroup',
        'repository': 'myrepo',
      });
      expect(body['method'], 'GET');
      expect(
        body['path'],
        '/api/v4/projects/mygroup%2Fmyrepo/issues?state=opened&per_page=20',
      );
    });

    test('gitlab_list_issues honors state and perPage args', () {
      final body = echo('gitlab_list_issues', {
        'workspace': 'g',
        'repository': 'r',
        'state': 'all',
        'perPage': '50',
      });
      expect(
          body['path'], '/api/v4/projects/g%2Fr/issues?state=all&per_page=50');
    });
  });
}
