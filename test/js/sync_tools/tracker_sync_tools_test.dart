/// Tests for the tracker-generic `tracker_*` tool family: catalog presence,
/// backend routing (`TRACKER_TYPE`), provider argument mapping, and the
/// GitHub issue executors — all against the local echo fixture server.
///
/// The echo server runs in a separate Python process because the sync HTTP
/// client blocks the Dart event loop (curl subprocess inside QuickJS
/// callbacks); see `test_echo_server.py`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/config/property_reader_getters.dart';
import 'package:dmtools/src/js/sync_tools/tracker_sync_tools.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

const _fixtureScript = 'test_echo_server.py';

/// The echo fixture's response: request method, path, and decoded body.
class Req {
  final String method;
  final String path;
  final Object? body;

  const Req(this.method, this.path, this.body);
}

/// Decodes an echo-server response body into a [Req].
Req reqOf(String result) {
  final echo = jsonDecode(result) as Map<String, dynamic>;
  final raw = echo['body'] as String?;
  return Req(
    echo['method'] as String,
    echo['path'] as String,
    raw == null || raw.isEmpty ? null : jsonDecode(raw),
  );
}

/// The `{"error": …}` message of a tracker tool result.
String errOf(String result) =>
    (jsonDecode(result) as Map<String, dynamic>)['error'] as String;

/// Echo fixture server: prints the bound port, serves request details as
/// JSON until killed.
class EchoFixtureServer {
  Process? _process;

  /// The bound port (valid after [start]).
  int port = 0;

  /// Starts the fixture server on an ephemeral port.
  Future<void> start() async {
    final script = '${Directory.current.path}/test/js/$_fixtureScript';
    _process = await Process.start('python3', [script, '0']);
    final firstLine = await _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    port = int.parse(firstLine.trim());
  }

  /// Kills the server process.
  void stop() => _process?.kill();
}

void main() {
  final server = EchoFixtureServer();
  final hasPython = Process.runSync('which', ['python3']).exitCode == 0;

  setUpAll(() async {
    if (hasPython) await server.start();
  });
  tearDownAll(server.stop);
  tearDown(PropertyReader.clearOverrides);

  void configureGitHub({String token = 't0k3n', String? repository}) =>
      PropertyReader.setOverrides({
        'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'SOURCE_GITHUB_TOKEN': token,
        if (repository != null) 'GITHUB_REPOSITORY': repository,
      });

  void configureAdo() => PropertyReader.setOverrides({
        'ADO_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'ADO_ORGANIZATION': 'org',
        'ADO_PROJECT': 'proj',
        'ADO_PAT_TOKEN': 'pat',
      });

  void configureJira() => PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'JIRA_LOGIN_PASS_TOKEN': 'tok',
        'JIRA_AUTH_TYPE': 'Basic',
      });

  _testCatalog();
  _testTrackerType();
  if (hasPython) {
    _testJiraRouting(configureJira);
    _testGithubRouting(configureGitHub);
    _testGithubStatusAndErrors(configureGitHub);
    _testAdoRouting(configureAdo);
  }
}

TrackerSyncTools toolsOf(String? type) => TrackerSyncTools(trackerType: type);

void _testCatalog() {
  group('TrackerSyncTools catalog', () {
    test('exposes all nine tracker tool names', () {
      expect(toolsOf(null).handlers.keys.toSet(), {
        'tracker_get_ticket',
        'tracker_post_comment',
        'tracker_get_comments',
        'tracker_add_label',
        'tracker_remove_label',
        'tracker_move_to_status',
        'tracker_search',
        'tracker_assign_to',
        'tracker_create_ticket',
      });
    });

    test('tools are registered and resolvable in the default registry', () {
      final registry = createDefaultToolRegistry();
      for (final name in toolsOf(null).handlers.keys) {
        expect(registry.getTool(name)?.name, name, reason: name);
      }
    });

    test('definitions carry the generic arguments', () {
      final tool = createDefaultToolRegistry().getTool('tracker_post_comment')!;
      expect(tool.integration, 'tracker');
      expect(tool.requiredParams, ['key', 'comment']);
    });
  });
}

void _testTrackerType() {
  group('PropertyReader.getTrackerType', () {
    test('defaults to jira', () {
      expect(PropertyReader().getTrackerType(), 'jira');
    });

    test('accepts github/ado case-insensitively, jira fallback otherwise', () {
      PropertyReader.setOverrides({'TRACKER_TYPE': 'GitHub'});
      expect(PropertyReader().getTrackerType(), 'github');
      PropertyReader.setOverrides({'TRACKER_TYPE': ' ado '});
      expect(PropertyReader().getTrackerType(), 'ado');
      PropertyReader.setOverrides({'TRACKER_TYPE': 'gitlab'});
      expect(PropertyReader().getTrackerType(), 'jira');
    });
  });
}

void _testJiraRouting(void Function() configure) {
  group('routing → jira (default backend)', () {
    test('get_ticket forwards with the jira issue URL', () {
      configure();
      final req = reqOf(
          toolsOf(null).handlers['tracker_get_ticket']!({'key': 'PROJ-1'}));
      expect(req.method, 'GET');
      expect(req.path, contains('/issue/PROJ-1'));
    });

    test('search maps query → jql', () {
      configure();
      final result = toolsOf(null)
          .handlers['tracker_search']!({'query': 'labels = pr_approved'});
      // The echo fixture answers /search with a canned issues array that
      // carries the requested JQL — assert it reached the server.
      final issues = jsonDecode(result) as List<dynamic>;
      expect(
        (issues.first as Map)['jql'],
        'labels = pr_approved',
      );
    });

    test('assign_to maps user → accountId', () {
      configure();
      final req = reqOf(toolsOf(null)
          .handlers['tracker_assign_to']!({'key': 'P-1', 'user': 'u42'}));
      expect(req.body, {'accountId': 'u42'});
    });

    test('create_ticket maps title/type onto summary/issueType', () {
      configure();
      final req = reqOf(toolsOf(null).handlers['tracker_create_ticket']!({
        'project': 'PROJ',
        'type': 'Bug',
        'title': 'It breaks',
        'description': 'steps…',
      }));
      final body =
          (req.body! as Map<String, dynamic>)['fields'] as Map<String, dynamic>;
      expect(body['summary'], 'It breaks');
      expect((body['issuetype'] as Map)['name'], 'Bug');
    });
  });
}

void _testGithubRouting(
  void Function({String token, String? repository}) configure,
) {
  group('routing → github', () {
    test('get_ticket parses owner/repo#N into the issues API path', () {
      configure();
      final req = reqOf(toolsOf('github')
          .handlers['tracker_get_ticket']!({'key': 'epam/dmtools-dart#41'}));
      expect(req.method, 'GET');
      expect(req.path, '/repos/epam/dmtools-dart/issues/41');
    });

    test('falls back to GITHUB_REPOSITORY for bare numbers', () {
      configure(repository: 'octo/hello');
      final req = reqOf(
          toolsOf('github').handlers['tracker_get_ticket']!({'key': '7'}));
      expect(req.path, '/repos/octo/hello/issues/7');
    });

    test('post_comment posts the issue comment body', () {
      configure();
      final req = reqOf(toolsOf('github').handlers['tracker_post_comment']!(
        {'key': 'octo/hello#7', 'comment': 'hi'},
      ));
      expect(req.method, 'POST');
      expect(req.path, '/repos/octo/hello/issues/7/comments');
      expect(req.body, {'body': 'hi'});
    });

    test('search hits the search/issues endpoint with the encoded query', () {
      configure();
      final req = reqOf(toolsOf('github')
          .handlers['tracker_search']!({'query': 'is:open label=dark'}));
      expect(req.path, startsWith('/search/issues?q='));
    });
  });
}

/// GitHub backend: status transitions, labels, and error surfaces.
void _testGithubStatusAndErrors(
  void Function({String token, String? repository}) configure,
) {
  group('routing → github (status, labels, errors)', () {
    test('move_to_status maps Done → closed and Reopened → open', () {
      configure();
      final t = toolsOf('github');
      final closed = reqOf(t.handlers['tracker_move_to_status']!(
        {'key': 'octo/hello#7', 'status': 'Done'},
      ));
      expect(closed.method, 'PATCH');
      expect(closed.body, {'state': 'closed'});
      final open = reqOf(t.handlers['tracker_move_to_status']!(
        {'key': 'octo/hello#7', 'status': 'Reopened'},
      ));
      expect(open.body, {'state': 'open'});
    });

    test('unmappable status errors without an HTTP call', () {
      configure();
      final result = toolsOf('github').handlers['tracker_move_to_status']!(
        {'key': 'octo/hello#7', 'status': 'In Review'},
      );
      expect(errOf(result), contains('Cannot map GitHub status'));
    });

    test('remove_label issues DELETE against the label URL', () {
      configure();
      final req = reqOf(toolsOf('github').handlers['tracker_remove_label']!(
        {'key': 'octo/hello#7', 'label': 'bug'},
      ));
      expect(req.method, 'DELETE');
      expect(req.path, '/repos/octo/hello/issues/7/labels/bug');
    });

    test('missing token yields the not-configured error', () {
      configure(token: '');
      final result = toolsOf('github')
          .handlers['tracker_get_ticket']!({'key': 'octo/hello#7'});
      expect(errOf(result), 'GitHub not configured');
    });

    test('key without repo and no default yields a routing error', () {
      configure(repository: '');
      final result =
          toolsOf('github').handlers['tracker_get_ticket']!({'key': '41'});
      expect(errOf(result), contains('GITHUB_REPOSITORY'));
    });
  });
}

void _testAdoRouting(void Function() configure) {
  group('routing → ado', () {
    test('get_ticket maps key → work item id', () {
      configure();
      final req =
          reqOf(toolsOf('ado').handlers['tracker_get_ticket']!({'key': '42'}));
      expect(req.method, 'GET');
      expect(req.path, contains('/wit/workitems/42'));
    });

    test('ops without an ADO counterpart error cleanly', () {
      configure();
      final result = toolsOf('ado')
          .handlers['tracker_add_label']!({'key': '42', 'label': 'bug'});
      expect(
        errOf(result),
        'tracker_add_label is not yet supported for ADO',
      );
    });
  });
}
