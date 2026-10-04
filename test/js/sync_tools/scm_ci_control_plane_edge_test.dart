/// Control-plane edge behaviors (gh-339 review round 2): the
/// post-dispatch run-handle race and the E1 error-envelope passthrough.
///
/// The run listing lags a dispatch by seconds, so `_ghRunIdLookup` may
/// only hand out a provably-fresh `workflow_dispatch` run. And a
/// provider error envelope must pass through verbatim — `none`,
/// `UNKNOWN` and `{runs: []}` are semantically meaningful success values
/// for the SM, so a misconfigured environment must never masquerade as
/// "no CI evidence" (and a GitLab error envelope must never crash the
/// `as List?` rollups).
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'scm_ci_sync_tools_fixture.dart';

void main() {
  withScmCiEnv(() {
    runIdLookupHardeningTests();
    ghErrorEnvelopeTests();
    ghErrorEnvelopeVerdictTests();
    glErrorEnvelopeTests();
    glErrorEnvelopeVerdictTests();
  });
}

/// Runs `ci_trigger_workflow` against a fake that lists [runs] after the
/// accepted trigger.
Map<String, dynamic> triggerAndDecode(List<Map<String, dynamic>> runs) {
  final tools = ghSubject({
    'github_trigger_workflow': (args) => '"ok"',
    'github_list_workflow_runs': (args) => jsonEncode({'workflow_runs': runs}),
  });
  return decode(tools.handlers['ci_trigger_workflow']!(
    {'workspace': 'o', 'repository': 'r', 'workflow': 'ci.yml', 'ref': 'main'},
  ));
}

Map<String, dynamic> listedRun(
  int id, {
  String? at,
  String event = 'workflow_dispatch',
}) =>
    {
      'id': id,
      'head_branch': 'main',
      'event': event,
      if (at != null) 'created_at': at,
    };

/// Only a provably-fresh `workflow_dispatch` run may become the handle.
void runIdLookupHardeningTests() {
  group('ci_trigger_workflow run handle (GH)', () {
    test('a run created before the dispatch is never the handle', () {
      final out = triggerAndDecode([
        listedRun(900,
            at: DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 10))
                .toIso8601String()),
      ]);
      expect(out['runId'], isNull,
          reason: 'that is the previous run — polling it would read a '
              'stale verdict for this trigger');
    });

    test('a push-event run on the ref is never the handle', () {
      final out = triggerAndDecode([
        listedRun(901,
            at: DateTime.now().toUtc().toIso8601String(), event: 'push')
      ]);
      expect(out['runId'], isNull,
          reason: 'a dispatch cannot claim a push-triggered run');
    });

    test('a run without a parseable created_at is never the handle', () {
      final out = triggerAndDecode([listedRun(902)]);
      expect(out['runId'], isNull,
          reason: 'without a timestamp the run cannot be proven fresh — '
              'null is the honest handle');
    });

    test('a fresh workflow_dispatch run on the ref is the handle', () {
      final out = triggerAndDecode(
          [listedRun(903, at: DateTime.now().toUtc().toIso8601String())]);
      expect(out['runId'], 903);
    });
  });
}

/// Two completed runs on different branches — the payload for the
/// client-side ref-filter test.
String twoRunsOnBranches() => jsonEncode({
      'workflow_runs': [
        {
          'id': 1,
          'head_branch': 'release-1.2',
          'status': 'completed',
          'conclusion': 'success',
        },
        {
          'id': 2,
          'head_branch': 'main',
          'status': 'completed',
          'conclusion': 'failure',
        },
      ],
    });

Map<String, dynamic> ghAlias(
  String alias,
  Map<String, Handler> fake,
  Map<String, dynamic> args,
) =>
    decode(ghSubject(fake).handlers[alias]!(args));

Map<String, dynamic> glAlias(
  String alias,
  Map<String, Handler> fake,
  Map<String, dynamic> args,
) =>
    decode(glSubject(fake).handlers[alias]!(args));

void ghErrorEnvelopeTests() {
  group('ci_* error envelopes (E1, GH)', () {
    test('ci_list_runs passes the provider error through', () {
      final out = ghAlias('ci_list_runs', {
        'github_list_workflow_runs': (args) =>
            '{"error":"GitHub not configured"}',
      }, {
        'workspace': 'o',
        'repository': 'r',
        'workflow': 'ci.yml'
      });
      expect(out['error'], 'GitHub not configured',
          reason: 'not {runs: []} — that would read as a repo with no CI');
    });

    test('ci_list_runs honors the documented ref filter', () {
      final out = ghAlias('ci_list_runs', {
        'github_list_workflow_runs': (args) => twoRunsOnBranches(),
      }, {
        'workspace': 'o',
        'repository': 'r',
        'workflow': 'ci.yml',
        'ref': 'release-1.2'
      });
      final runs = out['runs'] as List;
      expect(runs, hasLength(1),
          reason: 'the concrete tool has no server-side ref filter — the '
              'alias must filter client-side or answer on the wrong branch '
              'looks legitimate');
      expect(runs.single['runId'], 1);
    });

    test('ci_get_merge_state passes the provider error through', () {
      final out = ghAlias('ci_get_merge_state', {
        'github_get_pr': (args) => '{"error":"GitHub not configured"}',
      }, {
        'workspace': 'o',
        'repository': 'r',
        'pr': 12
      });
      expect(out['error'], 'GitHub not configured',
          reason: 'not mergeState UNKNOWN — that reads as a legit no-CI '
              'signal to the SM');
    });
  });
}

void ghErrorEnvelopeVerdictTests() {
  group('ci_get_verdict error envelopes (E1, GH)', () {
    test('sha-probe passes the check-runs error through (not none)', () {
      final out = ghAlias('ci_get_verdict', {
        'github_get_commit_check_runs': (args) =>
            '{"error":"GitHub API 502: bad gateway"}',
      }, {
        'workspace': 'o',
        'repository': 'r',
        'sha': 'abc'
      });
      expect(out['error'], contains('502'));
      expect(out['verdict'], isNull);
    });

    test('sha-probe passes the workflow-fallback error through', () {
      final out = ghAlias('ci_get_verdict', {
        'github_get_commit_check_runs': (args) => '{"check_runs": []}',
        'github_list_workflow_runs': (args) =>
            '{"error":"GitHub API 502: bad gateway"}',
      }, {
        'workspace': 'o',
        'repository': 'r',
        'sha': 'abc',
        'workflow': 'ci.yml'
      });
      expect(out['error'], contains('502'));
      expect(out['verdict'], isNull);
    });
  });
}

void glErrorEnvelopeTests() {
  group('ci_* error envelopes (E1, GL)', () {
    test('ci_list_runs passes the provider error through (no cast crash)', () {
      final out = glAlias('ci_list_runs', {
        'gitlab_list_pipeline_runs': (args) =>
            '{"error":"GitLab API 500: boom"}',
      }, {
        'workspace': 'g',
        'repository': 'r'
      });
      expect(out['error'], contains('500'),
          reason: 'a map-shaped envelope is not a List — no TypeError');
    });

    test('ci_trigger_workflow passes the trigger error through', () {
      final out = glAlias('ci_trigger_workflow', {
        'gitlab_trigger_pipeline': (args) =>
            '{"error":"GitLab API 422: invalid ref"}',
      }, {
        'workspace': 'g',
        'repository': 'r',
        'workflow': 'x.yml',
        'ref': 'nope'
      });
      expect(out['error'], contains('422'));
    });

    test('ci_get_merge_state passes the provider error through', () {
      final out = glAlias('ci_get_merge_state', {
        'gitlab_get_mr': (args) => '{"error":"GitLab not configured"}',
      }, {
        'workspace': 'g',
        'repository': 'r',
        'pr': 4
      });
      expect(out['error'], 'GitLab not configured');
    });
  });
}

void glErrorEnvelopeVerdictTests() {
  group('ci_get_verdict error envelopes (E1, GL)', () {
    test('pr-probe passes the provider error through (no cast crash)', () {
      final out = glAlias('ci_get_verdict', {
        'gitlab_get_mr_pipelines': (args) =>
            '{"error":"GitLab API 401: bad credentials"}',
      }, {
        'workspace': 'g',
        'repository': 'r',
        'pr': 4
      });
      expect(out['error'], contains('401'));
      expect(out['verdict'], isNull);
    });

    test('sha-probe passes the provider error through (no cast crash)', () {
      final out = glAlias('ci_get_verdict', {
        'gitlab_get_commit_statuses': (args) =>
            '{"error":"GitLab API 404: not found"}',
      }, {
        'workspace': 'g',
        'repository': 'r',
        'sha': 'abc'
      });
      expect(out['error'], contains('404'));
      expect(out['verdict'], isNull);
    });
  });
}
