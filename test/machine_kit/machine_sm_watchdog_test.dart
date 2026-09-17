/// The machine-loop workflow contract, stub + factory edition.
///
/// The repository carries THIN STUBS (.github/workflows/ai-teammate.yml,
/// machine-sm.yml) over the reusable factory pack in the agents submodule
/// (agents/.github/workflows/factory/). The submodule is pinned, so both
/// layers are part of this repo's merge tree and both are pinned here:
///
///   README.md                              — linked workflow files exist
///   .github/workflows/machine-sm.yml       — stub: cron, dry dispatch, call
///   .github/workflows/ai-teammate.yml      — stub: triggers, per-issue
///                                             concurrency, dispatch inputs
///   agents/.github/workflows/factory-sm.yml       — tick engine contract
///   agents/.github/workflows/factory-teammate.yml — leg runner contract
///
/// so the documentation and the machine can never drift apart silently.
import 'dart:io';

import 'package:test/test.dart';

const _readmePath = 'README.md';
const _smStubPath = '.github/workflows/machine-sm.yml';
const _teammateStubPath = '.github/workflows/ai-teammate.yml';
const _smFactoryPath = 'agents/.github/workflows/factory-sm.yml';
const _teammateFactoryPath = 'agents/.github/workflows/factory-teammate.yml';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('missing expected file: $path');
  }
  return file.readAsStringSync();
}

void main() {
  _readmeWorkflowLinks();
  _smStubContract();
  _smFactoryContract();
  _teammateStubContract();
  _teammateFactoryContract();
}

/// BLOCKING review thread (PR #138): a README workflow link is a promise that
/// the file is in the merge tree. Check every `.github/workflows/*.yml`
/// markdown reference, not just machine-sm.yml — the next new section must
/// fail this test too, not silently ship a dead link.
void _readmeWorkflowLinks() {
  group('README workflow links resolve to files in the repository', () {
    final finalLink = RegExp(r'\]\((\.github/workflows/[^)#\s]+\.yml)\)');
    final linked = finalLink
        .allMatches(_read(_readmePath))
        .map((m) => m.group(1)!)
        .toSet();

    test(
        'the README references at least one workflow (guard against a '
        'silently weakened pattern)', () {
      expect(linked, isNotEmpty);
    });

    for (final path in linked) {
      test('$path exists', () {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'README links $path but the file is absent — a dead link '
              'on main and, if it documents a command, a failing command '
              '(gh-137 PR #138 BLOCKING review thread)',
        );
      });
    }
  });
}

/// The stub carries what a reusable workflow cannot: the cron trigger, the
/// manual dry probe, the single-instance group, and the call itself.
void _smStubContract() {
  group('machine-sm.yml stub (gh-137 README claims)', () {
    final yaml = _read(_smStubPath);

    test('runs the */10 reconciler cron the README calls the safety net', () {
      expect(
        yaml.contains("cron: '*/10 * * * *'"),
        isTrue,
        reason: 'the README documents a cron that re-fires stalled loop legs '
            'every 10 minutes; a slower/absent schedule breaks that promise',
      );
    });

    test('manual dispatch exposes the boolean dryRun input the README probes',
        () {
      expect(yaml, contains('workflow_dispatch:'));
      final inputsBlock = yaml.split('workflow_dispatch:').last;
      expect(inputsBlock, contains('dryRun:'));
      expect(
        inputsBlock.contains('type: boolean'),
        isTrue,
        reason: "`gh workflow run machine-sm.yml -f dryRun=true` (README) "
            'only works against a boolean input named dryRun',
      );
    });

    test('never runs two reconcilers concurrently', () {
      final concurrencyBlock = yaml.split('concurrency:').last;
      expect(concurrencyBlock, contains('group: machine-sm'));
      expect(
        concurrencyBlock.contains('cancel-in-progress: false'),
        isTrue,
        reason: 'an in-flight reconcile must finish; a second tick must '
            'queue, not interrupt it',
      );
    });

    test('calls the factory with the dryRun passthrough', () {
      expect(
        yaml,
        contains(
            'uses: IstiN/dmtools-agents/.github/workflows/factory-sm.yml@'),
        reason: 'the tick engine lives in the factory pack; the stub must '
            'call it (pinned ref)',
      );
      expect(
        yaml.contains(r'dryRun: ${{ github.event.inputs.dryRun || false }}'),
        isTrue,
        reason: 'manual ticks default to dry; cron ticks run live — the '
            'input must fall through exactly that way',
      );
      expect(yaml, contains('secrets: inherit'));
    });
  });
}

/// The tick engine: dryRun must reach the rule engine as plan-only, and the
/// rules must be pinned to the CALLING repository.
void _smFactoryContract() {
  group('factory/sm.yml tick engine', () {
    final yaml = _read(_smFactoryPath);

    test('dryRun propagates into the rule engine as plan-only', () {
      expect(
        yaml.contains(r'"dryRun\":true'),
        isTrue,
        reason: 'the dispatched jobParams override must carry dryRun:true so '
            'the SM logs the plan and performs no action',
      );
    });

    test('reconciles the CALLING repository via the smAgent rule pack', () {
      expect(yaml, contains('dmtools run sm_github.json'));
      expect(
        yaml.contains(r'${{ github.repository }}'),
        isTrue,
        reason: 'a reusable workflow runs in the caller context — the rule '
            'engine must be pinned to github.repository, not a hardcoded repo',
      );
    });
  });
}

/// The stub carries the repository event triggers (issues + dispatch) and
/// the per-issue concurrency group; the deep leg logic is factory-side.
void _teammateStubContract() {
  group('ai-teammate.yml stub (dispatch entry point, issue #116 path)', () {
    final yaml = _read(_teammateStubPath);

    test('declares workflow_dispatch with issue/leg/reason inputs', () {
      expect(yaml, contains('workflow_dispatch:'));
      expect(yaml, contains('issue:'));
      expect(yaml, contains('leg:'));
      expect(yaml, contains('reason:'));
      final inputsBlock = yaml.split('workflow_dispatch:').last;
      expect(inputsBlock, contains('options: [dev, review, rework]'),
          reason: 'the leg choice must mirror the runner legs the guard maps');
    });

    test('issue-number expressions fall back to the dispatch input', () {
      expect(
        yaml.contains(
            'ai-teammate-issue-${r'${{ github.event.issue.number || github.event.inputs.issue }}'}'),
        isTrue,
        reason: 'dispatched runs carry no issue event payload — the '
            'concurrency group (and every other issue-number expression) '
            'must fall back to github.event.inputs.issue',
      );
    });

    test('calls the factory teammate pack with the issue number', () {
      expect(
        yaml,
        contains(
            'uses: IstiN/dmtools-agents/.github/workflows/factory-teammate.yml@'),
      );
      expect(
        yaml,
        contains(
            r'issue: ${{ github.event.issue.number || github.event.inputs.issue }}'),
        reason: 'the factory guard needs the issue number regardless of '
            'whether the trigger was an event or a dispatch',
      );
      expect(yaml, contains('secrets: inherit'));
    });
  });
}

/// The leg runner: runners resolve from THIS repo's .dmtools/config.js
/// (sm.runners), never from factory-internal defaults.
void _teammateFactoryContract() {
  group('factory/teammate.yml leg runner', () {
    final yaml = _read(_teammateFactoryPath);

    test('the guard pins the runner from the SM-provided leg', () {
      expect(yaml, contains(r'case "$INPUT_LEG" in'));
      expect(
        yaml,
        contains(r'rework) runner="$RUNNER_REWORK"; slot="rework" ;;'),
        reason: 'each leg pins both the runner and its parent-pipeline slot '
            '(custom runners inherit session semantics by slot)',
      );
      expect(
        yaml,
        contains(r'review) runner="$RUNNER_REVIEW"; slot="review" ;;'),
      );
      expect(
        yaml.contains(r'runner="$RUNNER_BUG"'),
        isTrue,
        reason: 'a dispatched dev leg keeps the bug-vs-story routing (title '
            '[BUG]/bug label)',
      );
    });

    test('runners resolve from the target .dmtools/config.js, not the pack',
        () {
      expect(
        yaml.contains('.dmtools/config.js'),
        isTrue,
        reason: 'repo-specific agents live in the target repository '
            '(dmtools-agents#424 review); the factory resolves sm.runners '
            'from the caller config',
      );
      expect(
        yaml.contains('sm.runners'),
        isTrue,
      );
      expect(
        yaml.contains('configs/runners/'),
        isFalse,
        reason: 'factory-internal runner paths would shadow the target '
            'repository wiring',
      );
    });
  });
}
