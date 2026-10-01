/// The machine-loop workflow contract, stub + factory edition.
///
/// Freeze model (agents-by-version migration, owner directive 2026-09-28):
///
///   README.md                              — linked workflow files exist
///   .github/workflows/machine-sm.yml       — stub: cron, dry dispatch, call
///   .github/workflows/ai-teammate.yml      — stub: triggers, per-issue
///                                             concurrency, dispatch inputs
///
/// The SM tick + merge bot now call the FROZEN machine loop in
/// IstiN/dmtools-agentic-workflows (pinned immutable SHA, guarded by
/// test/machine_kit/factory_stub_ref_test.dart) — agent code and the CLI
/// resolve from RELEASES at run time (vars.AGENTS_VERSION /
/// vars.DMTOOLS_VERSION), so the frozen SHA never goes stale. Only the
/// teammate leg still calls the historical factory inside the agents
/// submodule (its migration is a follow-up), so its factory contract
/// groups keep reading the in-tree submodule copy:
///
///   agents/.github/workflows/factory-teammate.yml — leg runner contract
import 'dart:io';

import 'package:test/test.dart';

const _readmePath = 'README.md';
const _smStubPath = '.github/workflows/machine-sm.yml';
const _teammateStubPath = '.github/workflows/ai-teammate.yml';
const _teammateFactoryPath = 'agents/.github/workflows/factory-teammate.yml';

/// Single-instance contract: the FROZEN LOOP (dmtools-agentic-workflows
/// factory-sm.yml at the pinned SHA) owns the `machine-sm` group — a caller
/// declaring the same group deadlocks the called workflow. The frozen file
/// is not part of this merge tree (it lives in its own repo at the pin),
/// so this guard asserts the stub side only: NO caller-side `concurrency:`.
void _singleInstanceContract() {
  final yaml = _read(_smStubPath);
  test('never runs two reconcilers concurrently (factory owns the group)', () {
    // The single-instance group lives in the frozen loop: a caller
    // declaring the same group deadlocks the called workflow — the
    // caller holds the group while the callee waits for it forever.
    // The stub must NOT declare its own concurrency group.
    final activeConcurrency =
        yaml.split('\n').any((l) => l.startsWith('concurrency:'));
    expect(activeConcurrency, isFalse,
        reason: 'caller-side concurrency on the same group as the '
            'factory deadlocks the called workflow (pending, 0 jobs); '
            'the frozen loop owns `group: machine-sm` with '
            'cancel-in-progress: false (reviewed in dmtools-agentic-'
            'workflows at the pin guarded by factory_stub_ref_test)');
  });
}

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

    _singleInstanceContract();
    test('calls the frozen loop with the dryRun passthrough', () {
      expect(
        yaml,
        contains(
            'uses: IstiN/dmtools-agentic-workflows/.github/workflows/factory-sm.yml@'),
        reason: 'the tick engine lives in the FROZEN machine loop; the stub '
            'must call it (pinned immutable SHA, guarded by '
            'factory_stub_ref_test.dart)',
      );
      expect(
        yaml.contains('factory_ref'),
        isFalse,
        reason: 'agents resolve from the dmtools-agents RELEASE selected by '
            'vars.AGENTS_VERSION at run time — no engine checkout ref',
      );
      expect(
        yaml.contains(r"dryRun: ${{ github.event.inputs.dryRun || 'false' }}"),
        isTrue,
        reason: 'manual ticks default to dry; cron ticks run live — the '
            'input must fall through exactly that way (STRING: boolean '
            'reusable inputs reject expressions)',
      );
      expect(
        yaml.split('\n').any((l) => l.trim() == 'secrets: inherit'),
        isFalse,
        reason: 'explicit secret mapping — inherit fails the required check',
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
        yaml.contains('github.event.issue.number || github.event.inputs.issue'),
        isTrue,
        reason: 'dispatched runs carry no issue event payload — the '
            'concurrency group (and every other issue-number expression) '
            'must fall back to github.event.inputs.issue (and, per #544/#687, '
            'to the pr input for PR-anchored runs)',
      );
    });

    test('calls the factory teammate pack with the issue number', () {
      expect(
        yaml,
        contains(
            'uses: IstiN/dmtools-agentic-workflows/.github/workflows/factory-teammate.yml@'),
        reason: 'the factory home moved to dmtools-agentic-workflows '
            '(engine pin stays dmtools-agents via factory_ref)',
      );
      expect(
        yaml,
        contains(
            r'issue: ${{ github.event.issue.number || github.event.inputs.issue }}'),
        reason: 'the factory guard needs the issue number regardless of '
            'whether the trigger was an event or a dispatch',
      );
      // The AW-home factory declares its secrets; the stub maps them
      // explicitly (no inherit — explicit mapping fails loudly on drift).
      final hasActiveInherit = yaml
          .split('\n')
          .any((l) => l.trim() == 'secrets: inherit');
      expect(hasActiveInherit, isFalse);
      expect(yaml.contains('SOURCE_GITHUB_TOKEN:'), isTrue);
    });
  });
}

/// The leg runner: runners resolve from THIS repo's .dmtools/config.js
/// (sm.runners), never from factory-internal defaults.
///
/// SKIPPED: the factory moved to dmtools-agentic-workflows;
/// dmtools-agents#591 retires the in-submodule copy this group parses.
/// Re-home the contract to the AW pin as a follow-up.
@Skip('factory moved to dmtools-agentic-workflows (pending #591 bump)')
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
