import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'xray_test_support.dart';

/// Coverage + behavior tests for the GraphQL- and Jira-backed [XrayClient]
/// tools ported from the Java Xray client.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  getTestDetailsTests();
  getPreconditionsTests();
  getPreconditionDetailsTests();
  addTestStepTests();
  addTestStepsTests();
  addPreconditionToTestTests();
  addPreconditionsToTestTests();
  createPreconditionTests();
  createPreconditionSyncTests();
  searchTicketsTests();
  searchTicketsFieldsTests();
}

/// Canned GraphQL test-details body with steps and one precondition.
final _gqlTestDetailsBody = jsonEncode({
  'data': {
    'getTests': {
      'results': [
        {
          'issueId': '101',
          'jira': {'key': 'TP-909', 'summary': 'Login test'},
          'testType': {'name': 'Manual'},
          'steps': [
            {
              'id': 1,
              'action': 'Open login',
              'data': '',
              'result': 'Form shown'
            },
          ],
          'preconditions': {
            'results': [
              {
                'issueId': '202',
                'definition': 'System ready',
                'jira': {'key': 'TP-910', 'summary': 'Ready'},
              },
            ],
          },
        },
      ],
    },
  },
});

/// `jira_xray_get_test_details` — POST `/api/v2/graphql`.
void getTestDetailsTests() {
  group('XrayClient.getTestDetails', () {
    test('auto-authenticates then queries getTests with limit 1', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': _gqlTestDetailsBody,
        }, o),
      );
      final result = await f.client.getTestDetails('TP-909');
      expect(result?['issueId'], '101');
      final gqlCall =
          f.adapter.calls.where((c) => c.path.endsWith('graphql')).single;
      expect(gqlCall.method, 'POST');
      final body = jsonDecode(gqlCall.data as String) as Map<String, dynamic>;
      expect(body['query'], contains('key=TP-909'));
      expect(body['query'], contains('limit: 1'));
      expect(body['query'], contains('preconditions(limit: 10)'));
    });

    test('returns null on GraphQL errors and empty results', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"errors":[{"message":"boom"}]}',
        }, o),
      );
      expect(await f.client.getTestDetails('TP-404'), isNull);
      final f2 = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"data":{"getTests":{"results":[]}}}',
        }, o),
      );
      expect(await f2.client.getTestDetails('TP-404'), isNull);
    });
  });
}

/// `jira_xray_get_preconditions` — preconditions of a test.
void getPreconditionsTests() {
  group('XrayClient.getPreconditions', () {
    test('returns the preconditions results list', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': _gqlTestDetailsBody,
        }, o),
      );
      final result = await f.client.getPreconditions('TP-909');
      expect(result.single['jira']['key'], 'TP-910');
    });

    test('returns empty list when the test has none', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"data":{"getTests":{"results":[{"issueId":"1"}]}}}',
        }, o),
      );
      expect(await f.client.getPreconditions('TP-909'), isEmpty);
    });
  });
}

/// `jira_xray_get_precondition_details` — Precondition definition query.
void getPreconditionDetailsTests() {
  group('XrayClient.getPreconditionDetails', () {
    test('queries Precondition issues with an inline fragment', () async {
      final body = jsonEncode({
        'data': {
          'getTests': {
            'results': [
              {
                'issueId': '202',
                'definition': 'System ready',
                'jira': {'key': 'TP-910'},
              },
            ],
          },
        },
      });
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': body,
        }, o),
      );
      final result = await f.client.getPreconditionDetails('TP-910');
      expect(result?['definition'], 'System ready');
      final gqlCall =
          f.adapter.calls.where((c) => c.path.endsWith('graphql')).single;
      final query =
          (jsonDecode(gqlCall.data as String) as Map<String, dynamic>)['query'];
      expect(query, contains('key=TP-910 AND issueType = Precondition'));
      expect(query, contains('... on Precondition { definition }'));
    });

    test('returns null when not found', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"data":{"getTests":{"results":[]}}}',
        }, o),
      );
      expect(await f.client.getPreconditionDetails('TP-404'), isNull);
    });
  });
}

/// `jira_xray_add_test_step` — GraphQL addTestStep mutation.
void addTestStepTests() {
  group('XrayClient.addTestStep', () {
    test('sends the mutation and returns the created step', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"data":{"addTestStep":{"id":"1","action":"a"}}}',
        }, o),
      );
      final result =
          await f.client.addTestStep('12345', 'Enter "user"', 'u', 'ok');
      expect(result?['id'], '1');
      final query = (jsonDecode(
        f.adapter.calls.last.data as String,
      ) as Map<String, dynamic>)['query'];
      expect(query, contains('addTestStep( issueId: "12345"'));
      expect(query, contains(r'action: "Enter \"user\""'));
    });

    test('throws on GraphQL errors', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"errors":[{"message":"nope"}]}',
        }, o),
      );
      await expectLater(
        f.client.addTestStep('12345', 'a'),
        throwsStateError,
      );
    });
  });
}

/// `jira_xray_add_test_steps` — batched addTestStep mutations.
void addTestStepsTests() {
  group('XrayClient.addTestSteps', () {
    test('adds every step and returns the created list', () async {
      var call = 0;
      final f = mockXray((o) {
        if (o.path.endsWith('authenticate')) return '"jwt-token"';
        call++;
        return '{"data":{"addTestStep":{"id":"$call"}}}';
      });
      final result = await f.client.addTestSteps('12345', [
        {'action': 'a1'},
        {'action': 'a2'},
      ]);
      expect(result.map((s) => s['id']).toList(), ['1', '2']);
    });

    test('rethrows when every step fails', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"errors":[{"message":"nope"}]}',
        }, o),
      );
      await expectLater(
        f.client.addTestSteps('12345', [
          {'action': 'a1'},
        ]),
        throwsStateError,
      );
    });
  });
}

/// `jira_xray_add_precondition_to_test` — GraphQL mutation with one ID.
void addPreconditionToTestTests() {
  group('XrayClient.addPreconditionToTest', () {
    test('sends a single-ID addPreconditionsToTest mutation', () async {
      final f = mockXray(
        (o) => routeByPath({
          'authenticate': '"jwt-token"',
          'graphql': '{"data":{"addPreconditionsToTest":{"__typename":"ok"}}}',
        }, o),
      );
      final result = await f.client.addPreconditionToTest('12345', '12346');
      expect(result?['__typename'], 'ok');
      final query = (jsonDecode(
        f.adapter.calls.last.data as String,
      ) as Map<String, dynamic>)['query'];
      expect(query, contains('addPreconditionsToTest( issueId: "12345"'));
      expect(query, contains(r'preconditionIssueIds: ["12346"]'));
    });

    test('returns null for empty IDs', () async {
      final f =
          mockXray((o) => routeByPath({'authenticate': '"jwt-token"'}, o));
      expect(await f.client.addPreconditionToTest('', '12346'), isNull);
      expect(f.adapter.calls, isEmpty); // no request leaves the client
    });
  });
}

/// `jira_xray_add_preconditions_to_test` — batched single-ID mutations.
void addPreconditionsToTestTests() {
  group('XrayClient.addPreconditionsToTest', () {
    test('keeps successes and skips failures', () async {
      var call = 0;
      final f = mockXray((o) {
        if (o.path.endsWith('authenticate')) return '"jwt-token"';
        call++;
        return call == 1
            ? '{"errors":[{"message":"nope"}]}'
            : '{"data":{"addPreconditionsToTest":{"__typename":"ok"}}}';
      });
      final result = await f.client.addPreconditionsToTest(
        '12345',
        ['12346', '12347'],
      );
      expect(result, hasLength(1));
      expect(result.single['__typename'], 'ok');
    });

    test('returns empty list for no IDs', () async {
      final f =
          mockXray((o) => routeByPath({'authenticate': '"jwt-token"'}, o));
      expect(await f.client.addPreconditionsToTest('12345', const []), isEmpty);
    });
  });
}

/// `jira_xray_create_precondition` — Jira creation plus X-ray definition.
void createPreconditionTests() {
  group('XrayClient.createPrecondition', () {
    test('creates the Jira issue then sets the definition via GraphQL',
        () async {
      final f = mockXrayWithJira(
        (o) => routeGraphQL({
          'updatePrecondition':
              '{"data":{"updatePrecondition":{"issueId":"101"}}}',
        }, o, fallback: _gqlTestDetailsBody),
        (o) => routeByPath({
          'issue': '{"key":"TP-1301","id":"501"}',
        }, o),
      );
      final key = await f.client.createPrecondition(
        'TP',
        'System is ready',
        description: 'All components initialized',
        steps: [
          {'action': 'boot', 'data': 'cfg', 'result': 'started'},
        ],
      );
      expect(key, 'TP-1301');
      final create = f.jira.calls.single;
      expect(create.method, 'POST');
      expect(jsonDecode(create.data as String), {
        'fields': {
          'project': {'key': 'TP'},
          'issuetype': {'name': 'Precondition'},
          'summary': 'System is ready',
          'description': 'All components initialized',
        },
      });
      final mutation = (jsonDecode(
        f.xray.calls.last.data as String,
      ) as Map<String, dynamic>)['query'];
      expect(mutation, contains('updatePrecondition( issueId: "101"'));
      expect(mutation, contains('Step 1: boot -> cfg -> started'));
    });
  });
}

/// `jira_xray_create_precondition` — issue-ID resolution fallbacks.
void createPreconditionSyncTests() {
  group('XrayClient.createPrecondition (sync fallbacks)', () {
    test('falls back to the Jira issue ID when X-ray has no issueId', () async {
      final f = mockXrayWithJira(
        (o) => routeGraphQL({
          'updatePrecondition': '{"data":{"updatePrecondition":{}}}',
        }, o,
            fallback:
                '{"data":{"getTests":{"results":[{"jira":{"key":"TP-1"}}]}}}'),
        (o) => routeByPath({
          'issue/TP-1301': '{"key":"TP-1301","id":"501","fields":{}}',
          'issue': '{"key":"TP-1301","id":"501"}',
        }, o),
      );
      final key = await f.client.createPrecondition(
        'TP',
        'No X-ray id',
        steps: [
          {'step': 'legacy action', 'expectedResult': 'legacy result'},
        ],
      );
      expect(key, 'TP-1301');
      final idCall =
          f.jira.calls.where((c) => c.queryParameters['fields'] == 'id').single;
      expect(idCall.path, endsWith('/issue/TP-1301'));
      final mutation = (jsonDecode(
        f.xray.calls.last.data as String,
      ) as Map<String, dynamic>)['query'];
      expect(mutation, contains('updatePrecondition( issueId: "501"'));
      expect(mutation, contains('Step 1: legacy action -> legacy result'));
    });

    test('returns the key even when the X-ray sync fails', () async {
      final f = mockXrayWithJira(
        (o) => routeGraphQL({}, o, fallback: '{"data":{}}'),
        (o) => routeByPath({
          'issue': '{"key":"TP-1302","id":"502","fields":{}}',
        }, o),
      );
      final key = await f.client.createPrecondition(
        'TP',
        'Broken sync',
        steps: [
          {'action': 'a'},
        ],
      );
      expect(key, 'TP-1302');
    });
  });
}

/// `jira_xray_search_tickets` — Jira JQL search plus X-ray enrichment.
void searchTicketsTests() {
  group('XrayClient.searchTickets', () {
    test('searches Jira and enriches Test issues with X-ray data', () async {
      final f = mockXrayWithJira(
        (o) => routeGraphQL({}, o, fallback: _gqlTestDetailsBody),
        (o) => routeByPath({
          'search/jql': jsonEncode({
            'issues': [
              {
                'key': 'TP-909',
                'fields': {
                  'issuetype': {'name': 'Test'},
                },
              },
              {
                'key': 'TP-100',
                'fields': {
                  'issuetype': {'name': 'Bug'},
                },
              },
            ],
          }),
          'issue/TP-910': jsonEncode({
            'key': 'TP-910',
            'fields': {
              'summary': 'Ready',
              'description': 'Everything up',
            },
          }),
        }, o),
      );
      final result = await f.client.searchTickets('project = TP');
      expect(result, hasLength(2));
      final fields = result[0]['fields'];
      expect(fields['issuetype']['name'], 'Test');
      expect(fields['xrayTestSteps'].single['action'], 'Open login');
      expect(fields['xrayTestType']['name'], 'Manual');
      expect(fields['xrayPreconditions'].single['jira']['key'], 'TP-910');
      expect(fields['xrayPreconditions'].single['summary'], 'Ready');
      expect(result[1]['fields'].containsKey('xrayTestSteps'), isFalse);
      final search =
          f.jira.calls.where((c) => c.path.contains('search')).single;
      expect(search.queryParameters['fields'], 'issuetype');
    });
  });
}

/// `jira_xray_search_tickets` — field handling and empty results.
void searchTicketsFieldsTests() {
  group('XrayClient.searchTickets (fields)', () {
    test('appends issuetype to the requested fields', () async {
      final f = mockXrayWithJira(
        (o) => routeGraphQL({}, o, fallback: '{"data":{}}'),
        (o) => routeByPath({
          'search/jql': '{"issues":[]}',
        }, o),
      );
      await f.client.searchTickets('project = TP', ['summary']);
      final search =
          f.jira.calls.where((c) => c.path.contains('search/jql')).single;
      expect(search.queryParameters['fields'], 'summary,issuetype');
    });

    test('skips enrichment when the Jira search is empty', () async {
      final f = mockXrayWithJira(
        (o) => routeGraphQL({}, o, fallback: _gqlTestDetailsBody),
        (o) => routeByPath({
          'search/jql': '{"issues":[]}',
        }, o),
      );
      expect(await f.client.searchTickets('project = TP'), isEmpty);
      expect(f.xray.calls.where((c) => c.path.endsWith('graphql')), isEmpty);
    });
  });
}
