/// gh-261 regression guards: the Release CLI `version and tag` job pushes
/// the version-bump commit straight to the protected `main`, satisfying
/// branch protection by stamping success check-runs for the required
/// contexts through the checks API (dm.ai release.yml pattern, ported 1:1).
///
/// When #187 split quality.yml into static/test/gate, branch protection
/// followed (the `quality` aggregate retired, `gate` + `static` became
/// required) — but the release workflow kept stamping the dead `quality`
/// name. Every release run since (34, 35, 36) died in "Push commit and
/// tag" with `GH006: Protected branch update failed ... 2 of 3 required
/// status checks are expected`, misread by the retry loop as "main moved".
///
/// These tests pin the stamped set to the contexts branch protection
/// requires and pin the retry-loop semantics that let the old failure
/// masquerade as a fast-forward race. If quality.yml renames a required
/// job again, the tests here and the workflow must move in lockstep.
library;

import 'dart:io';

import 'package:test/test.dart';

const _workflowPath = '.github/workflows/release-cli.yml';
const _qualityPath = '.github/workflows/quality.yml';

/// The contexts branch protection on `main` requires — the non-matrix
/// quality.yml surface (`gate` summarizes the `test (n)` shards).
const _requiredContexts = {'static', 'gate', 'agents-suite'};

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('missing expected file: $path');
  }
  return file.readAsStringSync();
}

void main() {
  final workflow = _read(_workflowPath);
  final quality = _read(_qualityPath);

  group('release-cli stamps the branch-protection-required contexts', () {
    test('stamped context set is exactly {static, gate, agents-suite}', () {
      final stampLoop =
          RegExp(r'for ctx in (.+?); do').firstMatch(workflow);
      expect(stampLoop, isNotNull,
          reason: '$_workflowPath must stamp the required check-runs via '
              'a `for ctx in <names>; do` loop (dm.ai release.yml pattern)');
      final stamped =
          stampLoop!.group(1)!.trim().split(RegExp(r'\s+')).toSet();
      expect(stamped, _requiredContexts,
          reason: 'branch protection on main requires {${_requiredContexts.join(', ')}}; '
              'stamping {${stamped.join(', ')}} leaves the push rejected '
              'with "N of M required status checks are expected" (gh-261)');
    });

    test('the retired `quality` aggregate is no longer stamped', () {
      final stampLoop =
          RegExp(r'for ctx in (.+?); do').firstMatch(workflow)!;
      expect(stampLoop.group(1), isNot(contains('quality')),
          reason: 'no workflow has produced a `quality` check-run since '
              '#187 renamed the aggregate to `gate` — stamping it cannot '
              'satisfy any required context');
    });

    test('every stamped context is a real quality.yml job name', () {
      final jobs = _qualityJobNames(quality);
      for (final ctx in _requiredContexts) {
        expect(jobs, contains(ctx),
            reason: 'the release stamps `$ctx` as success — if quality.yml '
                'renamed that job, branch protection and the stamp set here '
                'must be updated in lockstep (gh-261: #187 renamed '
                'quality → gate and the releases silently broke)');
      }
    });
  });

  group('push retry loop cannot loop on protection declines', () {
    test('a rebase is followed by a re-stamp (new SHA has no check-runs)',
        () {
      final callCount =
          'stamp_required_checks'.allMatches(workflow).length;
      expect(callCount, greaterThanOrEqualTo(3),
          reason: 'the stamp helper must be defined and invoked before the '
              'first push, and re-invoked inside the retry loop');
      final lines = workflow.split('\n');
      final rebaseLine = lines.indexWhere((l) => l.contains('git rebase '));
      expect(rebaseLine, greaterThanOrEqualTo(0),
          reason: 'the rebase-retry loop must exist (dm.ai parity)');
      final restampAfterRebase = lines
          .skip(rebaseLine + 1)
          .toList()
          .indexWhere((l) => l.trim() == 'stamp_required_checks');
      expect(restampAfterRebase, greaterThanOrEqualTo(0),
          reason: 'a rebase creates a NEW commit SHA whose required '
              'check-runs do not exist — without a re-stamp the retry '
              'attempt is rejected again and the loop burns all attempts');
    });

    test('a protection decline aborts instead of rebasing', () {
      final lines = workflow.split('\n');
      final declineGuard = lines
          .indexWhere((l) => l.contains('protected branch hook declined'));
      final rebaseLine = lines.indexWhere((l) => l.contains('git rebase '));
      expect(declineGuard, greaterThanOrEqualTo(0),
          reason: 'the push output must be inspected for the protection '
              'decline (GH006 "protected branch hook declined") — gh-261');
      expect(declineGuard, lessThan(rebaseLine),
          reason: 'the decline guard must run BEFORE the fetch/rebase '
              'fallback: rebasing cannot fix branch protection, and the '
              'old "main moved — rebasing" message lied about the cause '
              '(gh-261 runs 34/35/36)');
      expect(workflow, contains('::error::'),
          reason: 'a protection decline must surface a ::error:: naming '
              'the real cause instead of three identical retries');
    });
  });
}

/// Top-level job keys of quality.yml (2-space indent under `jobs:`).
Set<String> _qualityJobNames(String yml) {
  final lines = yml.split('\n');
  final jobsIndex = lines.indexWhere((l) => l.trim() == 'jobs:');
  expect(jobsIndex, greaterThanOrEqualTo(0),
      reason: 'quality.yml must declare jobs');
  final names = <String>{};
  for (final line in lines.skip(jobsIndex + 1)) {
    if (line.trim().isEmpty) {
      continue;
    }
    final job = RegExp(r'^  ([A-Za-z0-9_-]+):\s*$').firstMatch(line);
    if (job != null) {
      names.add(job.group(1)!);
      continue;
    }
    if (!line.startsWith('    ')) {
      break; // left the jobs: block (next 0-indent top-level key)
    }
  }
  return names;
}
