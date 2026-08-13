/// L3 live integration test — Figma smoke path (skeleton).
///
/// Follows the same shape as every live integration test (GOAL.md → Integration
/// testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox file via [gateVar] (`DMTOOLS_IT_FIGMA_FILE`), which
///   selects *where* to test, never *how* to authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path (auth → get file → get components), strictly read-only: the
///   sandbox file is only ever read, never commented on or modified.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox Figma file key the tests target (e.g. `aBcDeFgHiJkL`). Absent → skip.
const String gateVar = 'DMTOOLS_IT_FIGMA_FILE';

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

  _figmaSmokeGroup(gate);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _figmaSmokeGroup(String gate) {
  group(
    'Figma live smoke path',
    () {
      late final FigmaClient client;
      setUpAll(() {
        client = FigmaClient(FigmaHttpClient(PropertyReader()));
      });
      _figmaReadTests(() => client, gate);
    },
    skip: gate.isEmpty ? 'Set $gateVar to a sandbox Figma file to run.' : null,
  );
}

/// Auth and read smoke tests.
void _figmaReadTests(FigmaClient Function() client, String gate) {
  test('auth: testConnection resolves the current user', () async {
    final result = await client().testConnection();

    expect(result['success'], isTrue, reason: 'authentication failed');
    expect(result['user'], isNotNull);
  });

  test('get file: fetches the sandbox Figma file', () async {
    final file = await client().getFile(gate);

    expect(file, isNotEmpty);
    expect(file['name'], isNotNull,
        reason: 'no file named "$gate" is readable');
  });

  test('get components: reads the sandbox file components', () async {
    final components = await client().getComponents(gate);

    expect(components, isNotEmpty);
    expect(
      components['meta'],
      isA<Map>(),
      reason: 'unexpected components payload for "$gate"',
    );
  });
}
