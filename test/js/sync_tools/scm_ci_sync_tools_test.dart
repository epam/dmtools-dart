/// `ScmCiSyncTools` — dispatch-time translation of the normalized
/// `scm_*`/`ci_*` calls onto the configured provider's concrete tools
/// (gh-339).
///
/// Provider handlers are injected so every test proves the TRANSLATION
/// (arg mapping, response normalization, error contracts) without
/// network. The concrete tools' own suites pin their wire behavior; the
/// data-plane aliases must return the concrete response byte-identical
/// (the IT contract-fixture requirement).
library;

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/scm_ci_sync_tools.dart' hide Handler;
import 'package:test/test.dart';

import 'scm_ci_sync_tools_fixture.dart';

void main() {
  withScmCiEnv(() {
    availabilityTests();
    scmGithubTests();
    scmGithubStateTests();
    scmGithubLabelTests();
    scmGitlabTests();
    scmGitlabBranchTests();
    scmGitlabCarrierTests();
    edgeContractTests();
  });
}

/// AC1/E-negative: without DEFAULT_SCM/DEFAULT_CI the surface is empty.
void availabilityTests() {
  group('availability at dispatch', () {
    test('no DEFAULT_SCM/DEFAULT_CI → empty handler map', () {
      final tools = ScmCiSyncTools();
      expect(tools.handlers, isEmpty);
    });

    test('DEFAULT_SCM env override routes the scm family only', () {
      PropertyReader.setOverrides(const {'DEFAULT_SCM': 'github'});
      final tools = ScmCiSyncTools();
      expect(tools.handlers.keys, everyElement(startsWith('scm_')));
      expect(tools.handlers, contains('scm_get_pr'));
      expect(tools.handlers, isNot(contains('ci_get_verdict')));
    });

    test('DEFAULT_CI env override routes the ci family only', () {
      PropertyReader.setOverrides(const {'DEFAULT_CI': 'actions'});
      final tools = ScmCiSyncTools();
      expect(tools.handlers.keys, everyElement(startsWith('ci_')));
    });

    test('routing freezes on first touch — never changes mid-process', () {
      final tools = ScmCiSyncTools();
      expect(tools.handlers, isEmpty);
      PropertyReader.setOverrides(const {'DEFAULT_SCM': 'github'});
      expect(tools.handlers, isEmpty,
          reason: 'late-final routing was already resolved');
    });
  });
}

void scmGithubTests() {
  group('scm_* → github (data plane)', () {
    test('scm_get_pr maps `pr` to pullRequestId and passes through', () {
      final tools = ghSubject({
        'github_get_pr': (args) {
          expect(args['pullRequestId'], 9);
          expect(args['workspace'], 'o');
          expect(args['repository'], 'r');
          return '{"number":9,"state":"open"}';
        },
      });
      final out = tools.handlers['scm_get_pr']!(
          {'workspace': 'o', 'repository': 'r', 'pr': 9});
      expect(decode(out), {'number': 9, 'state': 'open'},
          reason: 'provider response returns byte-identical');
    });

    test('scm_merge_pr carries the optional merge overrides', () {
      final tools = ghSubject({
        'github_merge_pr': (args) {
          expect(args['pullRequestId'], 9);
          expect(args['mergeMethod'], 'squash');
          expect(args['commitTitle'], 't');
          expect(args['commitMessage'], 'm');
          return '{"merged":true}';
        },
      });
      final out = tools.handlers['scm_merge_pr']!(
        {
          'workspace': 'o',
          'repository': 'r',
          'pr': 9,
          'mergeMethod': 'squash',
          'commitTitle': 't',
          'commitMessage': 'm',
        },
      );
      expect(decode(out)['merged'], isTrue);
    });

    test('scm_get_diff maps to the diff-text tool with pullRequestId', () {
      final tools = ghSubject({
        'github_get_pr_diff_text': (args) {
          expect(args['pullRequestId'], 9);
          return '"diff --git a/x b/x"';
        },
      });
      final out = decode(
        tools.handlers['scm_get_diff']!(
          {'workspace': 'o', 'repository': 'r', 'pr': 9},
        ),
      );
      expect(out, 'diff --git a/x b/x');
    });
  });
}

void scmGithubStateTests() {
  group('scm_* → github (data plane)', () {
    test('scm_list_prs validates the normalized state enum (E2)', () {
      final tools = ghSubject({
        'github_list_prs': (args) {
          expect(args['state'], 'open');
          return '[]';
        },
      });
      final h = tools.handlers;
      expect(decode(h['scm_list_prs']!({'workspace': 'o', 'repository': 'r'})),
          {'value': isEmpty},
          reason: 'state defaults to open');
      expect(
          decode(h['scm_list_prs']!(
              {'workspace': 'o', 'repository': 'r', 'state': 'OPEN'})),
          {'value': isEmpty},
          reason: 'case-insensitive enum');
      final bad = h['scm_list_prs']!(
          {'workspace': 'o', 'repository': 'r', 'state': 'OPENED'});
      expect(decode(bad)['error'], contains('open, closed, merged, all'));
      expect(decode(bad)['error'], contains("got 'opened'"));
    });
  });
}

void scmGithubLabelTests() {
  group('scm_* → github (data plane) — labels & approve', () {
    test('scm_add_labels passes the plain-string label array', () {
      final tools = ghSubject({
        'github_add_labels': (args) {
          expect(args['number'], 9);
          expect(args['labels'], ['ai_developed', 'agent:dev']);
          return '[]';
        },
      });
      tools.handlers['scm_add_labels']!(
        {
          'workspace': 'o',
          'repository': 'r',
          'pr': 9,
          'labels': ['ai_developed', 'agent:dev']
        },
      );
    });

    test('scm_approve submits an APPROVE review with optional body', () {
      final tools = ghSubject({
        'github_submit_pr_review': (args) {
          expect(args['pullRequestId'], 9);
          expect(args['event'], 'APPROVE');
          expect(args['body'], 'lgtm');
          return '{}';
        },
      });
      tools.handlers['scm_approve']!(
        {'workspace': 'o', 'repository': 'r', 'pr': 9, 'body': 'lgtm'},
      );
    });

    test('issue-carrier aliases map the neutral issue/pr names', () {
      final tools = ghSubject(_issueCarrierHandlers());
      final h = tools.handlers;
      const issue = {'workspace': 'o', 'repository': 'r', 'issue': 5};
      h['scm_get_issue']!(issue);
      h['scm_create_comment']!({...issue, 'body': 'hi'});
      h['scm_close_issue']!(issue);
      h['scm_search_issues']!({...issue, 'query': 'repo:o/r is:issue is:open'});
      const pr = {'workspace': 'o', 'repository': 'r', 'pr': 5};
      h['scm_list_branches']!({'workspace': 'o', 'repository': 'r'});
      h['scm_get_reviews']!(pr);
      h['scm_remove_label']!({...pr, 'label': 'ai_validating'});
      h['scm_add_pr_comment']!({...pr, 'text': 'note'});
      final out = h['scm_get_pr_comments']!(pr);
      expect(decode(out), {'value': []},
          reason: 'every alias rides its pinned concrete call');
    });
  });
}

void scmGitlabTests() {
  group('scm_* → gitlab (data plane)', () {
    test('scm_list_prs maps the state enum and stringifies the MR id', () {
      final tools = glSubject({
        'gitlab_list_mrs': (args) {
          expect(args['state'], 'opened');
          expect(args['pullRequestId'], isNull);
          return '[]';
        },
        'gitlab_get_mr': (args) {
          expect(args['pullRequestId'], '12',
              reason: 'GL MR ids stringify at the alias boundary');
          return '{"iid":12}';
        },
      });
      final h = tools.handlers;
      expect(decode(h['scm_list_prs']!({'workspace': 'g', 'repository': 'r'})),
          {'value': []});
      expect(
        decode(h['scm_get_pr']!(
          {'workspace': 'g', 'repository': 'r', 'pr': 12},
        ))['iid'],
        12,
      );
    });

    test('scm_add_labels fans out per label and stops on error', () {
      final calls = <String>[];
      final tools = glSubject({
        'gitlab_add_mr_label': (args) {
          calls.add(args['label'] as String);
          expect(args['pullRequestId'], '9');
          return calls.length == 2
              ? '{"error":"GitLab API 400: bad label"}'
              : '[]';
        },
      });
      final out = tools.handlers['scm_add_labels']!(
        {
          'workspace': 'g',
          'repository': 'r',
          'pr': 9,
          'labels': ['ai_developed', 'agent:dev', 'triage']
        },
      );
      expect(calls, ['ai_developed', 'agent:dev'],
          reason: 'one call per label, fan-out stops at the first error');
      expect(decode(out)['error'], contains('bad label'));
    });
  });
}

void scmGitlabBranchTests() {
  group('scm_* → gitlab (data plane) — carrier tools & gaps', () {
    test('scm_add_labels with an empty array is a schema error', () {
      final tools = glSubject(const {});
      final out = tools.handlers['scm_add_labels']!(
        {'workspace': 'g', 'repository': 'r', 'pr': 9, 'labels': <String>[]},
      );
      expect(decode(out)['error'], contains('non-empty labels array'));
    });
  });
}

void scmGitlabCarrierTests() {
  group('scm_* → gitlab (data plane) — carrier tools & gaps', () {
    test('issue-carrier aliases ride the MR-note shape; gaps error', () {
      final tools = glSubject({
        'gitlab_get_mr_diff_text': (args) {
          expect(args['pullRequestId'], '5');
          return '"diff"';
        },
        'gitlab_remove_mr_label': (args) {
          expect(args['label'], 'ai_validating');
          return '[]';
        },
        'gitlab_add_mr_comment': (args) {
          expect(args['text'], 'note');
          return '{}';
        },
        'gitlab_get_mr_comments': (args) {
          expect(args['pullRequestId'], '5');
          return '[]';
        },
        'gitlab_create_mr_note': (args) {
          expect(args['pullRequestId'], '5');
          expect(args['text'], 'hi');
          return '{}';
        },
        'gitlab_approve_mr': (args) {
          expect(args['pullRequestId'], '5');
          return '{}';
        },
        'gitlab_merge_mr': (args) {
          expect(args['pullRequestId'], '5');
          return '{"merged":true}';
        },
      });
      const repo = {'workspace': 'g', 'repository': 'r'};
      final h = tools.handlers;
      expect(decode(h['scm_get_diff']!({...repo, 'pr': 5})), {'value': 'diff'});
      h['scm_remove_label']!({...repo, 'pr': 5, 'label': 'ai_validating'});
      h['scm_add_pr_comment']!({...repo, 'pr': 5, 'text': 'note'});
      h['scm_get_pr_comments']!({...repo, 'pr': 5});
      h['scm_create_comment']!({...repo, 'issue': 5, 'body': 'hi'});
      h['scm_approve']!({...repo, 'pr': 5});
      expect(decode(h['scm_merge_pr']!({...repo, 'pr': 5}))['merged'], isTrue);
    });

    test('v1 gaps name the tool honestly (documented degradation)', () {
      final tools = glSubject(const {});
      const repo = {'workspace': 'g', 'repository': 'r'};
      final h = tools.handlers;
      for (final alias in ['scm_get_issue', 'scm_search_issues']) {
        final out = h[alias]!({...repo, 'issue': 5, 'query': 'q'});
        expect(decode(out)['error'], contains(alias), reason: alias);
        expect(decode(out)['error'], contains('GitLab'));
      }
      for (final alias in ['scm_list_branches', 'scm_get_reviews']) {
        final out = h[alias]!({...repo, 'pr': 5});
        expect(decode(out)['error'], contains(alias), reason: alias);
      }
      final closed = h['scm_close_issue']!({...repo, 'issue': 5});
      expect(decode(closed)['error'], contains('scm_close_issue'));
    });
  });
}

/// Edge contracts from the ticket's test plan.
void edgeContractTests() {
  group('edge contracts', () {
    test(
        'E1: provider env set but creds missing → alias present, provider '
        'auth error (not tool-not-found)', () {
      // Real provider handlers, empty overrides → the concrete config
      // reader finds no token.
      PropertyReader.setOverrides(const {'DEFAULT_SCM': 'github'});
      final tools = ScmCiSyncTools();
      final out = tools.handlers['scm_get_pr']!(
          {'workspace': 'o', 'repository': 'r', 'pr': 1});
      expect(decode(out)['error'], contains('not configured'));
    });

    test(
        'E3: runId from provider A on a B-routed provider names the '
        'mismatch', () {
      final tools = glSubject({
        'gitlab_get_pipeline_jobs': (args) {
          expect(args['pipelineId'], '77');
          return '{"error":"GitLab API 404: Not Found"}';
        },
      });
      final out = tools.handlers['ci_get_verdict']!({'runId': '77'});
      expect(decode(out)['error'], contains('GitLab API 404'));
      expect(decode(out)['error'], contains('different provider'));
    });

    test('ci_get_verdict without any selector is a schema error', () {
      final tools = ghSubject(const {});
      final out = tools.handlers['ci_get_verdict']!(const {});
      expect(decode(out)['error'], contains('runId'));
    });
  });
}

/// Fake GitHub handlers for every issue-carrier/branch/review alias —
/// each one pins the concrete tool + arg names the translation targets.
Map<String, Handler> _issueCarrierHandlers() => {
      'github_get_issue': (args) {
        expect(args['issueNumber'], 5);
        return '{"number":5}';
      },
      'github_create_comment': (args) {
        expect(args['number'], 5);
        expect(args['body'], 'hi');
        return '{}';
      },
      'github_close_issue': (args) {
        expect(args['number'], 5);
        return '{}';
      },
      'github_search_issues': (args) {
        expect(args['query'], 'repo:o/r is:issue is:open');
        return '[]';
      },
      'github_list_branches': (args) {
        expect(args['workspace'], 'o');
        return '[]';
      },
      'github_list_pr_reviews': (args) {
        expect(args['pullRequestId'], 5);
        return '[]';
      },
      'github_remove_label': (args) {
        expect(args['number'], 5);
        expect(args['label'], 'ai_validating');
        return '[]';
      },
      'github_add_pr_comment': (args) {
        expect(args['pullRequestId'], 5);
        expect(args['text'], 'note');
        return '{}';
      },
      'github_get_pr_comments': (args) {
        expect(args['pullRequestId'], 5);
        return '[]';
      },
    };
