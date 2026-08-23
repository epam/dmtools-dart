import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Issue-link tests: linkIssues, getIssueLinkTypes — plus executor dispatch.
///
/// Mirrors Java `JiraClient.linkIssueWithRelationship` / `getRelationships`:
/// GET `issueLinkType` resolves the relationship, then POST `issueLink`.
void main() {
  tearDown(PropertyReader.clearOverrides);
  linkIssuesTests();
  getIssueLinkTypesTests();
  issueLinksExecutorDispatchTests();
}

/// Canned `issueLinkType` body.
const _linkTypesBody = '{"issueLinkTypes":['
    '{"id":"1","name":"Blocks","inward":"blocks","outward":"is blocked by"},'
    '{"id":"2","name":"Relates","inward":"relates to","outward":"relates to"}'
    ']}';

/// `jira_link_issues` — POST `issueLink`.
void linkIssuesTests() {
  group('JiraClient.linkIssues', () {
    test('resolves by type name and POSTs to issueLink', () async {
      final f = mockJira(
        (o) => routeByPath({'/issueLinkType': _linkTypesBody}, o),
      );
      await f.client.linkIssues('PROJ-1', 'PROJ-2', 'Blocks');
      expect(f.adapter.calls, hasLength(2));
      final get = f.adapter.calls.first;
      expect(get.method, 'GET');
      expect(get.path, endsWith('/issueLinkType'));
      final post = f.adapter.calls.last;
      expect(post.method, 'POST');
      expect(post.path, endsWith('/issueLink'));
      expect(jsonDecode(post.data as String), {
        'type': {'name': 'Blocks'},
        'outwardIssue': {'key': 'PROJ-1'},
        'inwardIssue': {'key': 'PROJ-2'},
      });
    });

    test('resolves by outward description and swaps the sides', () async {
      final f = mockJira(
        (o) => routeByPath({'/issueLinkType': _linkTypesBody}, o),
      );
      await f.client.linkIssues('PROJ-1', 'PROJ-2', 'is blocked by');
      final post = f.adapter.calls.last;
      expect(jsonDecode(post.data as String), {
        'type': {'name': 'Blocks'},
        'inwardIssue': {'key': 'PROJ-1'},
        'outwardIssue': {'key': 'PROJ-2'},
      });
    });

    test('throws for an unknown relationship', () async {
      final f = mockJira(
        (o) => routeByPath({'/issueLinkType': _linkTypesBody}, o),
      );
      expect(
        () => f.client.linkIssues('PROJ-1', 'PROJ-2', 'Nonsense'),
        throwsStateError,
      );
    });
  });
}

/// `jira_get_issue_link_types` — GET `issueLinkType`.
void getIssueLinkTypesTests() {
  group('JiraClient.getIssueLinkTypes', () {
    test('returns the issueLinkTypes array', () async {
      final f = mockJira(
        (o) => routeByPath({'/issueLinkType': _linkTypesBody}, o),
      );
      final result = await f.client.getIssueLinkTypes();
      expect(result, hasLength(2));
      expect(result[0]['name'], 'Blocks');
      expect(result[1]['name'], 'Relates');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, endsWith('/issueLinkType'));
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
      spy = _SpyJiraClient(mockHttp((o) => _linkTypesBody).http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_link_issues with the Java argument names', () async {
      await executor.execute('jira_link_issues', {
        'sourceKey': 'PROJ-1',
        'anotherKey': 'PROJ-2',
        'relationship': 'Blocks',
      });
      // linkIssues resolves the relationship via getIssueLinkTypes first.
      expect(spy.calls, [
        'linkIssues:PROJ-1:PROJ-2:Blocks',
        'getIssueLinkTypes',
      ]);
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
  Future<String> linkIssues(
    String sourceKey,
    String anotherKey,
    String relationship,
  ) {
    calls.add('linkIssues:$sourceKey:$anotherKey:$relationship');
    return super.linkIssues(sourceKey, anotherKey, relationship);
  }

  @override
  Future<List<Map<String, dynamic>>> getIssueLinkTypes() {
    calls.add('getIssueLinkTypes');
    return super.getIssueLinkTypes();
  }
}
