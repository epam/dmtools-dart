import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Pull-request updates — title/body edits, reviewer requests, and review
/// dismissal — [GithubClient] methods plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  updatePullRequestTests();
  requestReviewersTests();
  dismissReviewTests();
  executorPrUpdateTests();
  executorReviewTests();
}

/// `github_update_pr` — PATCH `/repos/{owner}/{repo}/pulls/{number}`.
void updatePullRequestTests() {
  group('GithubClient.updatePullRequest', () {
    test('PATCHes title and body when both are given', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.updatePullRequest('epm', 'dm.ai', 42, 'New', 'Desc');
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
      expect(jsonDecode(call.data as String), {
        'title': 'New',
        'body': 'Desc',
      });
    });

    test('sends only the title when the body is omitted', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.updatePullRequest('epm', 'dm.ai', 42, 'New');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'title': 'New',
      });
    });

    test('sends only the body when the title is omitted', () async {
      final f = mockGithub((o) => routeByPath({'/pulls/42': _prBody}, o));
      await f.client.updatePullRequest('epm', 'dm.ai', 42, null, 'Desc');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'body': 'Desc',
      });
    });
  });
}

/// `github_request_reviewers` — POST
/// `/repos/{owner}/{repo}/pulls/{number}/requested_reviewers`.
void requestReviewersTests() {
  group('GithubClient.requestReviewers', () {
    test('POSTs the reviewer set', () async {
      final f = mockGithub(
        (o) => routeByPath({'/requested_reviewers': _prBody}, o),
      );
      await f.client.requestReviewers('epm', 'dm.ai', 42, ['alice', 'bob']);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/requested_reviewers'),
      );
      expect(jsonDecode(call.data as String), {
        'reviewers': ['alice', 'bob'],
      });
    });
  });
}

/// `github_dismiss_review` — PUT
/// `/repos/{owner}/{repo}/pulls/{number}/reviews/{reviewId}/dismissals`.
void dismissReviewTests() {
  group('GithubClient.dismissReview', () {
    test('PUTs the dismissal message', () async {
      final f = mockGithub(
        (o) => routeByPath({'/dismissals': _reviewBody}, o),
      );
      await f.client.dismissReview('epm', 'dm.ai', 42, 9, 'Stale');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/reviews/9/dismissals'),
      );
      expect(jsonDecode(call.data as String), {'message': 'Stale'});
    });
  });
}

/// Executor routing for the PR-update tools.
void executorPrUpdateTests() {
  group('GithubToolExecutor.execute (PR update)', () {
    test('routes github_update_pr with title and body', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_update_pr',
        {..._prArgs(42), 'title': 'New', 'body': 'Desc'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/pulls/42'));
      expect(jsonDecode(call.data as String), {
        'title': 'New',
        'body': 'Desc',
      });
    });

    test('routes github_update_pr without optional fields', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client)
          .execute('github_update_pr', _prArgs(42));
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        isEmpty,
      );
    });
  });
}

/// Executor routing for the reviewer-request and review-dismissal tools.
void executorReviewTests() {
  group('GithubToolExecutor.execute (reviews)', () {
    test('routes github_request_reviewers with a cast list', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_request_reviewers',
        {
          ..._prArgs(42),
          'reviewers': ['alice'],
        },
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/requested_reviewers'),
      );
    });

    test('routes github_dismiss_review with a coerced review_id', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_dismiss_review',
        {..._prArgs(42), 'review_id': '9', 'message': 'Stale'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/pulls/42/reviews/9/dismissals'),
      );
      expect(jsonDecode(call.data as String), {'message': 'Stale'});
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// PR tool arguments with a [number] value.
Map<String, dynamic> _prArgs(Object number) => {..._repoArgs, 'number': number};

/// Serves the canned review body for dismissals, the pull-request body
/// otherwise.
String _router(RequestOptions o) {
  if (o.path.endsWith('/dismissals')) return _reviewBody;
  return _prBody;
}

/// Canned pull-request body.
const _prBody = '{"number":42,"title":"PR"}';

/// Canned review body.
const _reviewBody = '{"id":9,"state":"DISMISSED"}';
