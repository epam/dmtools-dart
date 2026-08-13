import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Coverage + behavior tests for [GithubClient] and [GithubHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getPrTests();
  listPrsTests();
  createCommentTests();
  getIssueTests();
  createPrTests();
}

/// The base path injected by the fixture's config.
const _basePath = 'https://github.example.com/api/v3';

/// [GithubHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('GithubHttpClient', () {
    test('builds GitHub API URLs from the configured base path', () {
      final f = mockGithubHttp((o) => '{}');
      expect(
        f.http.buildUrl('user'),
        '$_basePath/user',
      );
    });

    test('assembles Authorization, Accept, and content headers', () {
      final f = mockGithubHttp((o) => '{}');
      expect(f.http.headers['Authorization'], 'Bearer gh-token-123');
      expect(f.http.headers['Accept'], 'application/vnd.github+json');
      expect(f.http.headers['X-GitHub-Api-Version'], '2022-11-28');
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/post return the response bodies', () async {
      final f = mockGithubHttp((o) => routeByPath({
            '/user': 'GET-USER',
            '/pulls': 'POST-PR',
          }, o));
      expect(await f.http.get('user'), 'GET-USER');
      expect(await f.http.post('pulls'), 'POST-PR');
      f.http.close();
    });

    test('throws StateError when SOURCE_GITHUB_TOKEN is missing', () {
      PropertyReader.clearOverrides();
      expect(() => GithubHttpClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when SOURCE_GITHUB_TOKEN is empty', () {
      PropertyReader.setOverrides({'SOURCE_GITHUB_TOKEN': ''});
      expect(() => GithubHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `github_test` — connectivity check via GET `/user`.
void testConnectionTests() {
  group('GithubClient.testConnection', () {
    test('returns success with the user profile', () async {
      final f = mockGithub((o) => routeByPath({'/user': _userBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'GitHub connection successful');
      expect(result['user'], 'dev-user');
      expect(f.adapter.calls.single.path, endsWith('/user'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockGithub((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `github_get_pr` — GET `/repos/{owner}/{repo}/pulls/{number}`.
void getPrTests() {
  group('GithubClient.getPr', () {
    test('returns the decoded pull request map', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      final pr = await f.client.getPr('epm', 'dm.ai', 42);
      expect(pr['number'], 42);
      expect(pr['title'], 'Fix bug');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
    });
  });
}

/// `github_list_prs` — GET `/repos/{owner}/{repo}/pulls`.
void listPrsTests() {
  group('GithubClient.listPrs', () {
    test('returns the decoded list of pull requests', () async {
      final f = mockGithub((o) => routeByPath({'/pulls': _prListBody}, o));
      final prs = await f.client.listPrs('epm', 'dm.ai');
      expect(prs.map((p) => p['number']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls'));
    });

    test('defaults the state query to open', () async {
      final f = mockGithub((o) => routeByPath({'/pulls': _prListBody}, o));
      await f.client.listPrs('epm', 'dm.ai');
      expect(f.adapter.calls.single.queryParameters['state'], 'open');
    });

    test('forwards an explicit state filter', () async {
      final f = mockGithub((o) => routeByPath({'/pulls': _prListBody}, o));
      await f.client.listPrs('epm', 'dm.ai', 'closed');
      expect(f.adapter.calls.single.queryParameters['state'], 'closed');
    });
  });
}

/// `github_create_comment` — POST `/repos/{owner}/{repo}/issues/{number}/comments`.
void createCommentTests() {
  group('GithubClient.createComment', () {
    test('POSTs the comment body to the issues endpoint', () async {
      final f = mockGithub((o) => routeByPath(
            {'/issues/42/comments': _commentBody},
            o,
          ));
      final result = await f.client.createComment('epm', 'dm.ai', 42, 'hi');
      expect(result['id'], 9001);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/42/comments'));
      expect(jsonDecode(call.data as String), {'body': 'hi'});
    });
  });
}

/// `github_get_issue` — GET `/repos/{owner}/{repo}/issues/{number}`.
void getIssueTests() {
  group('GithubClient.getIssue', () {
    test('returns the decoded issue map', () async {
      final f = mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
      final issue = await f.client.getIssue('epm', 'dm.ai', 7);
      expect(issue['number'], 7);
      expect(issue['title'], 'Reported bug');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7'));
    });
  });
}

/// `github_create_pr` — POST `/repos/{owner}/{repo}/pulls`.
void createPrTests() {
  group('GithubClient.createPr', () {
    test('POSTs title, head, and base', () async {
      final f = mockGithub((o) => routeByPath({'/pulls': _prBody}, o));
      final result =
          await f.client.createPr('epm', 'dm.ai', 'Fix bug', 'feature', 'main');
      expect(result['title'], 'Fix bug');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls'));
      expect(jsonDecode(call.data as String), {
        'title': 'Fix bug',
        'head': 'feature',
        'base': 'main',
      });
    });
  });
}

/// Canned `/user` response body.
const _userBody = '{"login":"dev-user"}';

/// Canned single pull-request response body.
const _prBody = '{"number":42,"title":"Fix bug"}';

/// Canned pull-request list response body.
const _prListBody = '[{"number":1},{"number":2}]';

/// Canned issue response body.
const _issueBody = '{"number":7,"title":"Reported bug"}';

/// Canned comment response body.
const _commentBody = '{"id":9001}';
