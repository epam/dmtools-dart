/// L3 live integration test — TestRail smoke path (skeleton).
///
/// Follows the same shape as every live integration test (GOAL.md → Integration
/// testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox project via [gateVar] (`DMTOOLS_IT_TESTRAIL_PROJECT`),
///   which selects *where* to test, never *how* to authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path (auth → get cases → get case), read-only.
///
/// The TestRail client scopes `get_cases` to the configured `TESTRAIL_PROJECT`
/// and takes the suite id as a parameter, so the suite under test is selected by
/// [suiteVar] (`DMTOOLS_IT_TESTRAIL_SUITE`). When that is unset the
/// case-reading tests skip with a reason rather than fail.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox TestRail project the tests target (its id). Absent → skip.
const String gateVar = 'DMTOOLS_IT_TESTRAIL_PROJECT';

/// Id of the suite inside the sandbox project whose cases the tests read.
const String suiteVar = 'DMTOOLS_IT_TESTRAIL_SUITE';

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

  _testrailSmokeGroup(gate);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _testrailSmokeGroup(String gate) {
  group(
    'TestRail live smoke path',
    () {
      late final TestRailClient client;
      setUpAll(() {
        client = TestRailClient(TestRailHttpClient(PropertyReader()));
      });
      _testrailReadTests(() => client);
    },
    skip: gate.isEmpty
        ? 'Set $gateVar to a sandbox TestRail project to run.'
        : null,
  );
}

/// Auth and read smoke tests.
///
/// The get-case test lists cases first to learn an id, then fetches it — the
/// same list-then-read shape the Jira skeleton uses, since a case cannot be
/// fetched without first discovering its id.
void _testrailReadTests(TestRailClient Function() client) {
  final suiteId = int.tryParse(Platform.environment[suiteVar] ?? '');
  final suiteSkip = suiteId == null
      ? 'Set $suiteVar to a sandbox TestRail suite id to run.'
      : null;

  test('auth: testConnection resolves the current user', () async {
    final result = await client().testConnection();

    expect(result['success'], isTrue, reason: 'authentication failed');
    expect(result['user'], isNotNull);
  });

  test('get cases: lists cases in the sandbox suite', () async {
    final cases = await client().getCases(suiteId!);

    expect(cases, isNotEmpty, reason: 'empty suite $suiteId');
  }, skip: suiteSkip);

  test('get case: fetches a sandbox case', () async {
    final cases = await client().getCases(suiteId!);
    expect(cases, isNotEmpty, reason: 'empty suite $suiteId');

    final id = cases.first['id'] as int;
    final testCase = await client().getCase(id);

    expect(testCase, isNotNull);
    expect(testCase!['id'], id);
  }, skip: suiteSkip);
}
