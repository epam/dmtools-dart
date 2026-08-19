/// L3 live integration test — Azure DevOps smoke path (skeleton).
///
/// Follows the same shape as every live integration test (GOAL.md → Integration
/// testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox project via [gateVar] (`DMTOOLS_IT_ADO_PROJECT`),
///   which selects *where* to test, never *how* to authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path (auth → list work items via WIQL → get work item), read-only.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox Azure DevOps project the tests target (e.g. `dmtools-sandbox`).
/// Absent → skip.
const String gateVar = 'DMTOOLS_IT_ADO_PROJECT';

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

  _adoSmokeGroup(gate);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _adoSmokeGroup(String gate) {
  group(
    'Azure DevOps live smoke path',
    () {
      late final AdoClient client;
      setUpAll(() {
        client = AdoClient(AdoHttpClient(PropertyReader()));
      });
      _adoReadTests(() => client, gate);
    },
    skip: gate.isEmpty ? 'Set $gateVar to a sandbox ADO project to run.' : null,
  );
}

/// Auth and read smoke tests.
///
/// The get-work-item test lists work items first (WIQL) to learn an id, then
/// fetches it — the same list-then-read shape the Jira skeleton uses, since a
/// work item cannot be fetched without first discovering its id.
void _adoReadTests(AdoClient Function() client, String gate) {
  test('auth: testConnection resolves the authenticated user', () async {
    final result = await client().testConnection();

    expect(result['success'], isTrue,
        reason:
            'authentication failed: ${result['error'] ?? result['message']}');
    // The Profile API carries user/email; a PAT without profile scope
    // falls back to the projects proof, where only success is known.
    if (result['user'] != null) {
      expect(result['user'], isA<String>());
    }
  });

  test('list work items: WIQL finds work items in the sandbox project',
      () async {
    final items = await client().listWorkItems(_wiqlFor(gate));

    expect(
      items,
      isNotEmpty,
      reason: 'sandbox project "$gate" has no work items to read',
    );
  });

  test('get work item: fetches a sandbox work item', () async {
    final items = await client().listWorkItems(_wiqlFor(gate));
    if (items.isEmpty) {
      fail('sandbox project "$gate" has no work items to read');
    }

    final id = int.parse(items.first['id'].toString());
    final workItem = await client().getWorkItem(id);

    expect(workItem, isNotNull);
    expect(workItem['id'], id);
  });
}

/// Builds a flat WIQL query that returns the ids of work items in [project].
String _wiqlFor(String project) =>
    "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '$project'";
