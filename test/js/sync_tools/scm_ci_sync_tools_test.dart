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

import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/scm_ci_sync_tools.dart';
import 'package:test/test.dart';

typedef Handler = String Function(Map<String, dynamic> args);

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() => PropertyReader.setOverrides(const {}));
  tearDown(PropertyReader.clearOverrides);

  availabilityTests();
  scmGithubTests();
  scmGitlabTests();
  ciGithubTriggerTests();
  ciGithubVerdictTests();
  ciGitlabTriggerTests();
  ciGitlabVerdictTests();
  edgeContractTests();
}

/// Fake provider handlers: a tool missing from the map fails the test —
/// the alias must only call what the translation table declares.
Map<String, Handler> fake(Map<String, Handler> handlers) => handlers;

Map<String, dynamic> decode(String raw) {
  final v = jsonDecode(raw);
  return v is Map<String, dynamic> ? v : {'value': v};
}

/// GitHub-side test subject with a configured scm+ci routing.
ScmCiSyncTools ghSubject(Map<String, Handler> gh, {Map<String, Handler>? gl}) =>
    ScmCiSyncTools(
      scmProvider: 'github',
      ciProvider: 'github',
      githubHandlers: fake(gh),
      gitlabHandlers: fake(gl ?? const {}),
    );

/// GitLab-side test subject.
ScmCiSyncTools glSubject(Map<String, Handler> gl, {Map<String, Handler>? gh}) =>
    ScmCiSyncTools(
      scmProvider: 'gitlab',
      ciProvider: 'gitlab',
      githubHandlers: fake(gh ?? const {}),
      gitlabHandlers: fake(gl),
    );

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

void ciGithubTriggerTests() {
  group('ci_* → github actions (control plane)', () {
    test('ci_trigger_workflow stringifies the inputs map (pinned fact)', () {
      final tools = ghSubject({
        'github_trigger_workflow': (args) {
          expect(args['workflowId'], 'ci.yml');
          expect(args['ref'], 'main');
          final inputs =
              jsonDecode(args['inputs'] as String) as Map<String, dynamic>;
          expect(inputs['issue'], '17');
          expect(inputs['count'], '3',
              reason: 'non-string values are stringified at the boundary');
          return '"triggered"';
        },
        'github_list_workflow_runs': (args) {
          expect(args['workflowId'], 'ci.yml');
          return jsonEncode({
            'workflow_runs': [
              {'id': 991, 'head_branch': 'main'},
              {'id': 990, 'head_branch': 'other'},
            ],
          });
        },
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {
            'workflow': 'ci.yml',
            'ref': 'main',
            'inputs': {'issue': 17, 'count': 3}
          },
        ),
      );
      expect(out['runId'], 991);
    });

    test('ci_trigger_workflow accepts a JSON-string inputs payload', () {
      final tools = ghSubject({
        'github_trigger_workflow': (args) {
          expect(args['inputs'], '{"leg":"dev"}');
          return '"ok"';
        },
        'github_list_workflow_runs': (args) => '{"workflow_runs": []}',
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {'workflow': 'w.yml', 'inputs': '{"leg":"dev"}'},
        ),
      );
      expect(out['runId'], isNull,
          reason: 'no matching run — the handle is honestly null');
    });
  });
}

void ciGithubListRunsTests() {
  group('ci_* → github actions (control plane)', () {
    test('ci_trigger_workflow returns the trigger error untouched', () {
      final tools = ghSubject({
        'github_trigger_workflow': (args) => '{"error":"Workflow trigger '
            'failed for \'ci.yml\' (422): bad"}',
        'github_list_workflow_runs': (args) =>
            fail('no run lookup after a failed trigger'),
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {'workflow': 'ci.yml'},
        ),
      );
      expect(out['error'], contains('422'));
    });

    test('ci_list_runs normalizes run fields and pins the verdict enum', () {
      final tools = ghSubject({
        'github_list_workflow_runs': (args) {
          expect(args['workflowId'], 'ci.yml');
          expect(args['status'], 'completed');
          return jsonEncode({
            'workflow_runs': [
              {
                'id': 1,
                'status': 'completed',
                'conclusion': 'success',
                'head_sha': 'abc',
                'html_url': 'u1',
                'created_at': '2026-01-01T00:00:00Z',
                'event': 'workflow_dispatch',
                'path': '.github/workflows/ci.yml',
                'name': 'ci',
              },
              {
                'id': 2,
                'status': 'in_progress',
                'conclusion': null,
                'head_sha': 'def',
                'html_url': 'u2',
                'created_at': '2026-01-02T00:00:00Z',
                'event': 'push',
                'path': '.github/workflows/ci.yml',
                'name': 'ci',
              },
            ],
          });
        },
      });
      final out = decode(
        tools.handlers['ci_list_runs']!(
          {
            'workspace': 'o',
            'repository': 'r',
            'workflow': 'ci.yml',
            'status': 'completed'
          },
        ),
      );
      final runs = out['runs'] as List;
      expect(runs, hasLength(2));
      expect(runs[0]['runId'], 1);
      expect(runs[0]['status'], 'completed');
      expect(runs[0]['verdict'], 'pass');
      expect(runs[0]['sha'], 'abc');
      expect(runs[0]['url'], 'u1');
      expect(runs[0]['event'], 'workflow_dispatch');
      expect(runs[1]['verdict'], 'pending');
    });
  });
}

void ciGithubVerdictTests() {
  group('ci_* → github actions (control plane)', () {
    test('ci_get_verdict by runId reads the run conclusion', () {
      final tools = ghSubject({
        'github_get_workflow_run': (args) {
          expect(args['runId'], '77');
          return jsonEncode({
            'id': 77,
            'status': 'completed',
            'conclusion': 'failure',
          });
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'o', 'repository': 'r', 'runId': '77'},
        ),
      );
      expect(out['verdict'], 'fail');
      expect(out['provider'], 'github');
    });

    test('ci_get_verdict sha-probe rolls up check runs', () {
      final tools = ghSubject({
        'github_get_commit_check_runs': (args) {
          expect(args['commitSha'], 'abc');
          return jsonEncode({
            'check_runs': [
              {'conclusion': 'success'},
              {'conclusion': 'success'},
            ],
          });
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'o', 'repository': 'r', 'sha': 'abc'},
        ),
      );
      expect(out['verdict'], 'pass');
    });

    test(
        'ci_get_verdict sha-probe falls back to workflow runs matched on '
        'head_sha (the stale-verdict probe)', () {
      final tools = ghSubject({
        'github_get_commit_check_runs': (args) => '{"check_runs": []}',
        'github_list_workflow_runs': (args) {
          expect(args['workflowId'], 'ci.yml');
          return jsonEncode({
            'workflow_runs': [
              {
                'id': 5,
                'head_sha': 'other',
                'status': 'completed',
                'conclusion': 'success',
              },
              {
                'id': 6,
                'head_sha': 'abc',
                'status': 'completed',
                'conclusion': 'failure',
              },
            ],
          });
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {
            'workspace': 'o',
            'repository': 'r',
            'sha': 'abc',
            'workflow': 'ci.yml'
          },
        ),
      );
      expect(out['verdict'], 'fail');
    });
  });
}

void ciGithubMergeStateTests() {
  group('ci_* → github actions (control plane)', () {
    test('ci_get_verdict with no evidence at all is none', () {
      final tools = ghSubject({
        'github_get_commit_check_runs': (args) => '{"check_runs": []}',
        'github_list_workflow_runs': (args) => '{"workflow_runs": []}',
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {
            'workspace': 'o',
            'repository': 'r',
            'sha': 'abc',
            'workflow': 'ci.yml'
          },
        ),
      );
      expect(out['verdict'], 'none');
    });

    test('ci_get_verdict without runId or sha is a schema error (E-negative)',
        () {
      final tools = ghSubject(const {});
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'o', 'repository': 'r'},
        ),
      );
      expect(out['error'], contains('runId'));
      expect(out['error'], contains('sha'));
    });

    test('ci_get_merge_state normalizes the REST body (AC7)', () {
      final tools = ghSubject({
        'github_get_pr': (args) {
          expect(args['pullRequestId'], 12);
          return jsonEncode({
            'number': 12,
            'mergeable': true,
            'mergeable_state': 'blocked',
          });
        },
      });
      final out = decode(
        tools.handlers['ci_get_merge_state']!(
          {'workspace': 'o', 'repository': 'r', 'pr': 12},
        ),
      );
      expect(out['mergeState'], 'BLOCKED');
      expect(out['reason'], 'required-checks-pending');
    });
  });
}

void ciGitlabTriggerTests() {
  group('ci_* → gitlab ci (control plane)', () {
    test('ci_trigger_workflow triggers a pipeline with variables', () {
      final tools = glSubject({
        'gitlab_trigger_pipeline': (args) {
          expect(args['ref'], 'main');
          final vars = jsonDecode(args['variablesJson'] as String) as Map;
          expect(vars['issue'], '17');
          return jsonEncode({'id': 551, 'status': 'pending'});
        },
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {
            'workflow': 'ignored.yml',
            'ref': 'main',
            'inputs': {'issue': 17}
          },
        ),
      );
      expect(out['runId'], 551);
    });

    test('ci_list_runs normalizes pipeline payloads', () {
      final tools = glSubject({
        'gitlab_list_pipeline_runs': (args) {
          expect(args['ref'], 'main');
          return jsonEncode([
            {
              'id': 9,
              'status': 'success',
              'sha': 'abc',
              'web_url': 'u9',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]);
        },
      });
      final out = decode(
        tools.handlers['ci_list_runs']!(
          {'workspace': 'g', 'repository': 'r', 'ref': 'main'},
        ),
      );
      final runs = out['runs'] as List;
      expect(runs.single['runId'], 9);
      expect(runs.single['verdict'], 'pass');
    });
  });
}

void ciGitlabVerdictTests() {
  group('ci_* → gitlab ci (control plane)', () {
    test('ci_get_verdict pr-probe rolls MR pipelines up to the enum', () {
      final tools = glSubject({
        'gitlab_get_mr_pipelines': (args) {
          expect(args['pullRequestId'], '4');
          return jsonEncode([
            {'status': 'success'},
            {'status': 'running'},
          ]);
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'g', 'repository': 'r', 'pr': 4},
        ),
      );
      expect(out['verdict'], 'pending');
      expect(out['provider'], 'gitlab');
    });

    test(
        'ci_get_verdict runId-form reads pipeline jobs and names the '
        'provider on not-found (E3)', () {
      final tools = glSubject({
        'gitlab_get_pipeline_jobs': (args) {
          expect(args['pipelineId'], '123456');
          return '{"error":"GitLab API 404: Not Found"}';
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'g', 'repository': 'r', 'runId': '123456'},
        ),
      );
      expect(out['error'], contains('GitLab'));
      expect(out['error'], contains('different provider'));
    });
  });
}

void ciGitlabMergeStateTests() {
  group('ci_* → gitlab ci (control plane)', () {
    test('ci_get_verdict sha-probe reads commit statuses', () {
      final tools = glSubject({
        'gitlab_get_commit_statuses': (args) {
          expect(args['commitSha'], 'abc');
          return jsonEncode([
            {'status': 'success'},
            {'status': 'success'},
          ]);
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'g', 'repository': 'r', 'sha': 'abc'},
        ),
      );
      expect(out['verdict'], 'pass');
    });

    test('ci_get_merge_state maps the GL MR body (AC7 transient)', () {
      final tools = glSubject({
        'gitlab_get_mr': (args) {
          return jsonEncode({
            'iid': 4,
            'merge_status': 'can_be_merged',
            'detailed_merge_status': 'ci_still_running',
            'has_conflicts': false,
          });
        },
      });
      final out = decode(
        tools.handlers['ci_get_merge_state']!(
          {'workspace': 'g', 'repository': 'r', 'pr': 4},
        ),
      );
      expect(out['mergeState'], 'BLOCKED');
      expect(out['reason'], 'ci-still-running');
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
