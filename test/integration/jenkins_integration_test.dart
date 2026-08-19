/// L3 live integration test — Jenkins smoke path (skeleton).
///
/// Follows the shape every live integration test shares (GOAL.md → Integration
/// testing strategy; see test/integration/README.md and
/// `jira_integration_test.dart`):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - gated on [gateVar] (`JENKINS_BASE_PATH`), resolved through the standard
///   Phase 1 [PropertyReader] chain (real env → `dmtools.env` →
///   `dmtools-local.env`) — the same path production uses;
/// - skipped locally when the gate is absent; `DMTOOLS_IT_REQUIRE_CREDS=true`
///   turns that skip into a failure in the CI integration job;
/// - smoke path: auth → get jobs (read-only).
///
/// Auth additionally needs `JENKINS_USER` + `JENKINS_API_TOKEN`; when the gate
/// is open but those are missing the client construction fails loud, surfacing
/// the incomplete config rather than silently skipping.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Gate: a resolved `JENKINS_BASE_PATH` selects *whether* to run. Absent →
/// skip.
const String gateVar = 'JENKINS_BASE_PATH';

/// When `true`, a missing gate fails the suite instead of skipping it.
const String requireCredsVar = 'DMTOOLS_IT_REQUIRE_CREDS';

void main() {
  final reader = PropertyReader();
  final gate = reader.getValue(gateVar) ?? '';
  final requireCreds =
      (Platform.environment[requireCredsVar] ?? '').toLowerCase() == 'true';

  if (requireCreds && gate.isEmpty) {
    throw StateError(
      '$requireCredsVar=true but $gateVar is unset: the CI integration job '
      'must fail loud rather than silently skip a missing Jenkins target.',
    );
  }

  _jenkinsSmokeGroup(gate);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _jenkinsSmokeGroup(String gate) {
  group(
    'Jenkins live smoke path',
    () {
      late final JenkinsClient client;
      setUpAll(() {
        client = JenkinsClient(JenkinsHttpClient(PropertyReader()));
      });

      test('auth: testConnection resolves the controller', () async {
        final result = await client.testConnection();

        expect(result['success'], isTrue, reason: 'authentication failed');
      });

      test('read: getJobs lists jobs on the controller', () async {
        final jobs = await client.getJobs();

        expect(jobs, isA<List<Map<String, dynamic>>>());
        expect(jobs.every((j) => j.containsKey('name')), isTrue);
      });
    },
    skip: gate.isEmpty ? 'Set $gateVar to a Jenkins URL to run.' : null,
  );
}
