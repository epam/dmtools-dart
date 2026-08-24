import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_http_client.dart';
import 'package:dmtools/src/js/sync_tools/jira_sync_tools.dart';
import 'package:test/test.dart';

/// Shared fixtures for the fixture-server groups (each group's setUp
/// rebinds the server and tools).
late JiraFixtureServer server;
late JiraSyncTools tools;
late Directory tmp;

/// Tests for [JiraSyncTools] — the public sync executors for `jira_*` tools.
///
/// Server-dependent tests run a Python fixture server subprocess (same
/// constraint as test/js/sync_tool_dispatch_test.dart: the Dart event loop
/// is frozen during `Process.runSync('curl', …)`).
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  _testHandlerCatalog();
  _testDispatchErrors();
  if (hasPython3()) {
    _testNewWriteTools();
    _testLinkIssues();
    _testAttachFile();
    _testFieldCustomCode();
  }
}

/// Manages the Python fixture-server subprocess lifecycle.
class JiraFixtureServer {
  Process? _process;

  /// The bound port (valid after [start]).
  int port = 0;

  /// Starts the fixture server on an ephemeral port.
  Future<void> start() async {
    final script = '${Directory.current.path}'
        '/test/js/sync_tools/jira_fixture_server.py';
    _process = await Process.start('python3', [script, '0']);
    final firstLine = await _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    port = int.parse(firstLine.trim());
  }

  /// Kills the server process.
  void stop() => _process?.kill();
}

/// Whether `python3` is available on this system.
bool hasPython3() {
  try {
    return Process.runSync('which', ['python3']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// The `{"error": …}` payload decoded from a [JiraSyncTools] result.
Map<String, dynamic> errOf(String result) =>
    jsonDecode(result) as Map<String, dynamic>;

/// Starts [server] and points the Jira config at it.
void configureJira(JiraFixtureServer server, {String token = 'tok'}) {
  PropertyReader.setOverrides({
    'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}',
    'JIRA_LOGIN_PASS_TOKEN': token,
    'JIRA_AUTH_TYPE': 'Basic',
  });
}

void _testHandlerCatalog() {
  group('JiraSyncTools handler catalog', () {
    test('exposes the canonical and alias jira tool names', () {
      final names = const JiraSyncTools().handlers.keys.toSet();
      expect(
          names,
          containsAll([
            'jira_get_ticket',
            'jira_post_comment',
            'jira_search_by_jql',
            'jira_add_label',
            'jira_remove_label',
            'jira_move_to_status',
            'jira_get_comments',
            'jira_update_field',
            'jira_update_description',
            'jira_get_transitions',
            'jira_get_my_profile',
            'jira_delete_ticket',
            'jira_create_ticket_basic',
            'jira_create_ticket',
            'jira_assign_ticket_to',
            'jira_assign_to',
            'jira_assign',
            'tracker_assign_ticket',
            'jira_set_priority',
            'jira_create_ticket_with_parent',
            'jira_create_ticket_with_json',
            'jira_link_issues',
            'tracker_link_tickets',
            'jira_get_field_custom_code',
            'jira_attach_file_to_ticket',
          ]));
    });
  });
}

void _testDispatchErrors() {
  group('JiraSyncTools dispatch errors', () {
    tearDown(PropertyReader.clearOverrides);

    test('unknown tool name yields the unsupported-tool error', () {
      expect(
        errOf(const JiraSyncTools().dispatch('jira_mystery', {})),
        {'error': 'Unsupported Jira tool: jira_mystery'},
      );
    });

    test('blank config yields the not-configured error', () {
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': '',
        'JIRA_LOGIN_PASS_TOKEN': '',
      });
      expect(
        errOf(const JiraSyncTools().dispatch('jira_set_priority', {})),
        {'error': 'Jira not configured'},
      );
    });
  });
}

void _testNewWriteTools() {
  group('JiraSyncTools new write tools', () {
    setUp(() async {
      server = JiraFixtureServer();
      await server.start();
      configureJira(server);
      tools = JiraSyncTools();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    testnewwritetools_p1();
    testnewwritetools_p2();
  });
}

void testnewwritetools_p1() {
  test('jira_set_priority PUTs the priority name', () {
    final body = jsonDecode(
      tools.dispatch('jira_set_priority', {'key': 'P-1', 'priority': 'High'}),
    );
    expect(body['method'], 'PUT');
    expect(body['path'], '/rest/api/latest/issue/P-1');
    final fields = jsonDecode(body['body'] as String)['fields'];
    expect(fields['priority'], {'name': 'High'});
  });

  test('jira_assign_ticket_to PUTs accountId to the assignee endpoint', () {
    final body = jsonDecode(tools.dispatch('jira_assign_ticket_to', {
      'key': 'P-1',
      'accountId': 'acc-7',
    }));
    expect(body['method'], 'PUT');
    expect(body['path'], '/rest/api/latest/issue/P-1/assignee');
    expect(jsonDecode(body['body'] as String)['accountId'], 'acc-7');
  });

  test('tracker_assign_ticket alias routes to the assign executor', () {
    final body = jsonDecode(tools.dispatch('tracker_assign_ticket', {
      'key': 'P-1',
      'accountId': 'acc-7',
    }));
    expect(body['path'], '/rest/api/latest/issue/P-1/assignee');
  });

  test('jira_create_ticket_with_parent POSTs parent key and description', () {
    final body = jsonDecode(tools.dispatch('jira_create_ticket_with_parent', {
      'project': 'PROJ',
      'issueType': 'Sub-task',
      'summary': 'Do the thing',
      'description': 'Details here',
      'parentKey': 'EPIC-1',
    }));
    expect(body['method'], 'POST');
    expect(body['path'], '/rest/api/latest/issue');
    final fields = jsonDecode(body['body'] as String)['fields'];
    expect(fields['parent'], {'key': 'EPIC-1'});
    expect(fields['description'], 'Details here');
  });
}

void testnewwritetools_p2() {
  test('jira_create_ticket_with_json merges fieldsJson over project', () {
    final body = jsonDecode(tools.dispatch('jira_create_ticket_with_json', {
      'project': 'PROJ',
      'fieldsJson': {
        'summary': 'From JSON',
        'issuetype': {'name': 'Bug'},
      },
    }));
    expect(body['method'], 'POST');
    final fields = jsonDecode(body['body'] as String)['fields'];
    expect(fields['project'], {'key': 'PROJ'});
    expect(fields['summary'], 'From JSON');
    expect(fields['issuetype'], {'name': 'Bug'});
  });

  test('jira_create_ticket_with_json accepts a JSON-string fieldsJson', () {
    final body = jsonDecode(tools.dispatch('jira_create_ticket_with_json', {
      'project': 'PROJ',
      'fieldsJson': '{"summary": "FromString"}',
    }));
    final fields = jsonDecode(body['body'] as String)['fields'];
    expect(fields['summary'], 'FromString');
  });

  test('jira_create_ticket alias routes to the create executor', () {
    final body = jsonDecode(tools.dispatch('jira_create_ticket', {
      'project': 'PROJ',
      'issueType': 'Task',
      'summary': 'S',
    }));
    expect(body['method'], 'POST');
    expect(body['path'], '/rest/api/latest/issue');
  });
}

void _testLinkIssues() {
  group('JiraSyncTools jira_link_issues', () {
    setUp(() async {
      server = JiraFixtureServer();
      await server.start();
      configureJira(server);
      tools = JiraSyncTools();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    testlinkissues_p1();
  });
}

void testlinkissues_p1() {
  test('relationship matched by type name maps source to outward', () {
    final body = jsonDecode(tools.dispatch('jira_link_issues', {
      'sourceKey': 'EPIC-1',
      'anotherKey': 'STORY-1',
      'relationship': 'Blocks',
    }));
    expect(body['method'], 'POST');
    expect(body['path'], '/rest/api/latest/issueLink');
    expect(jsonDecode(body['body'] as String), {
      'type': {'name': 'Blocks'},
      'outwardIssue': {'key': 'EPIC-1'},
      'inwardIssue': {'key': 'STORY-1'},
    });
  });

  test('relationship matched by inward description maps the same way', () {
    final body = jsonDecode(tools.dispatch('jira_link_issues', {
      'sourceKey': 'A-1',
      'anotherKey': 'B-1',
      'relationship': 'blocks',
    }));
    final sent = jsonDecode(body['body'] as String);
    expect(sent['outwardIssue'], {'key': 'A-1'});
    expect(sent['inwardIssue'], {'key': 'B-1'});
  });

  test('relationship matched by outward description swaps the sides', () {
    final body = jsonDecode(tools.dispatch('jira_link_issues', {
      'sourceKey': 'A-1',
      'anotherKey': 'B-1',
      'relationship': 'is blocked by',
    }));
    final sent = jsonDecode(body['body'] as String);
    expect(sent['inwardIssue'], {'key': 'A-1'});
    expect(sent['outwardIssue'], {'key': 'B-1'});
  });

  test('unknown relationship yields an error', () {
    expect(
      errOf(tools.dispatch('jira_link_issues', {
        'sourceKey': 'A-1',
        'anotherKey': 'B-1',
        'relationship': 'Nonsense',
      })),
      {'error': 'Unknown relationship type: Nonsense'},
    );
  });
}

void _testAttachFile() {
  group('JiraSyncTools jira_attach_file_to_ticket', () {
    setUp(() async {
      server = JiraFixtureServer();
      await server.start();
      configureJira(server);
      tools = JiraSyncTools();
      tmp = await Directory.systemTemp.createTemp('dmtools_jira_attach_');
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
      tmp.deleteSync(recursive: true);
    });

    testattachfile_p1();
    testattachfile_p2();
  });
}

void testattachfile_p1() {
  test('uploads via multipart POST and reports success', () {
    final file = File('${tmp.path}/doc.md')..writeAsStringSync('# report body');
    final result = tools.dispatch('jira_attach_file_to_ticket', {
      'ticketKey': 'P-1',
      'name': 'doc.md',
      'contentType': 'text/markdown',
      'filePath': file.path,
    });
    expect(jsonDecode(result), {
      'status': 'success',
      'message': "File 'doc.md' attached to ticket P-1",
      'ticket': 'P-1',
      'fileName': 'doc.md',
    });
    final last = _lastRequest(server);
    expect(last['line'], 'POST /rest/api/latest/issue/P-1/attachments');
    expect(last['body'] as String, contains('name="doc.md"'));
    expect(last['body'] as String, contains('text/markdown'));
  });

  test('defaults the content type to image/*', () {
    final file = File('${tmp.path}/pic.png')..writeAsBytesSync([1, 2, 3]);
    tools.dispatch('jira_attach_file_to_ticket', {
      'ticketKey': 'P-1',
      'name': 'pic.png',
      'filePath': file.path,
    });
    final last = _lastRequest(server);
    expect(last['body'] as String, contains('image/*'));
  });

  test('skips the upload when an attachment with the name exists', () {
    final file = File('${tmp.path}/doc.md')..writeAsStringSync('x');
    final result = tools.dispatch('jira_attach_file_to_ticket', {
      'ticketKey': '__attached',
      'name': 'doc.md',
      'contentType': 'text/markdown',
      'filePath': file.path,
    });
    expect(jsonDecode(result)['status'], 'success');
    // The last request is the attachment-listing GET — no POST happened.
    expect(
      _lastRequest(server)['line'],
      'GET /rest/api/latest/issue/__attached?fields=attachment,summary',
    );
  });
}

void testattachfile_p2() {
  test('missing local file yields an error', () {
    expect(
      errOf(tools.dispatch('jira_attach_file_to_ticket', {
        'ticketKey': 'P-1',
        'name': 'nope.md',
        'filePath': '${tmp.path}/nope.md',
      })),
      {'error': 'File does not exist: ${tmp.path}/nope.md'},
    );
  });
}

/// Fetches the fixture server's record of the last served request.
Map<String, dynamic> _lastRequest(JiraFixtureServer server) {
  final resp = SyncHttpClient.get('http://127.0.0.1:${server.port}/__last');
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

void _testFieldCustomCode() {
  group('JiraSyncTools jira_get_field_custom_code', () {
    setUp(() async {
      server = JiraFixtureServer();
      await server.start();
      tools = JiraSyncTools();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('returns the best matching custom field id as a JSON string', () {
      configureJira(server);
      final result = tools.dispatch('jira_get_field_custom_code', {
        'project': 'PROJ',
        'fieldName': 'Story Points',
      });
      // JSON string: the C bridge unmarshals it to the JS string value.
      expect(result, '"customfield_10002"');
    });

    test('no matching field yields JSON null (Java returns null)', () {
      configureJira(server);
      final result = tools.dispatch('jira_get_field_custom_code', {
        'project': 'PROJ',
        'fieldName': 'Nope Field',
      });
      expect(result, 'null');
    });

    test('falls back to createmeta when the field listing fails', () {
      // The fixture server 503s /field when the token contains 'fieldfail';
      // the createmeta fallback body is an object, which — as in Java —
      // yields no array parse and therefore no field id.
      configureJira(server, token: 'fieldfail');
      final result = tools.dispatch('jira_get_field_custom_code', {
        'project': 'PROJ',
        'fieldName': 'Story Points',
      });
      expect(result, 'null');
    });
  });
}
