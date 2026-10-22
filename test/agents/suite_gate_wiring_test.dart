import 'dart:io';

import 'package:test/test.dart';

/// gh-315 rework — review thread 1 (IMPORTANT): a `needs:`-dependent job
/// whose dependency fails reports conclusion `skipped`, and GitHub counts
/// skipped as a *successful* status for required checks. The gate jobs
/// must therefore run unconditionally (`if: always()`), fail explicitly
/// when their upstream result is not `success`, and keep their merge
/// steps gated on success — so a red shard produces a RED required
/// check, not a skipped one, even if a `pull_request` trigger is ever
/// added to quality.yml.
void main() {
  final quality = File('.github/workflows/quality.yml').readAsStringSync();
  _agentsGateTests(quality);
  _gateTests(quality);
}

void _agentsGateTests(String quality) {
  group('agents-gate job (quality.yml)', () {
    test('runs unconditionally with if: always()', () {
      expect(
        _jobBlock(quality, 'agents-gate'),
        contains('if: always()'),
        reason: 'a needs-failed dependent job is skipped, and skipped '
            'satisfies branch protection — the job must run and fail '
            'explicitly instead',
      );
    });

    test('fails explicitly when the agents-suite result is not success', () {
      final block = _jobBlock(quality, 'agents-gate');
      expect(
        block,
        contains("needs.agents-suite.result != 'success'"),
        reason: 'guard step must exit 1 on a red/cancelled shard',
      );
      expect(
        block,
        contains('exit 1'),
      );
    });

    test('gates the merge steps on the agents-suite result', () {
      final block = _jobBlock(quality, 'agents-gate');
      expect(
        block,
        contains("needs.agents-suite.result == 'success'"),
        reason: 'merge steps must not run against missing manifests',
      );
    });

    test('no longer claims that needs: alone reds the job', () {
      expect(
        quality,
        isNot(contains('already fails this job through `needs:`')),
        reason: 'the comment must state the real enforcement path '
            '(run-level red → SM validate → tick stamping) plus the '
            'explicit guard',
      );
    });
  });
}

void _gateTests(String quality) {
  group('gate job (quality.yml) — same latent hole', () {
    test('runs unconditionally with if: always()', () {
      expect(
        _jobBlock(quality, 'gate'),
        contains('if: always()'),
      );
    });

    test('fails explicitly when static or test did not succeed', () {
      final block = _jobBlock(quality, 'gate');
      expect(block, contains("needs.static.result != 'success'"));
      expect(block, contains("needs.test.result != 'success'"));
      expect(
        block,
        contains("needs.static.result == 'success' && "
            "needs.test.result == 'success'"),
        reason: 'merge steps must be gated on both upstream results',
      );
    });
  });
}

/// The YAML block of job [name]: from its `name:` line to the next
/// top-level job key (same indentation).
String _jobBlock(String yaml, String name) {
  final pattern =
      RegExp('^\\s*${RegExp.escape(name.trim())}:\\n', multiLine: true);
  final match = pattern.firstMatch(yaml);
  if (match == null) {
    fail('job $name not found in workflow');
  }
  final rest = yaml.substring(match.start);
  final nextJob = RegExp(r'^\S', multiLine: true).allMatches(rest).skip(1);
  final end = nextJob.isEmpty ? yaml.length : match.start + nextJob.first.start;
  return yaml.substring(match.start, end);
}
