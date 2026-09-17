/// Runner-wiring contract tests for the machine loop (gh-146 edition).
///
/// The per-leg runner configs live in `.dmtools/runners/` and are selected
/// by the factory guard via `.dmtools/config.js` `sm.runners`. Their
/// `parent` and prompt paths resolve at run time in the factory checkout
/// (`factory-agents/` — dmtools-agents cloned beside the target repo by the
/// factory workflow), which does not exist in this repository. Runner-level
/// wiring is therefore pinned on the raw runner JSON here, and the parent
/// side on the same content in the pinned `agents/` submodule.
///
/// Covered contracts:
/// - the review runner opts in to the formal GitHub review (gh-129) with
///   approve-with-suggestions, while the parent's own customParams survive
///   the deepMerge;
/// - the review runner extends the parent prompts with the verdict rules
///   (gh-71 machine protocol) and the rules file exists;
/// - the rework runner keeps its pack parent and the fa provider pin;
/// - the factory workflow invokes review-verdict.sh and defines the cap.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Map<String, dynamic> _runnerJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// The verdict-rules prompt exactly as the review runner references it
/// (cwd-relative; `factory-agents/` is the pack checkout at run time).
const _verdictRulesRunnerPath =
    './factory-agents/instructions/pr_review/review_verdict_rules.md';

/// In-repo copy of the verdict-rules instruction (agents/ submodule).
const _verdictRulesFile =
    'agents/instructions/pr_review/review_verdict_rules.md';

void main() {
  formalReviewWiringTests();
  wiringTests();
}

/// gh-129: the review runner must opt in to the formal GitHub review
/// (real APPROVE / REQUEST_CHANGES reviews, not just the pr_approved
/// label) while the parent's own customParams survive the deepMerge.
void formalReviewWiringTests() {
  group('machine wiring: formal review', () {
    test(
        'review runner turns on formalGithubReview '
        '(real approvals, not just labels)', () {
      final customParams =
          (_runnerJson('.dmtools/runners/fa-review-kimi.json')['params'])
              as Map;
      final runnerCustomParams = customParams['customParams'] as Map;
      expect(runnerCustomParams['formalGithubReview'], true);
      expect(runnerCustomParams['allowApproveWithSuggestions'], true);
      // deepMerge keeps the parent's own customParams alongside the flags
      // at run time — pinned here on the parent's in-repo copy.
      final parentCustomParams =
          (_runnerJson('agents/pr_review.json')['params'])['customParams']
              as Map;
      expect(parentCustomParams['removeLabel'], 'sm_story_review_triggered');
      expect(parentCustomParams['checkOpenPR'], true);
    });
  });
}

/// Contract tests: the runners + workflow must stay wired to the script and
/// the verdict-rules instruction file.
void wiringTests() {
  group('machine wiring', () {
    test('review runner extends parent prompts with the verdict rules', () {
      final runner = _runnerJson('.dmtools/runners/fa-review-kimi.json');
      final params = runner['params'] as Map;
      final prompts = (params['cliPrompts'] as List).cast<String>();
      expect(prompts, contains(_verdictRulesRunnerPath));
      // Parent prompts survive the merge (merge: ["params.cliPrompts"]).
      expect(runner['merge'], contains('params.cliPrompts'));
      final parentPrompts = ((_runnerJson('agents/pr_review.json')['params'])
          as Map)['cliPrompts'] as List;
      expect(parentPrompts.cast<String>(),
          contains('./agents/instructions/pr_review/general_guidelines.md'));
      expect(
        (params['customParams'] as Map)['allowApproveWithSuggestions'],
        true,
      );
    });

    test('verdict-rules instruction file exists', () {
      expect(File(_verdictRulesFile).existsSync(), isTrue);
    });

    test('rework runner still resolves against its parent', () {
      final runner = _runnerJson('.dmtools/runners/fa-rework-zai.json');
      expect((runner['parent'] as Map)['path'],
          '../../factory-agents/pr_rework.json');
      expect(
          ((runner['params'] as Map)['envVariables']
              as Map)['AI_AGENT_PROVIDER'],
          'fa');
    });

    test('workflow invokes the script and defines the cap', () {
      final yml = File('agents/.github/workflows/factory/teammate.yml')
          .readAsStringSync();
      expect(yml, contains('review-verdict.sh'));
      expect(yml, contains('MAX_AUTO_REWORK_ROUNDS'));
      expect(yml, contains('needs-human'));
    });
  });
}
