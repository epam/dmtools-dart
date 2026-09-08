import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  routingTests();
  envExpansionTests();
  fetchTests();
  singleIssueTests();
}

void routingTests() {
  group('looksLikeGithubQuery', () {
    test('GitHub search tokens are recognized', () {
      for (final q in [
        'repo:o/r is:issue is:open label:bug',
        'is:issue assignee:ai-teammate',
        'is:pr is:open',
        'type:issue state:open',
      ]) {
        expect(looksLikeGithubQuery(q), isTrue, reason: q);
      }
    });
    test('Jira JQL is not misrouted', () {
      for (final q in [
        'project = JD AND status = Open ORDER BY priority',
        'assignee = currentUser() AND labels is not empty',
      ]) {
        expect(looksLikeGithubQuery(q), isFalse, reason: q);
      }
    });
    test('direct-issue forms route to the GitHub source', () {
      expect(looksLikeGithubQuery('repo:o/r#42'), isTrue);
      expect(looksLikeGithubQuery('#42'), isTrue);
      expect(looksLikeGithubQuery('GH-42'), isTrue);
      expect(looksLikeGithubQuery('42'), isTrue);
    });
  });
}

void envExpansionTests() {
  group('expandEnvRefs', () {
    test('expands env refs from the provided map', () {
      expect(
        expandEnvRefs(r'repo:${GITHUB_REPOSITORY} is:issue',
            {'GITHUB_REPOSITORY': 'o/r'}),
        'repo:o/r is:issue',
      );
    });
    test('unresolved refs become empty strings', () {
      expect(expandEnvRefs(r'repo:${NOPE_X} is:issue', {}), 'repo: is:issue');
    });
  });
}

/// Fake GitHub REST API: records every requested path and answers the
/// canned search/issue/comments payloads for `o/r` issues 7 and 42.
Future<Map<String, dynamic>> fakeGithubApi(
  List<String> calls,
  String path,
) async {
  calls.add(path);
  if (path.startsWith('/search/issues')) {
    return {
      'items': [
        {'number': 7, 'repository_url': 'https://api.github.com/repos/o/r'},
      ],
    };
  }
  if (path == '/repos/o/r/issues/7') {
    return {
      'title': '[BUG] login flaky',
      'body': 'Fails intermittently',
      'state': 'open',
      'labels': [
        {'name': 'bug'},
      ],
    };
  }
  if (path == '/repos/o/r/issues/7/comments') {
    return {
      'comments': [
        {
          'user': {'login': 'dev1'},
          'created_at': '2026-09-08T10:00:00Z',
          'body': 'Reproduced on main',
        },
      ],
    };
  }
  if (path == '/repos/o/r/issues/42') {
    return {
      'number': 42,
      'title': 'Fix flaky login',
      'body': 'Body',
      'state': 'open'
    };
  }
  if (path == '/repos/o/r/issues/42/comments') return {'comments': []};
  fail('unexpected path: $path');
}

void fetchTests() {
  group('GithubIssueSource.fetch', () {
    test('search, hydrate, Teammate ticket shape', () async {
      final calls = <String>[];
      final source = GithubIssueSource(
        getJson: (path) => fakeGithubApi(calls, path),
        env: {'GITHUB_REPOSITORY': 'o/r'},
      );
      final tickets = await source
          .fetch(r'repo:${GITHUB_REPOSITORY} is:issue is:open label:bug');

      expect(
        calls,
        containsAll(['/repos/o/r/issues/7', '/repos/o/r/issues/7/comments']),
      );
      expect(tickets, hasLength(1));
      final t = tickets.single;
      expect(t['key'], 'GH-7');
      final fields = t['fields'] as Map;
      expect(fields['summary'], '[BUG] login flaky');
      expect(fields['description'], 'Fails intermittently');
      expect((fields['status'] as Map)['name'], 'open');
      final comments =
          ((fields['comment'] as Map)['comments'] as List).cast<Map>();
      expect(comments, hasLength(1));
      expect(((comments.single['author'] as Map)['displayName']), 'dev1');
      expect(comments.single['body'], 'Reproduced on main');
      expect(jsonEncode(t), contains('bug'));
    });

    test('query without repo qualifier and no GITHUB_REPOSITORY fails',
        () async {
      final source = GithubIssueSource(
        getJson: (_) async => {'items': []},
        env: const {},
      );
      expect(
        () => source.fetch('is:issue is:open'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

void singleIssueTests() {
  group('single-issue inputJql', () {
    test('repo:o/r#42 fetches the issue directly, no search call', () async {
      final calls = <String>[];
      final source = GithubIssueSource(
        getJson: (path) => fakeGithubApi(calls, path),
        env: const {},
      );
      final tickets = await source.fetch('repo:o/r#42');

      expect(calls, ['/repos/o/r/issues/42', '/repos/o/r/issues/42/comments']);
      expect(tickets.single['key'], 'GH-42');
      expect((tickets.single['fields'] as Map)['summary'], 'Fix flaky login');
    });

    test('#42 and GH-42 resolve the repo from GITHUB_REPOSITORY', () async {
      var fetches = 0;
      Future<Map<String, dynamic>> getJson(String path) async {
        if (path.startsWith('/repos/o/r/issues/9')) fetches++;
        return {'comments': []};
      }

      final source = GithubIssueSource(
        getJson: getJson,
        env: {'GITHUB_REPOSITORY': 'o/r'},
      );
      expect((await source.fetch('#9')).single['key'], 'GH-9');
      expect((await source.fetch('GH-9')).single['key'], 'GH-9');
      expect(fetches, 4);
    });

    test('#42 without GITHUB_REPOSITORY fails', () async {
      final source = GithubIssueSource(
        getJson: (_) async => {'comments': []},
        env: const {},
      );
      expect(() => source.fetch('#42'), throwsA(isA<StateError>()));
    });
  });
}
