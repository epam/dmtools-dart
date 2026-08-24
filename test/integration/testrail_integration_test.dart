/// L3 live integration test — TestRail smoke path.
///
/// Follows the same shape as every live integration test (GOAL.md → Integration
/// testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox project via [gateVar] (`DMTOOLS_IT_TESTRAIL_PROJECT`,
///   the project **id**), which selects *where* to test, never *how* to
///   authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path (auth → get cases → get case → get sections), read-only where a
///   write is not the point, plus self-cleaning create/delete round-trips for
///   the section-aware case-creation tools.
///
/// The TestRail client scopes `get_cases` to the configured `TESTRAIL_PROJECT`
/// and takes the suite id as a parameter, so the suite under test is selected by
/// [suiteVar] (`DMTOOLS_IT_TESTRAIL_SUITE`). When that is unset the
/// suite-dependent tests (case reads, sections, writes) skip with a reason
/// rather than fail — the same way Confluence gates its round-trip on a
/// writable space.
///
/// The section and case-creation tools address projects by *name* (Java
/// parity), while the gate variable carries the project *id* — the tests
/// resolve id → name through the live `get_projects` list.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox TestRail project the tests target (its id). Absent → skip.
const String gateVar = 'DMTOOLS_IT_TESTRAIL_PROJECT';

/// Id of the suite inside the sandbox project under test.
const String suiteVar = 'DMTOOLS_IT_TESTRAIL_SUITE';

/// When `true`, a missing gate fails the suite instead of skipping it.
const String requireCredsVar = 'DMTOOLS_IT_REQUIRE_CREDS';

void main() {
  final gate = Platform.environment[gateVar] ?? '';
  final requireCreds =
      (Platform.environment[requireCredsVar] ?? '').toLowerCase() == 'true';
  final projectId = int.tryParse(gate);

  if (requireCreds && gate.isEmpty) {
    throw StateError(
      '$requireCredsVar=true but $gateVar is unset: the CI integration job '
      'must fail loud rather than silently skip a missing sandbox target.',
    );
  }
  if (gate.isNotEmpty && projectId == null) {
    throw StateError(
      '$gateVar must be a numeric TestRail project id, got "$gate".',
    );
  }

  final runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  _testrailSmokeGroup(gate, projectId, runId);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
///
/// [projectId] is `null` exactly when [gate] is empty (guarded in `main`),
/// so the tests can null-assert it — their bodies never run while skipped.
void _testrailSmokeGroup(String gate, int? projectId, String runId) {
  group(
    'TestRail live smoke path',
    () {
      late final TestRailClient client;
      setUpAll(() {
        // The gate var picks the sandbox project; mirror it into the
        // client config so TESTRAIL_PROJECT does not have to be set
        // separately for the same purpose (review note).
        final existing = PropertyReader.getOverrides();
        PropertyReader.setOverrides({...existing, 'TESTRAIL_PROJECT': gate});
        client = TestRailClient(TestRailHttpClient(PropertyReader()));
      });
      tearDownAll(PropertyReader.clearOverrides);
      _testrailReadTests(() => client, () => projectId!, runId);
      _testrailSectionTest(() => client, () => projectId!);
      _testrailCreateTests(() => client, () => projectId!, runId);
      _testrailCreateStepsTest(() => client, () => projectId!, runId);
    },
    skip: gate.isEmpty
        ? 'Set $gateVar to a sandbox TestRail project to run.'
        : null,
  );
}

/// Auth and read smoke tests.
///
/// The sandbox is self-cleaning (every created case is deleted in teardown),
/// so the case-reading tests **seed their own case first** — the suite cannot
/// be assumed to hold any pre-existing data.
void _testrailReadTests(
  TestRailClient Function() client,
  int Function() projectId,
  String runId,
) {
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
    final seedId = await _seedCase(client, projectId, suiteId!, runId);
    final cases = await client().getCases(suiteId);

    expect(
      cases.map((c) => (c['id'] as num).toInt()),
      contains(seedId),
      reason: 'seeded case $seedId missing from suite $suiteId',
    );
  }, skip: suiteSkip);

  test('get case: fetches a sandbox case', () async {
    final seedId = await _seedCase(client, projectId, suiteId!, runId);
    final testCase = await client().getCase(seedId);

    expect(testCase, isNotNull);
    expect(testCase!['id'], seedId);
  }, skip: suiteSkip);
}

/// Creates a disposable case in the suite's first section and returns its
/// id; the deletion is registered with [addTearDown] so the sandbox stays
/// clean even when the test body fails.
Future<int> _seedCase(
  TestRailClient Function() client,
  int Function() projectId,
  int suiteId,
  String runId,
) async {
  final sectionId = await _firstSectionId(client(), projectId(), suiteId);
  final seeded = await client().createCase(
    await _resolveProjectName(client(), projectId()),
    'it-$runId seed ${DateTime.now().millisecondsSinceEpoch % 100000}',
    sectionId: '$sectionId',
  );
  final seedId = (seeded['id'] as num).toInt();
  addTearDown(() => client().deleteCase(seedId));
  return seedId;
}

/// Read smoke test for `get_sections` — suite-keyed, read-only.
void _testrailSectionTest(
  TestRailClient Function() client,
  int Function() projectId,
) {
  final suiteId = int.tryParse(Platform.environment[suiteVar] ?? '');
  final suiteSkip = suiteId == null
      ? 'Set $suiteVar to a sandbox TestRail suite id to run.'
      : null;

  test('get sections: lists sections in the sandbox suite', () async {
    final name = await _resolveProjectName(client(), projectId());
    final sections = await client().getSectionsByProjectName(
      name,
      suiteId: '$suiteId',
    );

    expect(
      sections,
      isNotEmpty,
      reason: 'suite $suiteId in project ${projectId()} exposes no sections',
    );
  }, skip: suiteSkip);
}

/// Create/delete round-trips for `testrail_create_case` and
/// `testrail_create_case_detailed`, both targeting an explicit `section_id`
/// (the Java-parity path added with the section-aware creation tools).
/// Self-cleaning via [TestRailClient.deleteCase] in [addTearDown].
void _testrailCreateTests(
  TestRailClient Function() client,
  int Function() projectId,
  String runId,
) {
  final suiteId = int.tryParse(Platform.environment[suiteVar] ?? '');
  final suiteSkip = suiteId == null
      ? 'Set $suiteVar to a sandbox TestRail suite id to run.'
      : null;

  test('create case: basic round-trip targets an explicit section', () async {
    final sectionId = await _firstSectionId(client(), projectId(), suiteId!);
    final created = await client().createCase(
      await _resolveProjectName(client(), projectId()),
      'it-$runId basic',
      description: 'dmtools L3 smoke: basic create',
      sectionId: '$sectionId',
    );
    final id = (created['id'] as num).toInt();
    addTearDown(() => client().deleteCase(id));

    expect(id, greaterThan(0));
    expect(created['title'], 'it-$runId basic');
  }, skip: suiteSkip);

  test('create case detailed: markdown table becomes TestRail format',
      () async {
    final sectionId = await _firstSectionId(client(), projectId(), suiteId!);
    final created = await client().createCaseDetailed(
      await _resolveProjectName(client(), projectId()),
      'it-$runId detailed',
      steps: '| Col 1 | Col 2 |\n|---|---|\n| val1 | val2 |',
      sectionId: '$sectionId',
    );
    final id = (created['id'] as num).toInt();
    addTearDown(() => client().deleteCase(id));

    expect(created['custom_steps'] as String?, contains('|||:Col 1'));
  }, skip: suiteSkip);
}

/// Create/delete round-trip for `testrail_create_case_steps` — the Steps
/// template (template_id=2) with a Markdown table converted to HTML.
void _testrailCreateStepsTest(
  TestRailClient Function() client,
  int Function() projectId,
  String runId,
) {
  final suiteId = int.tryParse(Platform.environment[suiteVar] ?? '');
  final suiteSkip = suiteId == null
      ? 'Set $suiteVar to a sandbox TestRail suite id to run.'
      : null;

  test('create case steps: steps template converts tables to html', () async {
    final sectionId = await _firstSectionId(client(), projectId(), suiteId!);
    final created = await client().createCaseSteps(
      await _resolveProjectName(client(), projectId()),
      'it-$runId steps',
      stepsJson: '[{"content":"| Col 1 |\\n|---|\\n| val1 |",'
          '"expected":"table rendered"}]',
      sectionId: '$sectionId',
    );
    final id = (created['id'] as num).toInt();
    addTearDown(() => client().deleteCase(id));

    expect(created['template_id'], 2);
    final steps = created['custom_steps_separated'] as List;
    expect(steps, isNotEmpty);
    expect((steps.first as Map)['content'] as String?, contains('<table>'));
  }, skip: suiteSkip);
}

/// Resolves the sandbox project's name from its id via the live projects
/// list — the section/case-creation tools address projects by name (Java
/// parity), while the gate variable carries the id.
Future<String> _resolveProjectName(
  TestRailClient client,
  int projectId,
) async {
  final envelope = await client.getProjects();
  final projects =
      (envelope['projects'] as List).whereType<Map<String, dynamic>>().toList();
  for (final project in projects) {
    final id = (project['id'] as num?)?.toInt();
    if (id == projectId && project['name'] is String) {
      return project['name'] as String;
    }
  }
  fail('project id $projectId not found in the TestRail projects list');
}

/// Returns the id of the first section of the sandbox suite — the write
/// round-trips create their cases there.
Future<int> _firstSectionId(
  TestRailClient client,
  int projectId,
  int suiteId,
) async {
  final sections = await client.getSectionsByProjectName(
    await _resolveProjectName(client, projectId),
    suiteId: '$suiteId',
  );
  expect(sections, isNotEmpty, reason: 'suite $suiteId has no sections');
  return (sections.first['id'] as num).toInt();
}
