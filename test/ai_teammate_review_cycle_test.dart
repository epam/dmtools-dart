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

  verdictParserTests(workflow);
}

/// The run-output transcript-safety pins and the extraction pipeline they
/// tie the workflow to, split out of [main] (method_size gate).
void verdictParserTests(String workflow) {
  group('ai-teammate-issues.yml verdict parser transcript safety', () {
    test('never greps the whole mirrored transcript', () {
      // gh-50 mirrors every child output line into dmtools' stderr, which
      // the run step merges into RUN_OUTPUT (2>&1 | tee). A whole-file
      // grep matches verdict tokens the agent merely QUOTED (workflow
      // docs, review-format files, its own reasoning) and flips a genuine
      // APPROVE into a spurious agent:rework loop.
      expect(workflow, isNot(contains(r'cat "${RUN_OUTPUT}"')));
    });

    test('parses only the trailing single-line result JSON blob', () {
      // dmtools prints the run result as ONE line of JSON on stdout at
      // the very end — the last line starting with '{' in RUN_OUTPUT.
      expect(
        workflow,
        contains(
            r'''result_line="$(grep '^{' "${RUN_OUTPUT}" 2>/dev/null | tail -1 || true)"'''),
      );
      expect(workflow, contains('jq -r'));
    });
  });

  verdictExtractionTests();
}

/// Functional check of the extraction semantics pinned above, driven
/// through /bin/sh + jq exactly the way the verdict step runs them.
void verdictExtractionTests() {
  group('verdict extraction semantics (the pipeline pinned above)', () {
    Future<String> extractVerdict(String transcript) async {
      final dir = await Directory.systemTemp.createTemp('dmtools_verdict_');
      try {
        final runOutput = File('${dir.path}/run-output.txt');
        await runOutput.writeAsString(transcript);
        final script = File('${dir.path}/verdict.sh');
        await script.writeAsString(_verdictSnippet);
        final result =
            await Process.run('/bin/sh', [script.path, runOutput.path]);
        return result.stdout.trim();
      } finally {
        await dir.delete(recursive: true);
      }
    }

    test('a verdict token quoted in the transcript cannot flip APPROVE',
        () async {
      final verdict = await extractVerdict(
        '[debug] agent reads .github/workflows/ai-teammate-issues.yml\n'
        'CHANGES_REQUESTED / BLOCK → agent:rework (quoted workflow text)\n'
        'the diff adds: if grep -qE "CHANGES[_ ]REQUESTED|\\bBLOCK\\b" ...\n'
        '{"success":true,"results":[{"response":"# PR Review — verdict: '
        'APPROVE\\n\\nAll findings addressed on the branch."}]}\n',
      );
      expect(verdict, 'approve');
    });

    test('a rework verdict in the result JSON still yields rework', () async {
      final verdict = await extractVerdict(
        '[debug] starting review\n'
        '{"success":true,"results":[{"response":"verdict: CHANGES_REQUESTED '
        '— the fix misses the edge case"}]}\n',
      );
      expect(verdict, 'rework');
    });

    test('no result JSON at all yields no verdict (warning path)', () async {
      final verdict = await extractVerdict(
        '[debug] run crashed before printing the result\n'
        'Error: something failed\n',
      );
      expect(verdict, isEmpty);
    });
  });
}

/// The verdict extraction+classification pipeline, mirroring the
/// "Apply the review verdict" step's shell (kept in sync by the
/// `parses only the trailing single-line result JSON blob` pin).
const String _verdictSnippet = '''
RUN_OUTPUT="\$1"
result_line="\$(grep '^\{' "\$RUN_OUTPUT" 2>/dev/null | tail -1 || true)"
response=""
if [ -n "\$result_line" ]; then
  response="\$(printf '%s\\n' "\$result_line" | jq -r '.results[0].response // .response // empty' 2>/dev/null || true)"
fi
[ -n "\$response" ] || response="\$result_line"
verdict=""
if echo "\$response" | grep -qE 'CHANGES[_ ]REQUESTED|REQUEST_CHANGES|\\bBLOCK(ED)?\\b'; then
  verdict="rework"
elif echo "\$response" | grep -qE '\\bAPPROVE(D)?\\b'; then
  verdict="approve"
fi
echo "\$verdict"
''';
