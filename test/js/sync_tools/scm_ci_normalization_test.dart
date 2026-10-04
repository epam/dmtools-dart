/// Verdict + merge-state normalization tables for the `scm_*`/`ci_*` alias
/// layer (gh-339 AC6/AC7).
///
/// The alias returns ONLY the 4-value verdict enum (`pass|fail|pending|none`)
/// and the 5-value merge-state enum the SM already speaks
/// (`CLEAN|BEHIND|DIRTY|BLOCKED|UNKNOWN`) — the SM never sees raw provider
/// enums. Every GH check-run conclusion and every GL pipeline/job status
/// maps to exactly one verdict; anything unmappable is `pending` (never
/// crash, never silent pass).
library;

import 'dart:convert';

import 'package:dmtools/src/integrations/scm/ci_normalization.dart';
import 'package:test/test.dart';

void main() {
  ghVerdictTableTests();
  glVerdictTableTests();
  ghVerdictRollupTests();
  glVerdictRollupTests();
  ghMergeStateTests();
  gitlabMergeStateTests();
  gitlabMergeStateTransientTests();
}

/// AC6 — every GH conclusion value maps to exactly one of the 4 verdicts.
void ghVerdictTableTests() {
  group('GH conclusion → verdict table', () {
    test('conclusive values', () {
      expect(ghConclusionVerdict('success'), 'pass');
      expect(ghConclusionVerdict('failure'), 'fail');
      expect(ghConclusionVerdict('timed_out'), 'fail');
    });

    test('non-verdict values are pending — never a silent pass', () {
      // neutral completed without a verdict; cancelled says nothing about
      // the head (the SM's cancelled-is-not-a-verdict rule, live gh-191);
      // action_required needs a human; skipped/stale ran nothing current.
      for (final c in const [
        'neutral',
        'cancelled',
        'canceled',
        'action_required',
        'skipped',
        'stale',
        'startup_failure',
      ]) {
        expect(ghConclusionVerdict(c), 'pending', reason: c);
      }
    });

    test('in-flight statuses are pending', () {
      for (final s in const [
        'queued',
        'in_progress',
        'waiting',
        'pending',
        null,
        '',
      ]) {
        expect(ghConclusionVerdict(s), 'pending', reason: '$s');
      }
    });

    test('unmappable garbage is pending (negative case, never crash)', () {
      for (final g in const ['YELP', 'whatever', 'pass']) {
        expect(ghConclusionVerdict(g), 'pending', reason: g);
      }
    });

    test('input is case-insensitive (REST arrives lowercase, SM uppercases)',
        () {
      expect(ghConclusionVerdict('SUCCESS'), 'pass');
      expect(ghConclusionVerdict('TIMED_OUT'), 'fail');
    });
  });
}

void glVerdictTableTests() {
  group('GL status → verdict table', () {
    test('conclusive values', () {
      expect(gitlabStatusVerdict('success'), 'pass');
      expect(gitlabStatusVerdict('failed'), 'fail');
    });

    test('every documented GL pipeline/job status is pending or conclusive',
        () {
      // The full GL status alphabet (11 pipeline + commit statuses) —
      // nothing may fall through as a crash or a silent pass.
      for (final s in const [
        'created',
        'waiting_for_resource',
        'preparing',
        'pending',
        'running',
        'scheduled',
        'canceled',
        'canceled_by_caller',
        'skipped',
        'manual',
      ]) {
        expect(gitlabStatusVerdict(s), 'pending', reason: s);
      }
      expect(gitlabStatusVerdict('fail'), 'fail',
          reason: 'commit-status spelling of failed');
    });

    test('unmappable garbage is pending (negative case)', () {
      expect(gitlabStatusVerdict('YELP'), 'pending');
      expect(gitlabStatusVerdict(null), 'pending');
    });
  });
}

/// Rollup semantics across several checks for one head.
void ghVerdictRollupTests() {
  group('check-run rollup', () {
    test('empty rollup is none — no evidence at all', () {
      expect(ghCheckRunsVerdict(const []), 'none');
    });

    test('any failure is fail (multi-item case)', () {
      final v = ghCheckRunsVerdict([
        {'conclusion': 'success'},
        {'conclusion': 'failure'},
      ]);
      expect(v, 'fail');
    });

    test('all success is pass', () {
      expect(
        ghCheckRunsVerdict([
          {'conclusion': 'success'},
          {'conclusion': 'success'},
        ]),
        'pass',
      );
    });

    test('success + cancelled is pending — cancelled poisons the pass', () {
      // smProvider rule (live gh-191): a cancelled sibling means the head
      // has no complete verdict; the next tick re-runs CI.
      expect(
        ghCheckRunsVerdict([
          {'conclusion': 'success'},
          {'conclusion': 'cancelled'},
        ]),
        'pending',
      );
    });

    test('in-flight status without conclusion is pending', () {
      expect(
        ghCheckRunsVerdict([
          {'status': 'IN_PROGRESS'},
        ]),
        'pending',
      );
    });

    test('all-cancelled is pending, not none and not fail', () {
      expect(
        ghCheckRunsVerdict([
          {'conclusion': 'cancelled'},
          {'conclusion': 'cancelled'},
        ]),
        'pending',
      );
    });
  });
}

void glVerdictRollupTests() {
  group('GL status-list rollup', () {
    test('empty is none', () {
      expect(gitlabStatusListVerdict(const []), 'none');
    });

    test('any failed is fail', () {
      expect(
        gitlabStatusListVerdict([
          {'status': 'success'},
          {'status': 'failed'},
        ]),
        'fail',
      );
    });

    test('success + running is pending', () {
      expect(
        gitlabStatusListVerdict([
          {'status': 'success'},
          {'status': 'running'},
        ]),
        'pending',
      );
    });
  });
}

/// AC7 — the merge-state enum the SM already speaks.
void ghMergeStateTests() {
  group('GH merge state', () {
    test('REST mergeable_state maps 1:1 onto the SM enum', () {
      expect(ghMergeState(mergeableState: 'clean').state, 'CLEAN');
      expect(ghMergeState(mergeableState: 'dirty').state, 'DIRTY');
      expect(ghMergeState(mergeableState: 'behind').state, 'BEHIND');
    });

    test('BLOCKED survives with the checks-settling reason (AC7 transient)',
        () {
      final ms = ghMergeState(mergeableState: 'blocked');
      expect(ms.state, 'BLOCKED');
      expect(ms.reason, 'required-checks-pending');
    });

    test('mergeable === false is DIRTY (deterministic override)', () {
      expect(ghMergeState(mergeable: false, mergeableState: 'clean').state,
          'DIRTY');
    });

    test('GraphQL mergeStateStatus spelling is honored too', () {
      expect(
        ghMergeState(mergeStateStatus: 'BEHIND', mergeable: true).state,
        'BEHIND',
      );
    });

    test('has_hooks/draft/unstable are BLOCKED variants with reasons', () {
      expect(ghMergeState(mergeableState: 'has_hooks').state, 'BLOCKED');
      expect(ghMergeState(mergeableState: 'draft').reason, 'draft');
      expect(ghMergeState(mergeableState: 'unstable').reason, 'unstable');
    });

    test('unknown/absent verdict falls back to mergeable', () {
      expect(ghMergeState(mergeable: true).state, 'CLEAN');
      expect(ghMergeState(mergeable: null).state, 'UNKNOWN');
    });

    test("the mergeability-computing transient 'unknown' is never CLEAN", () {
      expect(
        ghMergeState(mergeableState: 'unknown', mergeable: true).state,
        'UNKNOWN',
        reason: 'GitHub reports mergeable_state unknown while '
            'mergeability is still being computed — mapping it to CLEAN '
            '(via the mergeable tiebreaker) would let the SM arm on an '
            'uncomputed PR; the tiebreaker is for genuinely unrecognized '
            'tokens only',
      );
    });

    test('garbage state never crashes — UNKNOWN', () {
      expect(ghMergeState(mergeableState: 'YELP', mergeable: null).state,
          'UNKNOWN');
    });
  });
}

void gitlabMergeStateTests() {
  group('GL merge state', () {
    test('can_be_merged without conflicts is CLEAN', () {
      expect(
        gitlabMergeState(
          mergeStatus: 'can_be_merged',
          hasConflicts: false,
        ).state,
        'CLEAN',
      );
    });

    test('conflict shapes are DIRTY (ticket mapping, not the JS BEHIND twin)',
        () {
      expect(
        gitlabMergeState(mergeStatus: 'cannot_be_merged').state,
        'DIRTY',
      );
      expect(
        gitlabMergeState(
          mergeStatus: 'can_be_merged',
          hasConflicts: true,
        ).state,
        'DIRTY',
      );
    });

    test('ci_still_running is BLOCKED + reason (the pinned GL transient)', () {
      final ms = gitlabMergeState(
        mergeStatus: 'can_be_merged',
        detailedMergeStatus: 'ci_still_running',
      );
      expect(ms.state, 'BLOCKED');
      expect(ms.reason, 'ci-still-running');
      // Both providers translate their transient to BLOCKED+reason —
      // the SM's no-unarm-on-BLOCKED rule stays intact (AC7).
      expect(ghMergeState(mergeableState: 'blocked').state, ms.state);
    });
  });
}

void gitlabMergeStateTransientTests() {
  Map<String, dynamic> decode(MergeState ms) =>
      jsonDecode(jsonEncode(ms.toJson())) as Map<String, dynamic>;

  group('GL merge state', () {
    test('protection shapes are BLOCKED with reasons', () {
      for (final d in const [
        'blocked',
        'ci_must_pass',
        'discussions_not_resolved',
        'draft_status',
        'pinned_thread',
      ]) {
        expect(
          gitlabMergeState(
                  mergeStatus: 'cannot_be_merged', detailedMergeStatus: d)
              .state,
          'BLOCKED',
          reason: d,
        );
      }
    });

    test('checking has no verdict yet — UNKNOWN', () {
      expect(gitlabMergeState(mergeStatus: 'checking').state, 'UNKNOWN');
    });

    test('not_open is UNKNOWN', () {
      expect(gitlabMergeState(mergeStatus: 'not_open').state, 'UNKNOWN');
    });

    test('toJSON round-trips (the alias wire shape)', () {
      final ms = gitlabMergeState(
        mergeStatus: 'can_be_merged',
        detailedMergeStatus: 'ci_still_running',
      );
      expect(decode(ms)['mergeState'], 'BLOCKED');
      expect(decode(ms)['reason'], 'ci-still-running');
    });
  });
}
