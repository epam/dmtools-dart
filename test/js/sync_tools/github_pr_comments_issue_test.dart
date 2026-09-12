import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/github_sync_tools.dart';
import 'package:test/test.dart';

import 'github_fixture_helper.dart';

// The plain-issue tolerance of `github_get_pr_comments`, split into its own
// file: the sync-tools test file sits at the 800-line loc gate limit, and
// these two tests pushed it over (crap4dart method_size flagged the grown
// test group as well). The fixture wiring mirrors the comment-tools group
// of github_sync_tools_test.dart; duplication ignores test/**.

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  late GithubFixtureServer fx;
  late GitHubSyncTools tools;

  setUp(() async {
    fx = GithubFixtureServer();
    await fx.start();
    PropertyReader.setOverrides({
      'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
      'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${fx.port}',
    });
    tools = const GitHubSyncTools();
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    fx.stop();
  });

  test('github_get_pr_comments tolerates a plain issue (404 inline page)', () {
    // trackers.js githubGetComments contract: /pulls/{n}/comments answers
    // 404 when n is a plain issue (only PRs have review comments) — the
    // runtime treats that page as empty and still returns the discussion
    // page, so the tracker layer can read issue comments.
    final result = tools.handlers['github_get_pr_comments']!({
      'workspace': 'o',
      'repository': 'r',
      'pullRequestId': '9',
    });
    final comments = jsonDecode(result) as List;
    expect(comments.map((c) => c['id']), [21]);
  });

  test('github_get_pr_comments still errors when both pages are missing', () {
    // The tolerance is inline-page-only: a 404 discussion page means the
    // caller asked for a comment listing that does not exist.
    final result = tools.handlers['github_get_pr_comments']!({
      'workspace': 'o',
      'repository': 'r',
      'pullRequestId': '8',
    });
    final decoded = jsonDecode(result) as Map<String, dynamic>;
    expect(decoded['error'], contains('HTTP 404'));
  });
}
