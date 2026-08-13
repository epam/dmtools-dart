/// L3 live integration test — Jira smoke path (skeleton).
///
/// Documents the shape every live integration test follows (GOAL.md →
/// Integration testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox project via [gateVar] (`DMTOOLS_IT_JIRA_PROJECT`),
///   which selects *where* to test, never *how* to authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path first (auth → search → read → write → cleanup), read-only
///   where a write is not the point of the test.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox Jira project the tests target (e.g. `SANDBOX`). Absent → skip.
const String gateVar = 'DMTOOLS_IT_JIRA_PROJECT';

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
  _jiraSmokeGroup(gate, runId);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _jiraSmokeGroup(String gate, String runId) {
  group(
    'Jira live smoke path',
    () {
      late final JiraClient client;
      setUpAll(() {
        client = JiraClient(JiraHttpClient(PropertyReader()));
      });
      _jiraReadTests(() => client, gate);
      _jiraWriteTest(() => client, gate, runId);
    },
    skip:
        gate.isEmpty ? 'Set $gateVar to a sandbox Jira project to run.' : null,
  );
}

/// Auth, search, and read smoke tests.
void _jiraReadTests(JiraClient Function() client, String gate) {
  test('auth: testConnection resolves the current user', () async {
    final user = await client().testConnection();

    expect(user['error'], isNull, reason: 'authentication failed');
    expect(user, isNotEmpty);
  });

  test('search: searchByJql finds tickets in the sandbox project', () async {
    final issues = await client().searchByJql('project = $gate');

    expect(
      issues,
      isNotEmpty,
      reason: 'sandbox project "$gate" has no tickets to read',
    );
  });

  test('read: getTicket fetches a sandbox ticket', () async {
    final issues = await client().searchByJql('project = $gate');
    if (issues.isEmpty) {
      fail('sandbox project "$gate" has no tickets to read');
    }

    final key = issues.first['key'] as String;
    final ticket = await client().getTicket(key);

    expect(ticket, isNotNull);
    expect(ticket!['key'], key);
  });
}

/// Write smoke test — self-cleaning label round-trip.
void _jiraWriteTest(
  JiraClient Function() client,
  String gate,
  String runId,
) {
  test('write: label round-trip is self-cleaning', () async {
    final issues = await client().searchByJql('project = $gate');
    if (issues.isEmpty) {
      fail('sandbox project "$gate" has no tickets to write to');
    }

    final key = issues.first['key'] as String;
    final label = 'it-$runId-smoke';
    await client().addLabel(key, label);
    // Always remove the label we just added, even if the assertion below
    // throws — fixtures never outlive their test.
    addTearDown(() => client().removeLabel(key, label));

    final fields =
        (await client().getTicket(key))?['fields'] as Map<String, dynamic>?;
    final labels = fields?['labels'] as List? ?? const [];

    expect(labels, contains(label));
  });
}
