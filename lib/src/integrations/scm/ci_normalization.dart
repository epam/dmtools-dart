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

/// The pinned merge-state enum (AC7) — the vocabulary the SM speaks.

/// No blocker, head == base.
const String stateClean = 'CLEAN';

/// Head is behind base but otherwise mergeable.
const String stateBehind = 'BEHIND';

/// Conflicts — a human must resolve before the SM may arm.
const String stateDirty = 'DIRTY';

/// Checks/protection still settling (carries a [MergeState.reason]).
const String stateBlocked = 'BLOCKED';

/// No evidence (unknown mergeability or non-open PR).
const String stateUnknown = 'UNKNOWN';

/// The pinned 4-value verdict enum (AC6).
const String verdictPass = 'pass';

/// A conclusive failure (GH `failure`/`timed_out`, GL `failed`).
const String verdictFail = 'fail';

/// No verdict yet — in-flight, cancelled, skipped, or unmappable.
const String verdictPending = 'pending';

/// No evidence at all (an empty rollup).
const String verdictNone = 'none';

/// GH check-run conclusions that are conclusive failures.
const _ghFailConclusions = {'failure', 'timed_out'};

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
String ghRunVerdict(String? status, String? conclusion) => _rollupVerdicts([
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
  'blocked': 'required-checks-pending',
  'has_hooks': 'has-hooks',
  'draft': 'draft',
  'unstable': 'unstable',
};

/// GitHub merge-state tokens that map straight to a state (no reason).
const _ghSimpleStates = {
  'clean': stateClean,
  'dirty': stateDirty,
  'behind': stateBehind,
};

/// Normalized lowercase state token from the REST (`mergeable_state`) /
/// GraphQL (`mergeStateStatus`) spellings — GraphQL wins when both are
/// present.
String _ghStateToken(String? mergeStateStatus, String? mergeableState) {
  final raw = mergeStateStatus ??
      (mergeableState != null && mergeableState.isNotEmpty
          ? mergeableState.toUpperCase()
          : '');
  return raw.trim().toLowerCase();
}

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
  if (mergeable == false) return const MergeState(stateDirty);
  final ms = _ghStateToken(mergeStateStatus, mergeableState);
  final simple = _ghSimpleStates[ms];
  if (simple != null) return MergeState(simple);
  final blockedReason = _ghBlockedReasons[ms];
  if (blockedReason != null) {
    return MergeState(stateBlocked, reason: blockedReason);
  }
  return MergeState(mergeable == true ? stateClean : stateUnknown);
}

const _glBlockedReasons = {
  'blocked': 'branch-protection',
  'ci_still_running': 'ci-still-running',
  'ci_must_pass': 'ci-must-pass',
  'discussions_not_resolved': 'discussions-not-resolved',
  'draft_status': 'draft',
  'pinned_thread': 'pinned-thread',
};

/// GL `detailed_merge_status` values that map straight to a state.
const _glDetailedStates = {
  'checking': stateUnknown,
  'has_conflicts': stateDirty,
  'broken_status': stateDirty,
};

/// GL `merge_status` values that map straight to a state.
const _glMergeStatusStates = {
  'can_be_merged': stateClean,
  'cannot_be_merged': stateDirty,
  'cannot_be_merged_rechecking': stateDirty,
};

/// Trimmed, lowercased provider status spelling.
String _normalizeStatus(String? raw) => raw?.trim().toLowerCase() ?? '';

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
  if (_normalizeStatus(mergeStatus) == 'not_open') {
    return const MergeState(stateUnknown);
  }
  if (hasConflicts == true) return const MergeState(stateDirty);
  final detailed = _normalizeStatus(detailedMergeStatus);
  final blockedReason = _glBlockedReasons[detailed];
  if (blockedReason != null) {
    return MergeState(stateBlocked, reason: blockedReason);
  }
  return MergeState(
    _glDetailedStates[detailed] ??
        _glMergeStatusStates[_normalizeStatus(mergeStatus)] ??
        stateUnknown,
  );
}
