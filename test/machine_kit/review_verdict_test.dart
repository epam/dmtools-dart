/// Unit tests for the machine's review-loop decision logic (gh-71).
///
/// The ai-teammate workflow must converge instead of looping forever:
///
/// 1. Approve-with-suggestions must actually approve — a REQUEST_CHANGES
///    verdict with zero BLOCKING findings is downgraded to approve (the
///    review protocol: only correctness/bug findings block), and the
///    authoritative verdict comes from `outputs/pr_review.json`, not from
///    token-grepping free text that may mention prior "request changes"
///    threads.
/// 2. The auto-rework loop is capped — after MAX_ROUNDS automatic rework
///    rounds (tracked via `rework-round-<n>` issue labels) the machine
///    escalates to `needs-human` instead of labeling `agent:rework` again.
///
/// The logic lives in `machine-kit/teammate-install/scripts/review-verdict.sh`
/// so the workflow step stays a thin wrapper (and this decision surface is
/// testable without `gh`/network).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  verdictFromReviewJsonTests();
  verdictOverrideTests();
  verdictMarkerCrossCheckTests();
  verdictMarkerOverrideStillAppliesTests();
  verdictSourcePriorityTests();
  verdictFallbackToRunOutputTests();
  roundCapProgressionTests();
  roundCapEscalationTests();
  roundCapBookkeepingTests();
  threadSummaryTests();
  wiringTests();
  verdictLabelWiringTests();
}

/// Verdict resolution, layer 1: `outputs/pr_review.json` is authoritative.
void verdictFromReviewJsonTests() {
  group('decide: verdict from pr_review.json', () {
    test('APPROVE wins even with suggestion/important counts present', () {
      final d = _decide(
        reviewJson: '{"recommendation":"APPROVE","issueCounts":'
            '{"blocking":0,"important":2,"suggestions":3}}',
      );
      expect(d['decision'], 'approve');
      expect(d['override'], 'false');
      expect(d['source'], 'pr_review_json');
    });

    test('APPROVED is normalized to approve', () {
      final d = _decide(reviewJson: '{"recommendation":"APPROVED"}');
      expect(d['decision'], 'approve');
    });

    test('REQUEST_CHANGES with 1 blocking finding → rework', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":1,"important":0,"suggestions":0}}',
      );
      expect(d['decision'], 'rework');
      expect(d['override'], 'false');
    });

    test('REQUEST_CHANGES with 2 blocking findings → rework', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":2,"important":1,"suggestions":5}}',
      );
      expect(d['decision'], 'rework');
    });

    test('BLOCK is never overridden, even with zero blocking counts', () {
      final d = _decide(
        reviewJson: '{"recommendation":"BLOCK","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":1}}',
      );
      expect(d['decision'], 'rework');
      expect(d['override'], 'false');
    });
  });
}

/// The gh-71 core: REQUEST_CHANGES with zero BLOCKING findings converges to
/// approve (approve-with-suggestions) instead of looping rework rounds.
void verdictOverrideTests() {
  group('decide: blocking-0 override', () {
    test('REQUEST_CHANGES with zero blocking findings → approve (gh-71)', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":4}}',
      );
      expect(d['decision'], 'approve');
      expect(d['override'], 'true');
    });

    test('REQUEST_CHANGES with only important findings → approve', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":1,"suggestions":0}}',
      );
      expect(d['decision'], 'approve');
      expect(d['override'], 'true');
    });

    test('REQUEST_CHANGES with missing issueCounts → approve', () {
      final d = _decide(reviewJson: '{"recommendation":"REQUEST_CHANGES"}');
      expect(d['decision'], 'approve');
      expect(d['override'], 'true');
    });

    test('falls back to the verdict key when recommendation is absent', () {
      final d = _decide(
        reviewJson: '{"verdict":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":2}}',
      );
      expect(d['decision'], 'approve');
      expect(d['override'], 'true');
    });

    test('ticket-scoped alt path (outputs/gh-N/) is honored', () {
      final d = _decide(
        reviewJsonAlt: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":2}}',
      );
      expect(d['decision'], 'approve');
      expect(d['source'], 'pr_review_json');
    });
  });
}

/// The blocking-0 override must cross-check the review's own inline
/// comments before it converts an explicit REQUEST_CHANGES into an
/// approval: issueCounts is written by the same reviewer that produced the
/// verdict, so a miscount has an irreversible consequence (auto-merge).
/// The override only fires when the counter AND the inline-comment marker
/// scan agree on zero blocking findings.
void verdictMarkerCrossCheckTests() {
  group('decide: blocking-marker cross-check (inline comments)', () {
    test('a severity=BLOCKING inline comment keeps the rework verdict', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":2},"inlineComments":'
            '[{"path":"lib/a.dart","line":3,"severity":"BLOCKING",'
            '"comment":"pr_review_comments/c1.md"}]}',
      );
      expect(d['decision'], 'rework');
      expect(d['override'], 'false');
    });

    test(
        'a 🚨 marker in the referenced comment file counts even when the '
        'severity field was mislabeled', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":1,"suggestions":0},"inlineComments":'
            '[{"path":"lib/a.dart","line":3,"severity":"IMPORTANT",'
            '"comment":"pr_review_comments/c1.md"}]}',
        commentFiles: const {
          'pr_review_comments/c1.md':
              '🚨 **BLOCKING: off-by-one**\nthe loop drops the last element',
        },
      );
      expect(d['decision'], 'rework');
      expect(d['override'], 'false');
    });
  });
}

/// The cross-check must not eat the override it guards: suggestion-level
/// (or unreadable) inline comments leave the approve convergence intact.
void verdictMarkerOverrideStillAppliesTests() {
  group('decide: marker cross-check keeps the override usable', () {
    test('suggestion-level inline comments do not block the override', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":2},"inlineComments":'
            '[{"path":"lib/a.dart","line":3,"severity":"SUGGESTION",'
            '"comment":"pr_review_comments/c1.md"}]}',
        commentFiles: const {
          'pr_review_comments/c1.md': '💡 reword the dartdoc reference',
        },
      );
      expect(d['decision'], 'approve');
      expect(d['override'], 'true');
    });

    test(
        'inline comments without severities or readable files keep the '
        'override', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0},"inlineComments":'
            '[{"path":"lib/a.dart","line":3},{"path":"lib/b.dart","line":9,'
            '"severity":"IMPORTANT","comment":"pr_review_comments/missing.md"}]}',
      );
      expect(d['decision'], 'approve');
      expect(d['override'], 'true');
    });

    test('the marker scan is reported in the emitted assignments', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":0},"inlineComments":'
            '[{"path":"lib/a.dart","line":3,"severity":"BLOCKING"}]}',
      );
      expect(d['blocking_markers'], '1');
    });
  });
}

/// Source priority: the machine-readable verdict wins over prose, and a
/// broken pr_review.json degrades to the legacy token fallback.
void verdictSourcePriorityTests() {
  group('decide: verdict source priority', () {
    test('JSON verdict beats CHANGES-tokens in free text', () {
      final d = _decide(
        reviewJson: '{"recommendation":"APPROVE","issueCounts":'
            '{"blocking":0,"important":0,"suggestions":1}}',
        runOutput: '... prior round was REQUEST_CHANGES; threads now resolved '
            '... verdict: APPROVE ...',
      );
      expect(d['decision'], 'approve');
      expect(d['source'], 'pr_review_json');
    });

    test('malformed JSON falls through to the run-output fallback', () {
      final d = _decide(
        reviewJson: '{"recommendation": BROKEN',
        runOutput: 'verdict: CHANGES_REQUESTED',
      );
      expect(d['decision'], 'rework');
      expect(d['source'], 'run_output');
    });
  });
}

/// Verdict resolution, layer 2: token-grep fallback for runs that produced
/// no pr_review.json (legacy behavior, preserved).
void verdictFallbackToRunOutputTests() {
  group('decide: run-output token fallback', () {
    for (final entry in {
      'verdict: CHANGES_REQUESTED': 'rework',
      'CHANGES REQUESTED by the reviewer': 'rework',
      'the review verdict is REQUEST_CHANGES': 'rework',
      'verdict: BLOCK': 'rework',
      'review BLOCKED the PR': 'rework',
      'verdict: APPROVE': 'approve',
      'review submitted: APPROVED': 'approve',
    }.entries) {
      test('"${entry.key}" → ${entry.value}', () {
        final d = _decide(runOutput: entry.key);
        expect(d['decision'], entry.value);
        expect(d['source'], 'run_output');
      });
    }

    test('changes-token beats approve-token (stricter first)', () {
      final d = _decide(
        runOutput: 'no longer REQUEST_CHANGES — everything is APPROVE now',
      );
      expect(d['decision'], 'rework');
    });

    test('no verdict token anywhere → unknown, nothing labeled', () {
      final d = _decide(runOutput: 'the run finished without a verdict');
      expect(d['decision'], 'unknown');
      expect(d['escalate'], 'false');
    });

    test('no inputs at all → unknown', () {
      final d = _decide();
      expect(d['decision'], 'unknown');
      expect(d['source'], 'none');
    });
  });
}

/// The gh-71 round cap: rounds come from `rework-round-<n>` issue labels
/// (highest n wins). Progression: each bounded verdict bumps the counter.
void roundCapProgressionTests() {
  group('decide: round cap progression', () {
    test('fresh issue: first rework round is allowed', () {
      final d = _decide(
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":1,"important":0,"suggestions":0}}',
      );
      expect(d['decision'], 'rework');
      expect(d['escalate'], 'false');
      expect(d['rounds_done'], '0');
      expect(d['next_round'], '1');
    });

    test('one round done: second rework round is allowed', () {
      final d = _decide(
        issueLabels: 'agent:rework rework-round-1',
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":1,"important":0,"suggestions":0}}',
      );
      expect(d['rounds_done'], '1');
      expect(d['next_round'], '2');
      expect(d['escalate'], 'false');
    });
  });
}

/// Escalation: at (or beyond) the cap a rework verdict escalates to
/// needs-human instead of queueing another automatic round.
void roundCapEscalationTests() {
  group('decide: round cap escalation', () {
    test('two round labels (multi-label history) → escalate', () {
      final d = _decide(
        issueLabels: 'agent:review rework-round-1 rework-round-2',
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":1,"important":0,"suggestions":0}}',
      );
      expect(d['rounds_done'], '2');
      expect(d['escalate'], 'true');
    });

    test('cap reached (rework-round-2 present) → escalate', () {
      final d = _decide(
        issueLabels: 'rework-round-2',
        reviewJson: '{"recommendation":"BLOCK"}',
      );
      expect(d['escalate'], 'true');
      expect(d['next_round'], '2');
    });

    test('round beyond the cap still escalates (defensive)', () {
      final d = _decide(
        issueLabels: 'rework-round-3',
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":1,"important":0,"suggestions":0}}',
      );
      expect(d['escalate'], 'true');
    });

    test('MAX_ROUNDS=1 escalates on the second rework verdict', () {
      final d = _decide(
        issueLabels: 'rework-round-1',
        maxRounds: 1,
        reviewJson: '{"recommendation":"REQUEST_CHANGES","issueCounts":'
            '{"blocking":1,"important":0,"suggestions":0}}',
      );
      expect(d['escalate'], 'true');
    });
  });
}

/// Label bookkeeping around the cap: converged cycles clear the counter and
/// the emitted assignments must survive a real bash `eval`.
void roundCapBookkeepingTests() {
  group('decide: round cap bookkeeping', () {
    test('approve verdict never escalates (cycle converged)', () {
      final d = _decide(
        issueLabels: 'rework-round-2',
        reviewJson: '{"recommendation":"APPROVE"}',
      );
      expect(d['decision'], 'approve');
      expect(d['escalate'], 'false');
    });

    test('round labels are emitted quoted (eval-safe)', () {
      final d = _decide(
        issueLabels: 'rework-round-1 rework-round-2',
        reviewJson: '{"recommendation":"BLOCK"}',
      );
      expect(d['round_labels'], contains('rework-round-1'));
      expect(d['round_labels'], contains('rework-round-2'));
    });

    test('emitted assignments eval cleanly in bash', () {
      final dir = Directory.systemTemp.createTempSync('review_verdict_eval_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final json = File('${dir.path}/pr_review.json')
        ..writeAsStringSync(
          '{"recommendation":"BLOCK"}',
        );
      final inner =
          "PR_REVIEW_JSON='${json.path}' ISSUE_LABELS='rework-round-2' "
          "bash '${_script.absolute.path}' decide";
      final result = Process.runSync(
        'bash',
        ['-c', 'eval "\$($inner)"; printf \'%s\\n\' "\$escalate"'],
        workingDirectory: dir.path,
        environment: {...Platform.environment},
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect((result.stdout as String).trim(), 'true');
    });
  });
}

/// The escalation comment lists unresolved PR review threads — rendered from
/// the GitHub GraphQL reviewThreads payload.
void threadSummaryTests() {
  group('threads: unresolved-thread summary', () {
    const threads = '''
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"isResolved":false,"path":"lib/src/a.dart","line":42,
  "comments":{"nodes":[{"body":"🚨 BLOCKING: null deref here\\nsecond line","author":{"login":"reviewer-1"}}]}},
 {"isResolved":false,"path":"lib/src/b.dart","line":null,
  "comments":{"nodes":[{"body":"💡 reword the doc comment","author":{"login":"reviewer-2"}}]}},
 {"isResolved":true,"path":"lib/src/fixed.dart","line":7,
  "comments":{"nodes":[{"body":"resolved already","author":{"login":"reviewer-3"}}]}}
]}}}}}
''';

    test('renders unresolved threads with path:line, author, first line', () {
      final out = _threads(threads);
      expect(out, contains('`lib/src/a.dart:42`'));
      expect(out, contains('@reviewer-1'));
      expect(out, contains('🚨 BLOCKING: null deref here'));
      expect(out, isNot(contains('second line')));
      expect(out, contains('`lib/src/b.dart:?`'));
      expect(out, contains('@reviewer-2'));
    });

    test('skips resolved threads', () {
      final out = _threads(threads);
      expect(out, isNot(contains('fixed.dart')));
      expect(out, isNot(contains('resolved already')));
    });

    test('renders multiple unresolved threads as separate bullets', () {
      final out = _threads(threads);
      expect(
        out.split('\n').where((l) => l.startsWith('- ')).length,
        2,
      );
    });

    test('missing pullRequest node → empty output', () {
      final out = _threads('{"data":{"repository":{"pullRequest":null}}}');
      expect(out, isEmpty);
    });

    test('empty thread list → empty output', () {
      final out = _threads(
        '{"data":{"repository":{"pullRequest":'
        '{"reviewThreads":{"nodes":[]}}}}}',
      );
      expect(out, isEmpty);
    });
  });
}

/// Contract tests: the bounded verdict's label wiring — the dynamic
/// rework-round-<n> / needs-human labels and the workflow that drives them
/// (gh-71 review threads: labels must exist before --add-label; the queue
/// label must be added before the counter).
void verdictLabelWiringTests() {
  group('machine wiring: bounded-verdict labels', () {
    test('quality job checks out the agents submodule (wiring tests need it)',
        () {
      final yml = File('.github/workflows/quality.yml').readAsStringSync();
      expect(
        yml.split('agents-suite:').first,
        contains('submodules: true'),
        reason: 'the machine-wiring tests resolve the runner parents under '
            'agents/ (a git submodule) — the dart test job must check it '
            'out, or parent-config resolution dies with '
            'PathNotFoundException (observed on CI, gh-71 rework)',
      );
    });

    test('dynamic verdict labels are created before they are added', () {
      final yml =
          File('.github/workflows/ai-teammate-issues.yml').readAsStringSync();
      // gh issue edit --add-label hard-fails on an unknown label ("not
      // found") — and the step runs under bash -e, so a missing label
      // definition would abort the verdict transition mid-way (the loop
      // dies on the very first bounded verdict).
      expect(yml, contains('ensure_label()'));
      for (final label in const ['needs-human', 'rework-round-']) {
        final ensure = yml.indexOf('ensure_label "$label');
        final add = yml.indexOf('--add-label "$label');
        expect(ensure, greaterThanOrEqualTo(0),
            reason: 'no ensure_label call for "$label"');
        expect(add, greaterThan(ensure),
            reason: '"$label" must be created (ensure_label) before it is '
                'passed to --add-label');
      }
    });

    test(
        'agent:rework is labeled before the round counter '
        '(supersession-safe order)', () {
      final yml =
          File('.github/workflows/ai-teammate-issues.yml').readAsStringSync();
      final rework = yml.indexOf('--add-label "agent:rework"');
      final round = yml.indexOf('--add-label "rework-round-');
      expect(rework, greaterThanOrEqualTo(0));
      expect(round, greaterThan(rework),
          reason: 'the round-label event fires while agent:review is still '
              'on the issue ("Close the review cycle" strips it later); the '
              'concurrency group keeps one pending run, so the queue label '
              'must be added first — a superseded pending run then still '
              'resolves to agent:rework even if the round-label add fails');
    });
  });
}

/// Contract tests: the runners + workflow must stay wired to the script and
/// the verdict-rules instruction file.
void wiringTests() {
  group('machine wiring', () {
    test('review runner extends parent prompts with the verdict rules', () {
      final json = jsonDecode(
        const RunCommandProcessor().process([
          'run',
          'machine-kit/teammate-install/runners/fa-review-kimi.json'
        ]),
      ) as Map;
      final params = json['params'] as Map;
      final prompts = (params['cliPrompts'] as List).cast<String>();
      expect(
        prompts,
        contains(
            'machine-kit/teammate-install/instructions/review-verdict-rules.md'),
      );
      // Parent prompts survive the merge.
      expect(prompts,
          contains('./agents/instructions/pr_review/general_guidelines.md'));
      expect(
        (params['customParams'] as Map)['allowApproveWithSuggestions'],
        true,
      );
    });

    test('verdict-rules instruction file exists', () {
      expect(
        File('machine-kit/teammate-install/instructions/review-verdict-rules.md')
            .existsSync(),
        isTrue,
      );
    });

    test('rework runner still resolves against its parent', () {
      final json = jsonDecode(
        const RunCommandProcessor().process(
            ['run', 'machine-kit/teammate-install/runners/fa-rework-zai.json']),
      ) as Map;
      expect(
          (json['params']['envVariables'] as Map)['AI_AGENT_PROVIDER'], 'fa');
    });

    test('workflow invokes the script and defines the cap', () {
      final yml =
          File('.github/workflows/ai-teammate-issues.yml').readAsStringSync();
      expect(yml, contains('review-verdict.sh'));
      expect(yml, contains('MAX_AUTO_REWORK_ROUNDS'));
      expect(yml, contains('needs-human'));
    });
  });
}

final _script = File('machine-kit/teammate-install/scripts/review-verdict.sh');

/// Runs `review-verdict.sh decide` with fixture files in a sandbox dir and
/// returns the emitted `key=value` assignments as a map.
Map<String, String> _decide({
  String? reviewJson,
  String? reviewJsonAlt,
  String? runOutput,
  String issueLabels = '',
  int maxRounds = 2,
  Map<String, String> commentFiles = const {},
}) {
  final dir = Directory.systemTemp.createTempSync('review_verdict_');
  addTearDown(() => dir.deleteSync(recursive: true));
  String write(String name, String content) {
    final f = File('${dir.path}/$name');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f.path;
  }

  final env = <String, String>{...Platform.environment};
  if (reviewJson != null) {
    env['PR_REVIEW_JSON'] = write('pr_review.json', reviewJson);
    for (final entry in commentFiles.entries) {
      write(entry.key, entry.value);
    }
  }
  if (reviewJsonAlt != null) {
    env['PR_REVIEW_JSON_ALT'] = write('gh-57/pr_review.json', reviewJsonAlt);
  }
  if (runOutput != null) {
    env['RUN_OUTPUT'] = write('run-output.txt', runOutput);
  }
  env['ISSUE_LABELS'] = issueLabels;
  env['MAX_ROUNDS'] = '$maxRounds';

  final result = Process.runSync(
    'bash',
    [_script.absolute.path, 'decide'],
    workingDirectory: dir.path,
    environment: env,
  );
  expect(result.exitCode, 0, reason: result.stderr);
  return Map.fromEntries(
    (result.stdout as String).trim().split('\n').map((line) {
      final i = line.indexOf('=');
      return MapEntry(line.substring(0, i), line.substring(i + 1));
    }),
  );
}

/// Runs `review-verdict.sh threads` on a GraphQL response fixture.
String _threads(String graphqlResponse) {
  final dir = Directory.systemTemp.createTempSync('review_threads_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final f = File('${dir.path}/threads.json')
    ..writeAsStringSync(graphqlResponse);
  final result = Process.runSync(
    'bash',
    [_script.absolute.path, 'threads', f.path],
    workingDirectory: dir.path,
    environment: {...Platform.environment},
  );
  expect(result.exitCode, 0, reason: result.stderr);
  return (result.stdout as String).trim();
}
