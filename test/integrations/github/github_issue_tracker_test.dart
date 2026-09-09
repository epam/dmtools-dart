import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Tracker-backed issue family (Java `GitHubIssues.java`, dm.ai #543):
/// composite-key resolution against config defaults plus the four tracker
/// tools (`github_search_issues`, `github_move_issue_to_status`,
/// `github_assign_issue`, `github_reopen_issue`) and the retrofitted
/// issue/comment tools that now accept `key`.
void main() {
  tearDown(PropertyReader.clearOverrides);
  searchIssuesTests();
  reopenIssueTests();
  assignIssueTests();
  moveIssueToStatusTests();
  compositeKeyTests();
  trackerCatalogTests();
  trackerExecutorTests();
}

/// Config defaults mirroring Java `BasicGithub` (workspace/repository from
/// `SOURCE_GITHUB_WORKSPACE` / `SOURCE_GITHUB_REPOSITORY`).
const _defaults = {
  'SOURCE_GITHUB_TOKEN': 'gh-token-123',
  'SOURCE_GITHUB_BASE_PATH': 'https://github.example.com/api/v3',
  'SOURCE_GITHUB_WORKSPACE': 'epm',
  'SOURCE_GITHUB_REPOSITORY': 'dm.ai',
};

/// `github_search_issues` — GET `search/issues?q=...&per_page=100`.
void searchIssuesTests() {
  group('GithubClient.searchIssues', () {
    test('scopes the query with repo: when missing', () async {
      final f = mockGithub(
        (o) => routeByPath({'/search/issues': _searchBody}, o),
      );
      PropertyReader.setOverrides(_defaults);
      await f.client.searchIssues('is:open label:bug');
      final call = f.adapter.calls.single;
      expect(call.path, contains('/search/issues'));
      expect(call.queryParameters['q'],
          'repo:epm/dm.ai is:open label:bug');
      expect(call.queryParameters['per_page'], '100');
    });

    test('keeps a query that already scopes a repo', () async {
      final f = mockGithub(
        (o) => routeByPath({'/search/issues': _searchBody}, o),
      );
      await f.client.searchIssues('repo:other/repo is:open');
      expect(f.adapter.calls.single.queryParameters['q'],
          'repo:other/repo is:open');
    });

    test('skips the scope when no defaults are configured', () async {
      final f = mockGithub(
        (o) => routeByPath({'/search/issues': _searchBody}, o),
      );
      await f.client.searchIssues('is:open');
      expect(f.adapter.calls.single.queryParameters['q'], 'is:open');
    });

    test('explicit workspace/repository override the defaults', () async {
      PropertyReader.setOverrides(_defaults);
      final f = mockGithub(
        (o) => routeByPath({'/search/issues': _searchBody}, o),
      );
      await f.client.searchIssues('is:open', 'myorg', 'myrepo');
      expect(f.adapter.calls.single.queryParameters['q'],
          'repo:myorg/myrepo is:open');
    });
  });
}

/// `github_reopen_issue` — PATCH `repos/{o}/{r}/issues/{n}` state open.
void reopenIssueTests() {
  group('GithubClient.reopenIssue', () {
    test('PATCHes state open', () async {
      final f = mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
      await f.client.reopenIssue('epm', 'dm.ai', 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7'));
      expect(jsonDecode(call.data as String), {'state': 'open'});
    });
  });
}

/// `github_assign_issue` — POST `repos/{o}/{r}/issues/{n}/assignees`.
void assignIssueTests() {
  group('GithubClient.assignIssue', () {
    test('POSTs the single-element assignees array', () async {
      final f =
          mockGithub((o) => routeByPath({'/assignees': _issueBody}, o));
      await f.client.assignIssue('epm', 'dm.ai', 7, 'octocat');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/assignees'));
      expect(jsonDecode(call.data as String), {
        'assignees': ['octocat']
      });
    });

    test('resolves a composite key against config defaults', () async {
      PropertyReader.setOverrides(_defaults);
      final f =
          mockGithub((o) => routeByPath({'/assignees': _issueBody}, o));
      await f.client.assignIssue(null, null, null, 'octocat',
          key: 'myorg/myrepo#42');
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/myorg/myrepo/issues/42/assignees'),
      );
    });
  });
}

/// `github_move_issue_to_status` — close / reopen / label semantics.
void moveIssueToStatusTests() {
  group('GithubClient.moveIssueToStatus', () {
    test('done-family statuses close the issue', () async {
      for (final s in const ['Done', 'CLOSED', 'completed', 'resolved']) {
        final f =
            mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
        await f.client.moveIssueToStatus('epm', 'dm.ai', 7, s);
        final call = f.adapter.calls.single;
        expect(call.method, 'PATCH', reason: s);
        expect(jsonDecode(call.data as String), {'state': 'closed'},
            reason: s);
      }
    });

    test('open-family statuses reopen the issue', () async {
      for (final s in const [
        'open',
        'reopened',
        'REOPEN',
        'todo',
        'backlog',
        'in progress'
      ]) {
        final f =
            mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
        await f.client.moveIssueToStatus('epm', 'dm.ai', 7, s);
        final call = f.adapter.calls.single;
        expect(call.method, 'PATCH', reason: s);
        expect(jsonDecode(call.data as String), {'state': 'open'}, reason: s);
      }
    });

    test('any other status is applied as an issue label', () async {
      final f = mockGithub((o) => routeByPath({'/labels': '[]'}, o));
      await f.client.moveIssueToStatus('epm', 'dm.ai', 7, 'In Review');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels'));
      expect(jsonDecode(call.data as String), {
        'labels': ['In Review']
      });
    });

    test('blank statusName is rejected', () async {
      final f = mockGithub((o) => '{}');
      expect(
        () => f.client.moveIssueToStatus('epm', 'dm.ai', 7, '  '),
        throwsArgumentError,
      );
      expect(f.adapter.calls, isEmpty);
    });
  });
}

/// Composite-key parsing shared by the retrofitted issue tools.
void compositeKeyTests() {
  group('composite key resolution', () {
    test('github_get_issue accepts owner/repo#123', () async {
      final f = mockGithub((o) => routeByPath({'/issues/12': _issueBody}, o));
      await f.client.getIssue(null, null, null, key: 'myorg/myrepo#12');
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/myorg/myrepo/issues/12'),
      );
    });

    test('github_get_issue accepts a bare number with defaults', () async {
      final f = mockGithub((o) => routeByPath({'/issues/9': _issueBody}, o));
      PropertyReader.setOverrides(_defaults);
      await f.client.getIssue(null, null, null, key: '9');
      expect(f.adapter.calls.single.path, endsWith('/repos/epm/dm.ai/issues/9'));
    });

    test('a composite key overrides explicit parts (Java behavior)', () async {
      final f = mockGithub((o) => routeByPath({'/issues/3': _issueBody}, o));
      PropertyReader.setOverrides(_defaults);
      await f.client.getIssue('epm', 'dm.ai', '3', key: 'other/repo#99');
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/other/repo/issues/99'),
      );
    });

    test('an unparseable key is rejected', () async {
      final f = mockGithub((o) => '{}');
      expect(
        () => f.client.getIssue(null, null, null, key: 'not-a-key'),
        throwsArgumentError,
      );
      expect(f.adapter.calls, isEmpty);
    });

    test('missing everything is rejected with the Java message', () async {
      final f = mockGithub((o) => '{}');
      await expectLater(
        f.client.getIssue(null, null, null),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            "Issue reference requires owner/repo/number or a composite key "
                "'owner/repo#123'.",
          ),
        ),
      );
    });

    test('github_close_issue accepts a composite key', () async {
      final f = mockGithub((o) => routeByPath({'/issues/5': _issueBody}, o));
      await f.client.closeIssue(null, null, null, key: 'myorg/myrepo#5');
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/myorg/myrepo/issues/5'));
      expect(jsonDecode(call.data as String), {'state': 'closed'});
    });

    test('github_add_labels accepts a composite key', () async {
      final f = mockGithub((o) => routeByPath({'/labels': '[]'}, o));
      await f.client
          .addLabels(null, null, null, ['bug'], key: 'myorg/myrepo#5');
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/myorg/myrepo/issues/5/labels'),
      );
    });

    test('github_remove_label accepts a composite key', () async {
      final f = mockGithub((o) => routeByPath({'/labels/bug': ''}, o));
      await f.client
          .removeLabel(null, null, null, 'bug', key: 'myorg/myrepo#5');
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/myorg/myrepo/issues/5/labels/bug'),
      );
    });

    test('github_create_comment accepts a composite key', () async {
      final f =
          mockGithub((o) => routeByPath({'/comments': _commentBody}, o));
      await f.client.createComment(null, null, null, 'Looks good!',
          key: 'myorg/myrepo#5');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/repos/myorg/myrepo/issues/5/comments'),
      );
      expect(jsonDecode(call.data as String), {'body': 'Looks good!'});
    });

    test('github_create_issue accepts the owner/repo project key', () async {
      final f = mockGithub((o) => routeByPath({'/issues': _issueBody}, o));
      await f.client.createIssue(null, null, 'Bug', key: 'myorg/myrepo');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/myorg/myrepo/issues'));
      expect(jsonDecode(call.data as String), {'title': 'Bug'});
    });

    test('github_create_issue falls back to config defaults', () async {
      final f = mockGithub((o) => routeByPath({'/issues': _issueBody}, o));
      PropertyReader.setOverrides(_defaults);
      await f.client.createIssue(null, null, 'Bug');
      expect(f.adapter.calls.single.path, endsWith('/repos/epm/dm.ai/issues'));
    });

    test('github_create_issue without any repo reference fails', () async {
      final f = mockGithub((o) => '{}');
      expect(
        () => f.client.createIssue(null, null, 'Bug'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          "github_create_issue requires owner/repo or a composite "
              "key/project 'owner/repo'.",
        )),
      );
    });
  });
}

/// Catalog metadata: names, Java alias sets, param shapes.
void trackerCatalogTests() {
  final registry = createDefaultToolRegistry();

  ToolDefinition tool(String name) => registry.getTool(name)!;

  group('github tracker catalog', () {
    test('registers the four new tracker tools', () {
      for (final name in const [
        'github_search_issues',
        'github_move_issue_to_status',
        'github_assign_issue',
        'github_reopen_issue',
      ]) {
        expect(registry.hasTool(name), isTrue, reason: name);
      }
    });

    test('carries the Java tracker alias set', () {
      expect(tool('github_search_issues').aliases,
          ['tracker_search']);
      expect(tool('github_move_issue_to_status').aliases,
          ['tracker_move_to_status']);
      expect(tool('github_assign_issue').aliases,
          ['tracker_assign_ticket']);
      expect(tool('github_get_issue').aliases,
          ['source_code_get_issue', 'tracker_get_ticket']);
      expect(tool('github_create_issue').aliases, ['tracker_create_ticket']);
      expect(tool('github_get_pr_comments').aliases,
          ['source_code_get_pr_comments', 'tracker_get_comments']);
      expect(tool('github_create_comment').aliases, ['tracker_post_comment']);
    });

    test('tracker_* aliases resolve through DEFAULT_TRACKER=github', () {
      for (final entry in const {
        'tracker_search': 'github_search_issues',
        'tracker_move_to_status': 'github_move_issue_to_status',
        'tracker_assign_ticket': 'github_assign_issue',
        'tracker_get_ticket': 'github_get_issue',
        'tracker_create_ticket': 'github_create_issue',
        'tracker_get_comments': 'github_get_pr_comments',
        'tracker_post_comment': 'github_create_comment',
      }.entries) {
        expect(
          registry.resolveToolAlias(
            entry.key,
            defaultTracker: 'github',
          ),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('search_issues exposes the query alias set', () {
      final t = tool('github_search_issues');
      final query = t.params.first;
      expect(query.name, 'query');
      expect(query.aliases, ['jql', 'wiql']);
      expect(query.required, isTrue);
      expect(
        t.params.where((p) => p.name == 'workspace' || p.name == 'repository'),
        everyElement(isA<ToolParam>()
            .having((p) => p.required, 'required', isFalse)),
      );
    });

    test('move_issue_to_status exposes the status aliases', () {
      final t = tool('github_move_issue_to_status');
      final status = t.params.first;
      expect(status.name, 'statusName');
      expect(status.aliases, ['state', 'status']);
      for (final name in const ['owner', 'repo', 'number', 'key']) {
        expect(
          t.params.any((p) => p.name == name && !p.required),
          isTrue,
          reason: name,
        );
      }
    });

    test('assign_issue exposes the user aliases', () {
      final t = tool('github_assign_issue');
      expect(t.params.first.name, 'user');
      expect(t.params.first.aliases, ['accountId', 'assignee', 'userName']);
    });

    test('existing issue tools accept the optional composite key', () {
      for (final name in const [
        'github_get_issue',
        'github_close_issue',
        'github_add_labels',
        'github_remove_label',
        'github_create_comment',
        'github_get_pr_comments',
      ]) {
        final t = tool(name);
        expect(
          t.params.any((p) => p.name == 'key' && !p.required),
          isTrue,
          reason: '$name lacks the key param',
        );
      }
    });

    test('github_create_issue gains summary/description/project aliases',
        () {
      final t = tool('github_create_issue');
      final byName = {for (final p in t.params) p.name: p};
      expect(byName['title']!.aliases, ['summary']);
      expect(byName['body']!.aliases, ['description']);
      expect(byName['key']!.aliases, ['project']);
      expect(byName['owner']!.required, isFalse);
      expect(byName['repo']!.required, isFalse);
    });

    test('applyParamAliases maps the tracker aliases onto canonical names',
        () {
      final args = tool('github_search_issues')
          .applyParamAliases({'jql': 'is:open'});
      expect(args['query'], 'is:open');

      final moved = tool('github_move_issue_to_status')
          .applyParamAliases({'state': 'Done', 'number': 7});
      expect(moved['statusName'], 'Done');
      expect(moved['number'], 7);

      final assigned = tool('github_assign_issue')
          .applyParamAliases({'assignee': 'octocat'});
      expect(assigned['user'], 'octocat');

      final created = tool('github_create_issue')
          .applyParamAliases({'summary': 'Bug', 'project': 'o/r'});
      expect(created['title'], 'Bug');
      expect(created['key'], 'o/r');
    });
  });
}

/// Executor routing for the tracker tools.
void trackerExecutorTests() {
  group('GithubToolExecutor.execute (tracker tools)', () {
    test('routes github_search_issues', () async {
      final f = mockGithub(
        (o) => routeByPath({'/search/issues': _searchBody}, o),
      );
      await GithubToolExecutor(f.client)
          .execute('github_search_issues', {'query': 'is:open'});
      expect(f.adapter.calls.single.queryParameters['per_page'], '100');
    });

    test('routes github_reopen_issue with a coerced number', () async {
      final f = mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
      await GithubToolExecutor(f.client).execute('github_reopen_issue',
          {'owner': 'epm', 'repo': 'dm.ai', 'number': '7'});
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(jsonDecode(call.data as String), {'state': 'open'});
    });

    test('routes github_assign_issue', () async {
      final f =
          mockGithub((o) => routeByPath({'/assignees': _issueBody}, o));
      await GithubToolExecutor(f.client).execute('github_assign_issue', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'number': 7,
        'user': 'octocat',
      });
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'assignees': ['octocat']
      });
    });

    test('routes github_move_issue_to_status onto a label add', () async {
      final f = mockGithub((o) => routeByPath({'/labels': '[]'}, o));
      await GithubToolExecutor(f.client).execute('github_move_issue_to_status',
          {'owner': 'epm', 'repo': 'dm.ai', 'number': 7, 'statusName': 'QA'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/issues/7/labels'),
      );
    });

    test('routes github_get_issue through a composite key', () async {
      final f = mockGithub((o) => routeByPath({'/issues/12': _issueBody}, o));
      await GithubToolExecutor(f.client)
          .execute('github_get_issue', {'key': 'myorg/myrepo#12'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/myorg/myrepo/issues/12'),
      );
    });

    test('routes github_create_comment through a composite key', () async {
      final f =
          mockGithub((o) => routeByPath({'/comments': _commentBody}, o));
      await GithubToolExecutor(f.client).execute('github_create_comment',
          {'key': 'myorg/myrepo#12', 'body': 'hi'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/myorg/myrepo/issues/12/comments'),
      );
    });
  });
}

/// Canned search-result body.
const _searchBody =
    '{"total_count":1,"items":[{"number":1,"title":"bug"}]}';

/// Canned issue body.
const _issueBody = '{"number":7,"title":"Bug"}';

/// Canned comment body.
const _commentBody = '{"id":99,"body":"hi"}';
