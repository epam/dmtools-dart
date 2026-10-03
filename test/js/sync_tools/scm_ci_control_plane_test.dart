/// `ci_*` alias dispatch — control-plane translation (gh-339): trigger,
/// run listing, and the semantic verdict / merge-state reads onto the
/// configured provider's concrete tools.
///
/// Provider handlers are injected so every test proves the TRANSLATION;
/// see `scm_ci_sync_tools_test.dart` for the data-plane aliases.
library;

import 'dart:convert';
import 'package:test/test.dart';

import 'scm_ci_sync_tools_fixture.dart';

void main() {
  withScmCiEnv(() {
    ciGithubTriggerTests();
    ciGithubTriggerValidationTests();
    ciGithubListRunsTests();
    ciGithubVerdictTests();
    ciGithubVerdictEdgeTests();
    ciGithubMergeStateTests();
    ciGithubMergeStateAc7Tests();
    ciGitlabTriggerTests();
    ciGitlabTriggerInputTests();
    ciGitlabVerdictTests();
    ciGitlabVerdictRunIdTests();
    ciGitlabMergeStateTests();
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

void ciGithubTriggerValidationTests() {
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

    test('ci_trigger_workflow rejects an unparsable inputs JSON string', () {
      final tools = ghSubject({
        'github_trigger_workflow': (args) =>
            fail('must not reach the provider with invalid inputs'),
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {'workflow': 'ci.yml', 'inputs': '{not json'},
        ),
      );
      expect(out['error'], contains('invalid inputs JSON'));
    });

    test('non-map inputs wrap under the `input` key, stringified', () {
      final tools = ghSubject({
        'github_trigger_workflow': (args) {
          expect(args['inputs'], '{"input":"42"}');
          return '"ok"';
        },
        'github_list_workflow_runs': (args) =>
            '{"workflow_runs":[{"id":7,"head_branch":"main"}]}',
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {'workflow': 'ci.yml', 'inputs': 42},
        ),
      );
      expect(out['runId'], 7);
    });
  });
}

void ciGithubListRunsTests() {
  group('ci_* → github actions (control plane)', () {
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
  });
}

void ciGithubVerdictEdgeTests() {
  group('ci_* → github actions (control plane)', () {
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
  });
}

void ciGithubMergeStateAc7Tests() {
  group('ci_* → github actions (control plane)', () {
    test(
        'sha-probe without check runs and without workflow is none '
        '(no speculative listing)', () {
      final tools = ghSubject({
        'github_get_commit_check_runs': (args) => '{"check_runs": []}',
        'github_list_workflow_runs': (args) =>
            fail('no workflow filter → no fallback listing'),
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'o', 'repository': 'r', 'sha': 'abc'},
        ),
      );
      expect(out['verdict'], 'none');
    });

    test('a runId the routed provider rejects names the mismatch (E3, GH)', () {
      final tools = ghSubject({
        'github_get_workflow_run': (args) =>
            '{"error":"GitHub API 404: Not Found"}',
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'o', 'repository': 'r', 'runId': '77'},
        ),
      );
      expect(out['error'], contains('GitHub API 404'));
      expect(out['error'], contains('different provider'));
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
    test('ci_trigger_workflow rejects an unparsable inputs JSON string', () {
      final tools = glSubject({
        'gitlab_trigger_pipeline': (args) =>
            fail('must not reach the provider with invalid inputs'),
      });
      final out = decode(
        tools.handlers['ci_trigger_workflow']!(
          {'workflow': '.gitlab-ci.yml', 'inputs': '{oops'},
        ),
      );
      expect(out['error'], contains('invalid inputs JSON'));
    });

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
  });
}

void ciGitlabTriggerInputTests() {
  group('ci_* → gitlab ci (control plane)', () {
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

void ciGitlabVerdictRunIdTests() {
  group('ci_* → gitlab ci (control plane)', () {
    test('ci_get_verdict runId-form rolls the job statuses up (multi-job)', () {
      final tools = glSubject({
        'gitlab_get_pipeline_jobs': (args) {
          expect(args['pipelineId'], '123456');
          return jsonEncode({
            'jobs': [
              {'status': 'success'},
              {'status': 'running'},
            ],
          });
        },
      });
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'g', 'repository': 'r', 'runId': '123456'},
        ),
      );
      expect(out['verdict'], 'pending',
          reason: 'success + in-flight is pending, never a silent pass');
      expect(out['provider'], 'gitlab');
    });

    test('ci_get_verdict without runId/pr/sha is a schema error', () {
      final tools = glSubject(const {});
      final out = decode(
        tools.handlers['ci_get_verdict']!(
          {'workspace': 'g', 'repository': 'r'},
        ),
      );
      expect(out['error'], contains('runId'));
      expect(out['error'], contains('pr'));
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
