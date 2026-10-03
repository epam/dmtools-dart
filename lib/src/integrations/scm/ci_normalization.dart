/// CI-verdict and merge-state normalization for the vendor-neutral
/// `scm_*` / `ci_*` alias layer (gh-339).
///
/// The alias layer returns ONLY the pinned enums — the SM never sees raw
/// provider values:
///
/// - Verdict: `pass | fail | pending | none` (AC6). Every GitHub
///   check-run conclusion and every GitLab pipeline/job/commit status
///   maps to exactly one verdict; anything unmappable is `pending` —
///   never a crash, never a silent pass.
/// - Merge state: `CLEAN | BEHIND | DIRTY | BLOCKED | UNKNOWN` — the enum
///   the SM already speaks (AC7). Both vendors' "checks settling"
///   transients translate to `BLOCKED` + `reason`, so the SM's
///   no-unarm-on-BLOCKED rule stays intact.
///
/// Rollup rule across several checks for one head: any `fail` wins;
/// otherwise any `pending` wins; otherwise (at least one `pass`) `pass`;
/// no evidence at all is `none`.
library;

/// The pinned 4-value verdict enum.
const String verdictPass = 'pass';
const String verdictFail = 'fail';
const String verdictPending = 'pending';
const String verdictNone = 'none';

/// GH check-run conclusions that are conclusive failures.
const _ghFailConclusions = {'failure', 'timed_out'};

/// GH check-run conclusions that produced NO verdict about the head.
///
/// `neutral` completed without a pass/fail answer, `cancelled` says
/// nothing about the head (the SM's cancelled-is-not-a-verdict rule,
/// live gh-191), `action_required` needs a human, `skipped`/`stale` ran
/// nothing current, `startup_failure` never ran.
const _ghPendingConclusions = {
  'neutral',
  'cancelled',
  'canceled',
  'action_required',
  'skipped',
  'stale',
  'startup_failure',
};

/// GL statuses that are conclusive failures (`fail` is the commit-status
/// spelling of `failed`).
const _glFailStatuses = {'failed', 'fail'};

/// Normalizes one GitHub check-run conclusion (or Actions run conclusion)
/// to the verdict enum. In-flight statuses and unmappable values are
/// [verdictPending].
String ghConclusionVerdict(String? raw) {
  final c = raw?.trim().toLowerCase() ?? '';
  if (_ghFailConclusions.contains(c)) return verdictFail;
  if (c == 'success') return verdictPass;
  return verdictPending;
}

/// Rollup of a `check_runs` array (decoded GitHub check-run objects) to
/// one verdict. Empty input is [verdictNone] — no evidence at all.
String ghCheckRunsVerdict(List<dynamic> runs) {
  final verdicts = <String?>[];
  for (final run in runs) {
    final map = run is Map ? run : null;
    final conclusion = map?['conclusion'] as String?;
    verdicts.add(
      conclusion == null
          ? _statusVerdict(map?['status'] as String?)
          : ghConclusionVerdict(conclusion),
    );
  }
  return _rollupVerdicts(verdicts);
}

/// One GitHub Actions run (status + conclusion) to a verdict: a
/// non-completed run has no verdict yet.
String ghRunVerdict(String? status, String? conclusion) =>
    _rollupVerdicts([
      (status?.trim().toLowerCase() ?? '') == 'completed'
          ? ghConclusionVerdict(conclusion)
          : verdictPending,
    ]);

/// Normalizes one GitLab pipeline/job/commit status to the verdict enum.
/// Unmappable values are [verdictPending].
String gitlabStatusVerdict(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  if (_glFailStatuses.contains(s)) return verdictFail;
  if (s == 'success') return verdictPass;
  return verdictPending;
}

/// Rollup of a GitLab pipeline/status list (`[{status: …}, …]`) to one
/// verdict. Empty input is [verdictNone].
String gitlabStatusListVerdict(List<dynamic> items) => _rollupVerdicts([
      for (final item in items)
        gitlabStatusVerdict((item as Map?)?['status'] as String?),
    ]);

/// A per-check verdict candidate: `null` marks "no evidence from this
/// check" (excluded from the rollup rather than read as pending).
String? _statusVerdict(String? status) {
  final s = status?.trim().toLowerCase() ?? '';
  const inFlight = {'queued', 'in_progress', 'waiting', 'pending'};
  if (s.isEmpty || inFlight.contains(s)) return verdictPending;
  return null;
}

/// The pinned rollup: any fail wins, then any pending, then a unanimous
/// pass; an empty candidate list is [verdictNone].
String _rollupVerdicts(Iterable<String?> verdicts) {
  var sawPass = false;
  var sawPending = false;
  for (final v in verdicts) {
    if (v == verdictFail) return verdictFail;
    if (v == verdictPending) {
      sawPending = true;
    } else if (v == verdictPass) {
      sawPass = true;
    }
  }
  if (sawPending) return verdictPending;
  return sawPass ? verdictPass : verdictNone;
}

/// A normalized merge state — the SM enum plus an optional machine
/// reason for the `BLOCKED` transients (AC7).
class MergeState {
  /// One of `CLEAN`, `BEHIND`, `DIRTY`, `BLOCKED`, `UNKNOWN`.
  final String state;

  /// Machine-readable reason, set for `BLOCKED` transients.
  final String? reason;

  /// Creates a merge state.
  const MergeState(this.state, {this.reason});

  /// The alias wire shape: `{"mergeState": …, "reason": …}`.
  Map<String, dynamic> toJson() => {
        'mergeState': state,
        if (reason != null) 'reason': reason,
      };
}

const _ghBlockedReasons = {
  'has_hooks': 'has-hooks',
  'draft': 'draft',
  'unstable': 'unstable',
};

/// GitHub merge state from a PR body (`mergeable`, REST
/// `mergeable_state`, GraphQL `mergeStateStatus`).
///
/// `mergeable === false` is the deterministic DIRTY override; `blocked`
/// survives as `BLOCKED` (`required-checks-pending`) — masking it as
/// CLEAN deadlocked armed fresh PRs (live dart #195).
MergeState ghMergeState({
  dynamic mergeable,
  String? mergeableState,
  String? mergeStateStatus,
}) {
  if (mergeable == false) return const MergeState('DIRTY');
  final raw = (mergeStateStatus ??
          (mergeableState != null && mergeableState.isNotEmpty
              ? mergeableState.toUpperCase()
              : null)) ??
      '';
  final ms = raw.trim().toLowerCase();
  if (ms == 'clean') return const MergeState('CLEAN');
  if (ms == 'dirty') return const MergeState('DIRTY');
  if (ms == 'behind') return const MergeState('BEHIND');
  if (ms == 'blocked') {
    return const MergeState('BLOCKED', reason: 'required-checks-pending');
  }
  final blockedReason = _ghBlockedReasons[ms];
  if (blockedReason != null) return MergeState('BLOCKED', reason: blockedReason);
  return MergeState(mergeable == true ? 'CLEAN' : 'UNKNOWN');
}

const _glBlockedReasons = {
  'blocked': 'branch-protection',
  'ci_still_running': 'ci-still-running',
  'ci_must_pass': 'ci-must-pass',
  'discussions_not_resolved': 'discussions-not-resolved',
  'draft_status': 'draft',
  'pinned_thread': 'pinned-thread',
};

const _glDirtyDetailedStatuses = {'has_conflicts', 'broken_status'};

/// GitLab merge state from an MR body (`merge_status`,
/// `detailed_merge_status`, `has_conflicts`).
///
/// Conflict shapes are `DIRTY` (the ticket's mapping — the JS-level
/// smProvider twin reads them as BEHIND; the alias is the normalized
/// truth). `ci_still_running` is the pinned GL transient: `BLOCKED` +
/// `ci-still-running`, the counterpart of GitHub's `blocked`
/// checks-settling form.
MergeState gitlabMergeState({
  String? mergeStatus,
  String? detailedMergeStatus,
  dynamic hasConflicts,
}) {
  final ms = mergeStatus?.trim().toLowerCase() ?? '';
  if (ms == 'not_open') return const MergeState('UNKNOWN');
  if (hasConflicts == true) return const MergeState('DIRTY');
  final detailed = detailedMergeStatus?.trim().toLowerCase() ?? '';
  final blockedReason = _glBlockedReasons[detailed];
  if (blockedReason != null) return MergeState('BLOCKED', reason: blockedReason);
  if (_glDirtyDetailedStatuses.contains(detailed)) {
    return const MergeState('DIRTY');
  }
  if (detailed == 'checking') return const MergeState('UNKNOWN');
  if (ms == 'can_be_merged') return const MergeState('CLEAN');
  if (ms == 'cannot_be_merged' || ms == 'cannot_be_merged_rechecking') {
    return const MergeState('DIRTY');
  }
  return const MergeState('UNKNOWN');
}
