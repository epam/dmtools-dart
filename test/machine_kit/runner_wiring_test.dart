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

import 'package:dmtools/src/cli/run_command_processor.dart';
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
  resolutionTests();
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

/// gh-146 review thread 4 — the raw pins above cannot execute the
/// parent-chain deepMerge `dmtools run` performs: a typo in a `merge`
/// directive or a parent-shape change passes raw-pin tests and breaks the
/// leg at run time. This group reconstructs the factory layout locally —
/// the runner under `<tmp>/.dmtools/runners/`, its pinned parent copied
/// from the `agents/` submodule into `<tmp>/factory-agents/` (exactly the
/// `../../factory-agents/…` layout the runners reference) — and runs
/// [RunCommandProcessor] against the copied runner. Parent paths resolve
/// relative to the loaded file's directory, so no chdir is needed.
void resolutionTests() {
  group('machine wiring: runner resolution through RunCommandProcessor', () {
    late Directory tmp;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('fa_runner_resolution');
      Directory('${tmp.path}/factory-agents').createSync(recursive: true);
      Directory('${tmp.path}/.dmtools/runners').createSync(recursive: true);
      for (final name in _packAgents) {
        File('agents/$name').copySync('${tmp.path}/factory-agents/$name');
      }
      for (final runner in _runners) {
        File('.dmtools/runners/$runner')
            .copySync('${tmp.path}/.dmtools/runners/$runner');
      }
    });

    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('all four runners resolve their parent chain and keep the fa pin',
        () {
      for (final runner in _runners) {
        final params = _resolvedRunner(tmp, runner)['params'] as Map;
        final env = params['envVariables'] as Map;
        expect(env['AI_AGENT_PROVIDER'], 'fa',
            reason: '$runner must keep the fa provider pin after the '
                'parent-chain deepMerge');
      }
    });

    test(
        'review runner deep-merges gh-129 custom params '
        'alongside the parent\'s own', () {
      final params =
          _resolvedRunner(tmp, 'fa-review-kimi.json')['params'] as Map;
      final custom = params['customParams'] as Map;
      expect(custom['formalGithubReview'], isTrue);
      expect(custom['allowApproveWithSuggestions'], isTrue);
      expect(custom['checkOpenPR'], isTrue,
          reason: "the parent's own customParams must survive the "
              'deepMerge alongside the runner overrides');
    });

    test('merge directive appends the verdict rules to the parent prompts',
        () {
      final params =
          _resolvedRunner(tmp, 'fa-review-kimi.json')['params'] as Map;
      final parentPrompts = (_runnerJson('agents/pr_review.json')['params']
          as Map)['cliPrompts'] as List;
      final prompts = params['cliPrompts'] as List;
      expect(prompts, hasLength(parentPrompts.length + 1),
          reason: 'a missing/typoed "merge": ["params.cliPrompts"] would '
              'replace the parent prompts instead of appending');
      expect(prompts.take(parentPrompts.length), parentPrompts);
      expect(
        prompts.last,
        './factory-agents/instructions/pr_review/review_verdict_rules.md',
      );
    });
  });
}

/// The factory layout the runners reference: parents at repo-root
/// `factory-agents/`, runners under `.dmtools/runners/`.
const _packAgents = [
  'bug_development.json',
  'story_development.json',
  'pr_review.json',
  'pr_rework.json',
];
const _runners = [
  'fa-bug-dev.json',
  'fa-story-dev.json',
  'fa-review-kimi.json',
  'fa-rework-zai.json',
];

Map<String, dynamic> _resolvedRunner(Directory tmp, String runner) =>
    jsonDecode(
      const RunCommandProcessor()
          .process(['run', '${tmp.path}/.dmtools/runners/$runner']),
    ) as Map<String, dynamic>;
