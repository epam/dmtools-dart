import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// `jira_move_to_status` error semantics — gh-146 review thread 3.
///
/// The legacy code swallowed transitions-fetch failures into an empty
/// list, so a sandbox transient (a 5xx or a truncated body on the GET)
/// surfaced as the misleading "No transition found for status: …" — which
/// is what flaked the integration job on main before 38fee63. Transport
/// failures must carry their real reason; the legacy text stays reserved
/// for the genuine empty-transitions case.
///
/// Fixtures live in test_echo_server.py under the `dt-move*` markers.
void main() {
  moveErrorSemanticsTests();
}

void moveErrorSemanticsTests() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  group('SyncToolDispatcher Jira move_to_status error semantics', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
        'JIRA_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('returns error when no transitions found (genuine empty case)', () {
      final result = dispatcher.execute('jira_move_to_status', {
        'key': 'PROJ-1',
        'statusName': 'In Progress',
      });
      expect(
        jsonDecode(result!),
        {'error': 'No transition found for status: In Progress'},
      );
    });

    test('surfaces a failed transitions fetch', () {
      final result = dispatcher.execute('jira_move_to_status', {
        'key': 'dt-movefail-1',
        'statusName': 'In Progress',
      });
      final error = jsonDecode(result!)['error'] as String;
      expect(error, contains('HTTP 500'));
      expect(error, contains('boom'));
      expect(error, isNot(contains('No transition found')));
    });

    test('surfaces a malformed transitions body', () {
      final result = dispatcher.execute('jira_move_to_status', {
        'key': 'dt-movebadjson-1',
        'statusName': 'In Progress',
      });
      final error = jsonDecode(result!)['error'] as String;
      expect(error, contains('malformed JSON'));
      expect(error, isNot(contains('No transition found')));
    });

    test('surfaces a failed transition POST', () {
      final result = dispatcher.execute('jira_move_to_status', {
        'key': 'dt-movepostfail-1',
        'statusName': 'Done',
      });
      final error = jsonDecode(result!)['error'] as String;
      expect(error, contains('HTTP 500'));
      expect(error, contains('nope'));
    });
  });
}
