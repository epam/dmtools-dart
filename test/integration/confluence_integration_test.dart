/// L3 live integration test — Confluence smoke path (skeleton).
///
/// Documents the shape every live integration test follows (GOAL.md →
/// Integration testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox space via [gateVar] (`DMTOOLS_IT_CONFLUENCE_SPACE`),
///   which selects *where* to test, never *how* to authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path first (auth → search CQL → get page → create page → cleanup),
///   read-only where a write is not the point of the test.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox Confluence space the tests target (e.g. `SANDBOX`). Absent → skip.
const String gateVar = 'DMTOOLS_IT_CONFLUENCE_SPACE';

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
  _confluenceSmokeGroup(gate, runId);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _confluenceSmokeGroup(String gate, String runId) {
  group(
    'Confluence live smoke path',
    () {
      late final ConfluenceClient client;
      setUpAll(() {
        client = ConfluenceClient(ConfluenceHttpClient(PropertyReader()));
      });
      _confluenceAuthTest(() => client);
      _confluenceReadTests(() => client, gate);
      _confluenceWriteTest(() => client, gate, runId);
    },
    skip: gate.isEmpty
        ? 'Set $gateVar to a sandbox Confluence space to run.'
        : null,
  );
}

/// Auth smoke test — [ConfluenceClient.testConnection] via GET `user/current`.
void _confluenceAuthTest(ConfluenceClient Function() client) {
  test('auth: testConnection resolves the current user', () async {
    final result = await client().testConnection();

    expect(result['success'], isTrue, reason: 'authentication failed');
    expect(result['user'], isNotEmpty);
  });
}

/// Search and read smoke tests, both scoped to [gate] via CQL `space =`.
void _confluenceReadTests(
  ConfluenceClient Function() client,
  String gate,
) {
  test('search: CQL search finds content in the sandbox space', () async {
    final results = await client().search('space = "$gate"');

    expect(
      results,
      isNotEmpty,
      reason: 'sandbox space "$gate" has no content to search',
    );
  });

  test('read: getPage fetches a sandbox page', () async {
    final results = await client().search('space = "$gate"');
    final title = _firstResultTitle(results);

    final page = await client().getPage(gate, title);

    expect(page, isNotNull);
    expect(page!['title'], title);
  });
}

/// Write smoke test — page create/delete round-trip, self-cleaning via
/// [ConfluenceClient.deletePage] in [addTearDown]. Titles carry [runId] so a
/// rerun cannot collide on Confluence's unique-title constraint.
void _confluenceWriteTest(
  ConfluenceClient Function() client,
  String gate,
  String runId,
) {
  test('write: page create/delete round-trip is self-cleaning', () async {
    final title = 'it-$runId-smoke';
    final created = await client().createPage(
      gate,
      title,
      '<p>dmtools L3 smoke test page</p>',
    );
    final id = created['id'] as String;
    addTearDown(() => client().deletePage(id));

    expect(created['title'], title);
  });
}

/// Picks the title of the first search result that has one.
String _firstResultTitle(List<Map<String, dynamic>> results) {
  for (final r in results) {
    final title = r['title'];
    if (title is String && title.isNotEmpty) return title;
  }
  fail('no titled content in sandbox space to read');
}
