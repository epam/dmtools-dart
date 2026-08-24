import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// Java-parity contract for 2xx responses with an empty body (204 No
/// Content): `GenericRequest.execute` returns the raw body string to JS —
/// `""` for the transitions POST, `"Success"` for `deleteTicket` when the
/// response is empty. The sync layer must never flag these as errors.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  if (!hasPython3()) return;
  _testMoveToStatus204();
  _testDeleteTicket204();
}

void _testMoveToStatus204() {
  group('SyncToolDispatcher Jira 2xx-empty-body contract', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}/dt-move',
        'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
        'JIRA_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('jira_move_to_status returns the JS empty string on 204', () {
      final result = dispatcher
          .execute('jira_move_to_status', {'key': 'PROJ-1', 'status': 'Done'})!;
      expect(result, '""');
    });
  });
}

void _testDeleteTicket204() {
  group('SyncToolDispatcher Jira delete 204 contract', () {
    late EchoServer server;
    late SyncToolDispatcher dispatcher;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'http://127.0.0.1:${server.port}/dt-del',
        'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
        'JIRA_AUTH_TYPE': 'Basic',
      });
      dispatcher = SyncToolDispatcher(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('jira_delete_ticket reports Success on 204', () {
      final result =
          dispatcher.execute('jira_delete_ticket', {'key': 'PROJ-1'})!;
      expect(result, '"Success"');
    });
  });
}
