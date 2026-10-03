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
import 'package:dmtools/src/js/sync_tools/scm_ci_sync_tools.dart';
import 'package:test/test.dart';

import 'scm_ci_sync_tools_fixture.dart';

void main() {
  withScmCiEnv(() {
    availabilityTests();
    scmGithubTests();
    scmGitlabTests();
    edgeContractTests();
  });
}

/// AC1/E-negative: without DEFAULT_SCM/DEFAULT_CI the surface is empty.
void availabilityTests() {
  group('availability at dispatch', () {
    test('no env → no handlers (tool-not-found territory)', () {
      final tools = ScmCiSyncTools();
      expect(tools.handlers, isEmpty);
    });

    test('DEFAULT_SCM=github env resolves the scm handlers once', () {
      PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
      final tools = ScmCiSyncTools();
      expect(tools.handlers.keys, contains('scm_get_pr'));
      expect(tools.handlers.keys.any((k) => k.startsWith('ci_')), isFalse);
    });

    test('routing never changes mid-process (env flip after first read)', () {
      PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
      final tools = ScmCiSyncTools();
      expect(tools.handlers.keys, contains('scm_get_pr'));
      PropertyReader.setOverrides({'DEFAULT_SCM': 'gitlab'});
      expect(tools.handlers.keys, contains('scm_get_pr'),
          reason: 'routing is frozen at first resolution');
    });

    test(
        'the dispatcher-level handlers include both families when both '
        'axes are configured', () {
      final tools = ghSubject(const {}, gl: const {});
      expect(
        tools.handlers.keys,
        containsAll(['scm_get_pr', 'ci_get_verdict']),
      );
    });
  });
}

void scmGithubTests() {
  group('scm_* → github (data plane)', () {
    test(
        'scm_get_pr maps pr→pullRequestId and returns the provider body '
        'byte-identical', () {
      const body = '{"number":42,"state":"open","mergeable_state":"clean"}';
      final tools = ghSubject({
        'github_get_pr': (args) {
          expect(args['pullRequestId'], 42);
          expect(args['workspace'], 'o');
          expect(args['repository'], 'r');
          return body;
        },
      });
      expect(
        tools.handlers['scm_get_pr']!(
          {'workspace': 'o', 'repository': 'r', 'pr': 42},
        ),
        body,
      );
    });

    test('scm_list_prs passes the normalized state through', () {
      final tools = ghSubject({
        'github_list_prs': (args) {
          expect(args['state'], 'open');
          return '[]';
        },
      });
      tools.handlers['scm_list_prs']!(
        {'workspace': 'o', 'repository': 'r', 'state': 'open'},
      );
    });

    test('scm_merge_pr maps pr and keeps mergeMethod', () {
      final tools = ghSubject({
        'github_merge_pr': (args) {
          expect(args['pullRequestId'], 7);
          expect(args['mergeMethod'], 'squash');
          return '{"merged":true}';
        },
      });
      tools.handlers['scm_merge_pr']!(
        {'workspace': 'o', 'repository': 'r', 'pr': 7, 'mergeMethod': 'squash'},
      );
    });

    test('scm_get_diff routes to the raw unified-diff tool', () {
      final tools = ghSubject({
        'github_get_pr_diff_text': (args) {
          expect(args['pullRequestId'], 7);
          return 'diff --git a/x b/x';
        },
      });
      expect(
        tools.handlers['scm_get_diff']!(
          {'workspace': 'o', 'repository': 'r', 'pr': 7},
        ),
        'diff --git a/x b/x',
      );
    });
  });
}

void scmGithubBranchTests() {
  group('scm_* → github (data plane)', () {
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
      final tools = ghSubject({
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
      });
      final h = tools.handlers;
      h['scm_get_issue']!({'workspace': 'o', 'repository': 'r', 'issue': 5});
      h['scm_create_comment']!(
        {'workspace': 'o', 'repository': 'r', 'issue': 5, 'body': 'hi'},
      );
      h['scm_close_issue']!(
        {'workspace': 'o', 'repository': 'r', 'issue': 5},
      );
      h['scm_search_issues']!(
        {
          'workspace': 'o',
          'repository': 'r',
          'query': 'repo:o/r is:issue is:open'
        },
      );
      h['scm_list_branches']!({'workspace': 'o', 'repository': 'r'});
      h['scm_get_reviews']!({'workspace': 'o', 'repository': 'r', 'pr': 5});
      h['scm_remove_label']!(
        {
          'workspace': 'o',
          'repository': 'r',
          'pr': 5,
          'label': 'ai_validating'
        },
      );
      h['scm_add_pr_comment']!(
        {'workspace': 'o', 'repository': 'r', 'pr': 5, 'text': 'note'},
      );
      h['scm_get_pr_comments']!({'workspace': 'o', 'repository': 'r', 'pr': 5});
    });
  });
}

void scmGitlabTests() {
  group('scm_* → gitlab (data plane)', () {
    test('scm_list_prs maps the state enum onto GitLab spellings', () {
      final states = <String?>[];
      final tools = glSubject({
        'gitlab_list_mrs': (args) {
          states.add(args['state'] as String?);
          return '[]';
        },
      });
      final h = tools.handlers;
      h['scm_list_prs']!(
          {'workspace': 'g', 'repository': 'r', 'state': 'open'});
      h['scm_list_prs']!(
        {'workspace': 'g', 'repository': 'r', 'state': 'merged'},
      );
      h['scm_list_prs']!({'workspace': 'g', 'repository': 'r', 'state': 'all'});
      expect(states, ['opened', 'merged', 'all']);
    });

    test('scm_get_pr maps pr→pullRequestId', () {
      final tools = glSubject({
        'gitlab_get_mr': (args) {
          expect(args['pullRequestId'], '42');
          return '{"iid":42}';
        },
      });
      tools.handlers['scm_get_pr']!(
        {'workspace': 'g', 'repository': 'r', 'pr': 42},
      );
    });
  });
}

void scmGitlabBranchTests() {
  group('scm_* → gitlab (data plane)', () {
    test('scm_add_labels fans out per label (multi-item loop)', () {
      final added = <String>[];
      final tools = glSubject({
        'gitlab_add_mr_label': (args) {
          added.add(args['label'] as String);
          return '{}';
        },
      });
      tools.handlers['scm_add_labels']!(
        {
          'workspace': 'g',
          'repository': 'r',
          'pr': 3,
          'labels': ['a', 'b', 'c']
        },
      );
      expect(added, ['a', 'b', 'c']);
    });

    test('scm_approve routes to the approvals API', () {
      final tools = glSubject({
        'gitlab_approve_mr': (args) {
          expect(args['pullRequestId'], '3');
          return '{}';
        },
      });
      tools.handlers['scm_approve']!(
        {'workspace': 'g', 'repository': 'r', 'pr': 3},
      );
    });

    test('scm_search_issues is an honest v1 gap on GitLab', () {
      final tools = glSubject(const {});
      final out = tools.handlers['scm_search_issues']!(
        {'workspace': 'g', 'repository': 'r', 'query': 'x'},
      );
      expect(decode(out)['error'], contains('GitLab'));
      expect(decode(out)['error'], contains('not available'));
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
      // error surfaces through the alias unchanged.
      PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
      final tools = ScmCiSyncTools(scmProvider: 'github');
      final out = decode(tools.handlers['scm_get_pr']!(
        {'workspace': 'o', 'repository': 'r', 'pr': 1},
      ));
      expect(out['error'], 'GitHub not configured');
    });

    test(
        'E2: a GitHub-shaped raw state is rejected — the normalized enum '
        'is the only accepted shape', () {
      final tools = ghSubject({
        'github_list_prs': (args) =>
            fail('must reject before reaching the provider'),
      });
      final out = decode(
        tools.handlers['scm_list_prs']!(
          {'workspace': 'o', 'repository': 'r', 'state': 'OPEN AND DECLINED'},
        ),
      );
      expect(out['error'], contains('open, closed, merged, all'));
    });

    test('E2 (positive): the enum accepts case-insensitive valid values', () {
      final tools = ghSubject({
        'github_list_prs': (args) {
          expect(args['state'], 'open');
          return '[]';
        },
      });
      tools.handlers['scm_list_prs']!(
        {'workspace': 'o', 'repository': 'r', 'state': 'OPEN'},
      );
    });

    test('an unrouted provider leaves its family unregistered', () {
      final tools = ScmCiSyncTools(
        scmProvider: 'github',
        githubHandlers: fake(const {}),
      );
      expect(tools.handlers.keys, contains('scm_get_pr'));
      expect(tools.handlers.keys.any((k) => k.startsWith('ci_')), isFalse);
    });
  });
}
