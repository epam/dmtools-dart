/// L3 live integration test — Bitrise smoke path (skeleton).
///
/// Follows the shape every live integration test shares (GOAL.md → Integration
/// testing strategy; see test/integration/README.md and
/// `jira_integration_test.dart`):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - gated on [gateVar] (`BITRISE_TOKEN`), resolved through the standard Phase 1
///   [PropertyReader] chain (real env → `dmtools.env` → `dmtools-local.env`) —
///   the same path production uses, so a token in `dmtools.env` is honoured;
/// - skipped locally when the gate is absent; `DMTOOLS_IT_REQUIRE_CREDS=true`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path: auth → get apps → get builds (read-only).
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Gate: a resolved `BITRISE_TOKEN` selects *whether* to authenticate. Absent
/// → skip.
const String gateVar = 'BITRISE_TOKEN';

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
      'must fail loud rather than silently skip a missing Bitrise token.',
    );
  }

  _bitriseSmokeGroup(gate);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _bitriseSmokeGroup(String gate) {
  group(
    'Bitrise live smoke path',
    () {
      late final BitriseClient client;
      setUpAll(() {
        client = BitriseClient(BitriseHttpClient(PropertyReader()));
      });

      test('auth: testConnection resolves accessible apps', () async {
        final result = await client.testConnection();

        expect(result['success'], isTrue, reason: 'authentication failed');
        expect(result['apps'], isA<int>());
      });

      test('read: getApps lists accessible apps', () async {
        final apps = await client.getApps();

        expect(apps, isA<List<Map<String, dynamic>>>());
      });

      test('read: getBuilds lists builds for the first app', () async {
        final apps = await client.getApps();
        if (apps.isEmpty) {
          fail('No Bitrise apps accessible to the token; cannot read builds.');
        }
        final slug = apps.first['slug'];
        if (slug is! String || slug.isEmpty) {
          fail('First Bitrise app has no slug; cannot read builds.');
        }

        final builds = await client.getBuilds(slug);
        expect(builds, contains('data'));
      });
    },
    skip: gate.isEmpty ? 'Set $gateVar to a Bitrise API token to run.' : null,
  );
}
