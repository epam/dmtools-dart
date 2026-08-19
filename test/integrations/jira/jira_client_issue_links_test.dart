import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Issue-link tests: linkIssues, getIssueLinkTypes — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  linkIssuesTests();
  getIssueLinkTypesTests();
  issueLinksExecutorDispatchTests();
}

/// `jira_link_issues` — POST `issue/link`.
void linkIssuesTests() {
  group('JiraClient.linkIssues', () {
    test('POSTs to issue/link with correct body', () async {
      final f = mockJira((o) => '{}');
      await f.client.linkIssues('Blocks', 'PROJ-1', 'PROJ-2');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/issue/link'));
      expect(jsonDecode(call.data as String), {
        'type': {'name': 'Blocks'},
        'inwardIssue': {'key': 'PROJ-1'},
        'outwardIssue': {'key': 'PROJ-2'},
      });
    });
  });
}

/// `jira_get_issue_link_types` — GET `issue/link/type`.
void getIssueLinkTypesTests() {
  group('JiraClient.getIssueLinkTypes', () {
    test('returns the issueLinkTypes array', () async {
      final f =
          mockJira((o) => routeByPath({'/issue/link/type': _linkTypesBody}, o));
      final result = await f.client.getIssueLinkTypes();
      expect(result, hasLength(2));
      expect(result[0]['name'], 'Blocks');
      expect(result[1]['name'], 'Relates');
      expect(f.adapter.calls.single.method, 'GET');
    });

    test('returns an empty list when issueLinkTypes is absent', () async {
      final f = mockJira((o) => '{}');
      expect(await f.client.getIssueLinkTypes(), isEmpty);
    });
  });
}

/// [JiraToolExecutor.execute] routes issue-link tool names correctly.
void issueLinksExecutorDispatchTests() {
  group('JiraToolExecutor.execute (issue links)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_link_issues', () async {
      await executor.execute('jira_link_issues', {
        'linkType': 'Blocks',
        'inwardKey': 'PROJ-1',
        'outwardKey': 'PROJ-2',
      });
      expect(spy.calls, ['linkIssues:Blocks:PROJ-1:PROJ-2']);
    });

    test('routes jira_get_issue_link_types', () async {
      await executor.execute('jira_get_issue_link_types', {});
      expect(spy.calls, ['getIssueLinkTypes']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyJiraClient extends JiraClient {
  _SpyJiraClient(super.http);

  final List<String> calls = [];

  @override
  Future<void> linkIssues(
    String linkType,
    String inwardKey,
    String outwardKey,
  ) {
    calls.add('linkIssues:$linkType:$inwardKey:$outwardKey');
    return super.linkIssues(linkType, inwardKey, outwardKey);
  }

  @override
  Future<List<Map<String, dynamic>>> getIssueLinkTypes() {
    calls.add('getIssueLinkTypes');
    return super.getIssueLinkTypes();
  }
}

/// Canned `issue/link/type` body.
const _linkTypesBody =
    '{"issueLinkTypes":[{"id":"1","name":"Blocks"},{"id":"2","name":"Relates"}]}';
