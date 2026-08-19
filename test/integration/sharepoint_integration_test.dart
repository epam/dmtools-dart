/// L3 live integration test — SharePoint smoke path (skeleton).
///
/// Follows the shape every live integration test shares (GOAL.md → Integration
/// testing strategy; see test/integration/README.md and
/// `jira_integration_test.dart`):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - gated on [gateVar] (`SHAREPOINT_SCOPES`), resolved through the standard
///   Phase 1 [PropertyReader] chain (real env → `dmtools.env` →
///   `dmtools-local.env`) — the same path production uses;
/// - skipped locally when the gate is absent; `DMTOOLS_IT_REQUIRE_CREDS=true`
///   turns that skip into a failure in the CI integration job;
/// - smoke path: auth → get drive (read-only).
///
/// SharePoint shares the Teams Graph transport, so auth additionally needs a
/// Graph access/refresh token; when the gate is open but no token is
/// configured the client construction fails loud, surfacing the incomplete
/// config rather than silently skipping.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Gate: a resolved `SHAREPOINT_SCOPES` selects *whether* to run. Absent →
/// skip.
const String gateVar = 'SHAREPOINT_SCOPES';

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
      'must fail loud rather than silently skip missing SharePoint scopes.',
    );
  }

  _sharepointSmokeGroup(gate);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _sharepointSmokeGroup(String gate) {
  group(
    'SharePoint live smoke path',
    () {
      late final SharepointClient client;
      setUpAll(() async {
        // A refresh token is not an access token — exchange it via the
        // OAuth2 flow (Java OAuth2AuthenticationFlow) before any Graph call.
        final accessToken =
            await TeamsOAuth.resolveAccessToken(PropertyReader());
        client = SharepointClient(
          TeamsHttpClient(PropertyReader(), token: accessToken),
        );
      });

      test('auth: testConnection resolves the default drive', () async {
        final result = await client.testConnection();

        expect(result['success'], isTrue, reason: 'authentication failed');
      });

      test('read: getDrive returns the default drive object', () async {
        final drive = await client.getDrive();

        expect(drive, contains('id'));
      });
    },
    skip: gate.isEmpty ? 'Set $gateVar to SharePoint scopes to run.' : null,
  );
}
