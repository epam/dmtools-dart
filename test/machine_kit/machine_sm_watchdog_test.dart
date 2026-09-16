/// gh-137 PR #138 rework: the README documents the machine-loop watchdog, so
/// the repository must actually carry it. The review's BLOCKING thread was a
/// dead link: the README referenced `.github/workflows/machine-sm.yml` (and
/// told readers to `gh workflow run machine-sm.yml -f dryRun=true`) while the
/// workflow existed only on the unmerged `sm-engine-switch` branch. These
/// tests pin, in the spirit of source_git_credentials_test.dart:
///   README.md                    — every workflow path it links must exist
///   .github/workflows/machine-sm.yml    — the watchdog contract the README states
///   .github/workflows/ai-teammate.yml   — the workflow_dispatch entry point
///                                   the SM dispatches (issue #116 dead letters)
/// so the documentation and the machine can never drift apart silently again.
import 'dart:io';

import 'package:test/test.dart';

const _readmePath = 'README.md';
const _smWorkflowPath = '.github/workflows/machine-sm.yml';
const _teammateWorkflowPath = '.github/workflows/ai-teammate.yml';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('missing expected file: $path');
  }
  return file.readAsStringSync();
}

void main() {
  _readmeWorkflowLinks();
  _smWatchdogContract();
  _teammateDispatchEntryPoint();
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

/// The watchdog contract the README states: a 10-minute reconciler cron, a
/// safe manual probe, one instance at a time, acting on THIS repository.
void _smWatchdogContract() {
  group('machine-sm.yml watchdog (gh-137 README claims)', () {
    final yaml = _read(_smWorkflowPath);

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

    test('dryRun propagates into the rule engine as plan-only', () {
      expect(
        yaml.contains('"dryRun":true'),
        isTrue,
        reason: 'the dispatched jobParams override must carry dryRun:true so '
            'the SM logs the plan and performs no action',
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

    test('reconciles THIS repository via the smAgent rule pack', () {
      expect(yaml, contains('dmtools run sm_github.json'));
      expect(
        yaml.contains(r'${{ github.repository }}'),
        isTrue,
        reason: 'the rule engine must be pinned to this repository (jobParams '
            'repo override), not a templated default',
      );
    });
  });
}

/// The SM's dispatch path: machine-sm.yml triggers ai-teammate.yml directly
/// because GITHUB_TOKEN-added labels never fire `labeled` events (issue #116).
void _teammateDispatchEntryPoint() {
  group('ai-teammate.yml workflow_dispatch entry point (SM dispatch path)', () {
    final yaml = _read(_teammateWorkflowPath);

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

    test('the guard pins the runner from the SM-provided leg', () {
      expect(yaml, contains(r'case "$INPUT_LEG" in'));
      expect(yaml, contains(r'rework) runner="$RUNNER_REWORK" ;;'));
      expect(yaml, contains(r'review) runner="$RUNNER_REVIEW" ;;'));
      expect(
        yaml.contains(r'runner="$RUNNER_BUG"'),
        isTrue,
        reason: 'a dispatched dev leg keeps the bug-vs-story routing (title '
            '[BUG]/bug label)',
      );
    });
  });
}
