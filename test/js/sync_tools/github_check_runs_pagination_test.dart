import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/github_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';
import 'github_fixture_helper.dart';

/// Regression: `github_get_commit_check_runs` must walk every page.
///
/// Live failure (fa #1457, dmtools-agents#865): the tool did a single
/// bare GET — GitHub's default 30-run page. Heads accumulate
/// check-runs across CI re-runs and SM stamps (the failing head carried
/// 355), so the in_progress placeholder orphans past page 1 stayed
/// invisible to every SM detector and pinned mergeStateStatus=BLOCKED.
///
/// Fixture: `/repos/o/r/commits/pagedsha/check-runs` serves a full
/// 100-run page 1 + a 3-run page 2 carrying the orphan trio
/// (see `github_fixture_server.py`).
late GithubFixtureServer fx;
late GitHubSyncTools tools;

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

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

  if (!hasPython3()) return;

  test('github_get_commit_check_runs walks every page (fa#1457 blind spot)',
      () {
    final body = jsonDecode(
      tools.handlers['github_get_commit_check_runs']!({
        'workspace': 'o',
        'repository': 'r',
        'commitSha': 'pagedsha',
      }),
    ) as Map<String, dynamic>;
    final runs = body['check_runs'] as List;
    expect(runs, hasLength(103));
    expect(
      runs.map((r) => (r as Map)['name']),
      containsAll(const [
        'Quality gate',
        'JS engine integration (quickjs-ng)',
        'Binaries smoke gate',
      ]),
    );
    expect(body['total_count'], 103);
    expect(
      fx.requests.where((r) => r.contains('commits/pagedsha/check-runs')),
      hasLength(2),
    );
  });
}
