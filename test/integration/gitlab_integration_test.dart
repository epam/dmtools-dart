/// L3 live integration test — GitLab smoke path (skeleton).
///
/// Documents the shape every live integration test follows (GOAL.md →
/// Integration testing strategy; see test/integration/README.md):
///
/// - tagged `integration`, so `dart_test.yaml` excludes it from the default
///   `dart test` run — run it explicitly with
///   `dart test -P integration -t integration`;
/// - targeted at a sandbox project via [gateVar] (`DMTOOLS_IT_GITLAB_PROJECT`),
///   which selects *where* to test, never *how* to authenticate;
/// - credentials resolved through the standard chain (real env → `dmtools.env`
///   → `dmtools-local.env`) by the Phase 1 [PropertyReader] — the same path
///   production uses. No test-specific config, no hardcoded values;
/// - skipped locally when the gate variable is absent; `DMTOOLS_IT_REQUIRE_CREDS`
///   turns that skip into a failure in the CI integration job so a rotting
///   secret cannot hide;
/// - smoke path first (auth → get MR → list MRs → note → cleanup), read-only
///   where a write is not the point of the test.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox GitLab project the tests target (e.g. `group/sandbox` or a numeric
/// id). Absent → skip.
const String gateVar = 'DMTOOLS_IT_GITLAB_PROJECT';

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
  _gitlabSmokeGroup(gate, runId);
}

/// Registers the smoke-path group, skipped when [gate] is empty.
void _gitlabSmokeGroup(String gate, String runId) {
  group(
    'GitLab live smoke path',
    () {
      late final GitlabHttpClient http;
      late final GitlabClient client;
      setUpAll(() {
        http = GitlabHttpClient(PropertyReader());
        client = GitlabClient(http);
      });
      _gitlabAuthTest(() => client);
      _gitlabMrTests(() => client, gate);
      _gitlabNoteTest(() => client, () => http, gate, runId);
    },
    skip: gate.isEmpty
        ? 'Set $gateVar to a sandbox GitLab project to run.'
        : null,
  );
}

/// Auth smoke test — [GitlabClient.testConnection] via GET `/user`.
void _gitlabAuthTest(GitlabClient Function() client) {
  test('auth: testConnection resolves the current user', () async {
    final result = await client().testConnection();

    expect(result['success'], isTrue, reason: 'authentication failed');
    expect(result['user'], isNotEmpty);
  });
}

/// MR get/list smoke tests. Both target [gate]; discovery uses `state=all` so a
/// sandbox with only merged/closed MRs still exercises the path.
void _gitlabMrTests(GitlabClient Function() client, String gate) {
  test('read: getMr fetches a sandbox merge request', () async {
    final iid = _firstMrIid(await client().listMrs(gate, 'all'));

    final mr = await client().getMr(gate, iid);

    expect(mr, isNotNull);
    expect(mr!['iid'], iid);
  });

  test('list: listMrs returns merge requests in the sandbox project', () async {
    final mrs = await client().listMrs(gate, 'all');

    expect(
      mrs,
      isNotEmpty,
      reason: 'sandbox project "$gate" has no merge requests to list',
    );
  });
}

/// Write smoke test — MR note round-trip, self-cleaning.
///
/// The note is deleted via the inherited [GitlabHttpClient.delete] in
/// [addTearDown]; [GitlabClient] has no note-delete method, so cleanup goes
/// one level down the transport. Fixtures never outlive the test.
void _gitlabNoteTest(
  GitlabClient Function() client,
  GitlabHttpClient Function() http,
  String gate,
  String runId,
) {
  test('write: MR note round-trip is self-cleaning', () async {
    final iid = _firstMrIid(await client().listMrs(gate, 'all'));
    final body = 'it-$runId-smoke note';

    final note = await client().createMrNote(gate, iid, body);
    expect(note, isNotNull, reason: 'note was not created');
    final noteId = note!['id'] as int;
    addTearDown(
      () => http().delete(
        'projects/${Uri.encodeComponent(gate)}/merge_requests/$iid'
        '/notes/$noteId',
      ),
    );

    expect(note['body'], body);
  });
}

/// Picks the iid of the first MR in [mrs], failing when none exist.
int _firstMrIid(List<Map<String, dynamic>> mrs) {
  if (mrs.isEmpty) {
    fail('sandbox project has no merge requests to read');
  }
  return mrs.first['iid'] as int;
}
