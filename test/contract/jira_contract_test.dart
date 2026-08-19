/// L2 contract tests for the Jira tools — replays recorded Java tool
/// invocations against the Dart [JiraClient] over a mocked transport.
///
/// Fixtures live in `test/fixtures/contract/`; the framework in
/// `contract_test_helper.dart` drives them. Each fixture's `mock_response_body`
/// is served by the mock transport, the Dart method named by `tool_name` is
/// invoked with `request_args`, and its output is compared with
/// `expected_response`.
library;

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import '../contract/contract_test_helper.dart';
import '../integrations/jira/jira_test_support.dart';

void main() {
  tearDown(PropertyReader.clearOverrides);

  runContractCases(
    'test/fixtures/contract',
    {'jira_get_ticket', 'jira_post_comment', 'jira_test'},
    _replayJira,
  );
}

/// Replays a Jira fixture against a mocked [JiraClient].
///
/// Returns the Dart tool's output for comparison with the fixture's
/// `expected_response`.
Future<Object?> _replayJira(ContractFixture f) async {
  final fix = mockJira((_) => f.mockBody);
  switch (f.toolName) {
    case 'jira_get_ticket':
      return fix.client.getTicket(f.requestArgs['ticket_id'] as String);
    case 'jira_post_comment':
      await fix.client.postComment(
        f.requestArgs['ticket_id'] as String,
        f.requestArgs['comment'] as String,
      );
      return {'success': true};
    case 'jira_test':
      return fix.client.testConnection();
    default:
      throw StateError('no Jira replay registered for ${f.toolName}');
  }
}
