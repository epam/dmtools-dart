/// L3 live integration test — GitHub smoke path.
///
/// Documents the shape every live integration test follows (GOAL.md →
/// Integration testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox repo via [gateVar] (`DMTOOLS_IT_GITHUB_REPO`) in
///   `owner/repo` form, which selects *where* to test, never *how* to
///   authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. `SOURCE_GITHUB_TOKEN` carries the auth token;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path: auth → list PRs → get PR → create comment → get issue →
///   cleanup comment.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox repo the tests target (`owner/repo`). Absent → skip.
const String gateVar = 'DMTOOLS_IT_GITHUB_REPO';

/// When `true`, a missing gate fails the suite instead of skipping it.
const String requireCredsVar = 'DMTOOLS_IT_REQUIRE_CREDS';

void main() {
  final gate = Platform.environment[gateVar] ?? '';
  final requireCreds =
      (Platform.environment[requireCredsVar] ?? '').toLowerCase() == 'true';

  if (requireCreds && gate.isEmpty) {
    throw StateError(
      '$requireCredsVar=true but $gateVar is unset: the CI integration job '
      'must fail loud rather than silently skip a missing sandbox target.',
    );
  }

  final runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  _githubSmokeGroup(gate, runId);
}

/// Registers the smoke-path group, skipped when [gate] is empty or malformed.
void _githubSmokeGroup(String gate, String runId) {
  final parts = gate.split('/');
  final valid = parts.length == 2 && parts.every((p) => p.isNotEmpty);
  // owner/repo are resolved now, not in setUpAll, so they are in scope when the
  // group body registers the test functions (which runs before setUpAll).
  final owner = valid ? parts[0] : '';
  final repo = valid ? parts[1] : '';

  group(
    'GitHub live smoke path',
    () {
      late final GithubClient client;
      late final GithubHttpClient http;
      setUpAll(() {
        http = GithubHttpClient(PropertyReader());
        client = GithubClient(http);
      });
      _githubReadTests(() => client, owner, repo);
      _githubWriteTest(() => client, () => http, owner, repo, runId);
    },
    skip: gate.isEmpty
        ? 'Set $gateVar to an owner/repo sandbox repo to run.'
        : (valid ? null : '$gateVar must be in "owner/repo" form.'),
  );
}

/// Auth, list, and read smoke tests (`github_test`, `github_list_prs`,
/// `github_get_pr`).
void _githubReadTests(
  GithubClient Function() client,
  String owner,
  String repo,
) {
  test('auth: testConnection resolves the current user', () async {
    final result = await client().testConnection();

    expect(result['success'], isTrue, reason: 'authentication failed');
    expect(result['user'], isNotEmpty);
  });

  test('list: listPrs returns a list for the sandbox repo', () async {
    final prs = await client().listPrs(owner, repo);

    expect(prs, isA<List<Map<String, dynamic>>>());
  });

  test('read: getPr fetches a sandbox pull request', () async {
    final number = await _resolvePrNumber(client, owner, repo);
    if (number < 0) {
      fail('sandbox repo "$owner/$repo" has no pull requests to read');
    }

    final pr = await client().getPr(owner, repo, number);

    expect(pr['number'], number);
  });
}

/// Write smoke test — self-cleaning comment round-trip plus issue read
/// (`github_create_comment`, `github_get_issue`).
void _githubWriteTest(
  GithubClient Function() client,
  GithubHttpClient Function() http,
  String owner,
  String repo,
  String runId,
) {
  test('write: comment round-trip on a PR is self-cleaning', () async {
    final number = await _resolvePrNumber(client, owner, repo);
    if (number < 0) {
      fail('sandbox repo "$owner/$repo" has no PRs to comment on');
    }

    final comment = await client().createComment(
      owner,
      repo,
      number,
      'it-$runId-smoke comment',
    );
    final commentId = (comment['id'] as num).toInt();
    // Always delete the comment we just created, even if the assertions below
    // throw — fixtures never outlive their test.
    addTearDown(
      () => http().delete('repos/$owner/$repo/issues/comments/$commentId'),
    );

    final issue = await client().getIssue(owner, repo, number);

    expect(issue['number'], number);
    expect(commentId, greaterThan(0));
  });
}

/// Resolves a pull-request number to exercise, preferring open PRs but falling
/// back to any state. Returns `-1` when the repo has no pull requests at all.
Future<int> _resolvePrNumber(
  GithubClient Function() client,
  String owner,
  String repo,
) async {
  final open = await client().listPrs(owner, repo);
  if (open.isNotEmpty) return open.first['number'] as int;

  final all = await client().listPrs(owner, repo, 'all');
  return all.isEmpty ? -1 : all.first['number'] as int;
}
