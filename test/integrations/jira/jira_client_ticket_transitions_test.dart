import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Transition-with-resolution tests: moveToStatusWithResolution
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  moveToStatusWithResolutionTests();
  transitionsExecutorDispatchTests();
}

/// `jira_move_to_status_with_resolution` — transition + resolution body.
void moveToStatusWithResolutionTests() {
  group('JiraClient.moveToStatusWithResolution', () {
    test('POSTs transition with resolution in fields', () async {
      final f = mockJira((o) => routeByPath({
            '/issue/PROJ-1/transitions': _transitionsBody,
          }, o));
      await f.client.moveToStatusWithResolution('PROJ-1', 'Done', 'Fixed');
      expect(f.adapter.calls, hasLength(2));
      expect(f.adapter.calls[0].method, 'GET');
      final post = f.adapter.calls[1];
      expect(post.method, 'POST');
      final decoded = jsonDecode(post.data as String) as Map<String, dynamic>;
      expect(decoded['transition'], {'id': '31'});
      expect(decoded['fields'], {
        'resolution': {'name': 'Fixed'}
      });
    });

    test('returns explanation when no transition matches', () async {
      final f = mockJira((o) => '{"transitions":[]}');
      final result = await f.client
          .moveToStatusWithResolution('PROJ-1', 'Nonexistent', 'Fixed');
      expect(result, 'No transition found for status: Nonexistent');
      expect(f.adapter.calls.single.method, 'GET');
    });
  });
}

/// [JiraToolExecutor.execute] routes transition tool names.
void transitionsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (transitions with resolution)', () {
    test('routes jira_move_to_status_with_resolution', () async {
      final f = mockJira((o) =>
          routeByPath({'/issue/PROJ-1/transitions': _transitionsBody}, o));
      await executor(f).execute('jira_move_to_status_with_resolution', {
        'key': 'PROJ-1',
        'status': 'Done',
        'resolution': 'Fixed',
      });
      expect(f.adapter.calls.last.method, 'POST');
      final decoded = jsonDecode(f.adapter.calls.last.data as String)
          as Map<String, dynamic>;
      expect(decoded['fields'], {
        'resolution': {'name': 'Fixed'}
      });
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned `issue/{key}/transitions` body with one "Done" transition.
const _transitionsBody =
    '{"transitions":[{"id":"31","name":"Done","to":{"name":"Done"}}]}';
