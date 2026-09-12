import 'dart:io';

import 'package:test/test.dart';

/// Pins the review-cycle wiring of [ai-teammate-issues.yml] to the
/// gh-71 verdict machinery: the decision comes from
/// machine-kit/teammate-install/scripts/review-verdict.sh (unit-tested in
/// test/machine_kit/review_verdict_test.dart — pr_review.json is
/// authoritative, token-grep is only the JSON-absent fallback), fed the
/// issue labels (round cap) and the tee'd run output. The workflow itself
/// must NOT inline a transcript parser: gh-50 mirrors every child output
/// line into the run output, so a workflow-side grep would match verdict
/// tokens the agent merely QUOTED (workflow docs, review-format files,
/// reasoning lines) and flip a genuine APPROVE into a spurious
/// agent:rework loop.
void main() {
  final workflow =
      File('.github/workflows/ai-teammate-issues.yml').readAsStringSync();

  _reviewCycleGroup(workflow);
  _verdictDelegationGroup(workflow);
}

/// The run/verdict step wiring itself: the verdict step exists, labels
/// every cycle outcome, and consumes exactly the output the run step
/// captures (gh-50: captured via tee while dmtools mirrors child output
/// live to stderr — no `tail -F` follower side-channel).
void _reviewCycleGroup(String workflow) {
  group('ai-teammate-issues.yml review cycle', () {
    test('verdict step survives the gh-50 rewrite', () {
      expect(workflow, contains('- name: Apply the review verdict'));
    });

    test('verdict step labels all cycle outcomes', () {
      expect(workflow, contains('--add-label "pr_approved"'));
      expect(workflow, contains('--add-label "agent:rework"'));
      expect(workflow, contains('--add-label "needs-human"'));
    });

    test('run step captures the output the verdict parser consumes', () {
      expect(
        workflow,
        contains(r'RUN_OUTPUT="${GITHUB_WORKSPACE}/.dmtools/run-output.txt"'),
      );
      expect(workflow, contains(r'tee "${RUN_OUTPUT}"'));
    });

    test('run step propagates the dmtools exit code through the tee', () {
      expect(workflow, contains(r'RC=${PIPESTATUS[0]}'));
      expect(workflow, contains(r'exit "${RC}"'));
    });

    test('no tail -F follower (gh-50: live streaming is dmtools stderr)', () {
      expect(workflow, isNot(contains('tail -n +1 -F')));
      expect(workflow, isNot(contains('FOLLOWER_PID')));
      expect(workflow, isNot(contains(r"sed -u 's/^/[fa] /'")));
    });
  });
}

/// gh-71: the decision logic lives in the shared, unit-tested
/// review-verdict.sh — the workflow only wires its inputs (round cap,
/// labels, run output) and must not grow an inline parser copy that
/// could drift from the tested script.
void _verdictDelegationGroup(String workflow) {
  group('ai-teammate-issues.yml verdict step delegates to review-verdict.sh',
      () {
    test('decision comes from review-verdict.sh, not an inline parser', () {
      expect(
        workflow,
        contains(
          'bash machine-kit/teammate-install/scripts/review-verdict.sh decide',
        ),
      );
    });

    test('the script sees the round cap, labels, and run output', () {
      expect(workflow, contains(r'MAX_ROUNDS="${MAX_ROUNDS}"'));
      expect(workflow, contains(r'ISSUE_LABELS="${labels}"'));
      expect(workflow, contains(r'RUN_OUTPUT="${RUN_OUTPUT}"'));
    });

    test('escalation hands over to a human instead of looping', () {
      // gh-71 round cap: cap reached ⇒ needs-human + thread summary,
      // never another automatic agent:rework round.
      expect(workflow, contains(r'[ "$escalate" = "true" ]'));
    });

    test('no inline transcript parser remains (transcript safety)', () {
      // The pre-gh-71 inline parser (trailing-JSON extraction + shape
      // guard + classification regexes) moved into review-verdict.sh; a
      // copy left in the workflow would drift from the tested script.
      expect(workflow, isNot(contains('result_line=')));
      expect(workflow, isNot(contains('shape_ok')));
      expect(workflow, isNot(contains(r'CHANGES[_ ]REQUESTED')));
    });
  });
}
