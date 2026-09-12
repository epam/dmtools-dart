import 'dart:io';

import 'package:test/test.dart';

/// Regression tests for the gh-50 rework of
/// `.github/workflows/ai-teammate-issues.yml`.
///
/// gh-50 kills the `FA_LOG_FILE` + `tail -F | sed` follower: live
/// visibility of the agent run now comes from dmtools' own stderr
/// mirroring. The same rewrite must NOT drop the zero-maintainer review
/// cycle main shipped in #58/#61:
///
///   review run → "Apply the review verdict" step →
///     APPROVE (+ green CI on the PR head) → pr_approved label →
///       merge-trigger.yml squash-merges the linked PR
///     CHANGES_REQUESTED / BLOCK → agent:rework label → rework run
///
/// The verdict step parses the run output captured to
/// `.dmtools/run-output.txt`; without that capture (and the step) an
/// APPROVE verdict would never produce the `pr_approved` label and the
/// auto-merge loop dies silently — exactly what the merge from main
/// (ddc4deb) kept from the branch's over-broad deletion. These structural
/// pins make the keystone impossible to lose again while keeping gh-50's
/// follower ban enforced.
void main() {
  final workflow =
      File('.github/workflows/ai-teammate-issues.yml').readAsStringSync();

  group('ai-teammate-issues.yml review cycle', () {
    test('verdict step survives the gh-50 rewrite', () {
      expect(workflow, contains('- name: Apply the review verdict'));
    });

    test('verdict step labels both cycle outcomes', () {
      expect(workflow, contains('--add-label "pr_approved"'));
      expect(workflow, contains('--add-label "agent:rework"'));
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
