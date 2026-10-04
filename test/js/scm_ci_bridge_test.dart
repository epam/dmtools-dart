/// Bridge-level routing for the `scm_*`/`ci_*` aliases (gh-339).
///
/// The JS-visible path is `executeToolViaJava('scm_get_pr', …)` →
/// [ToolBridge.execute] → registry → [dispatcher]: with `DEFAULT_SCM`
/// configured the alias dispatches to the provider's concrete handler,
/// and an unconfigured provider degrades to the same unknown-tool
/// envelope the tracker aliases produce (the documented degradation).
///
/// The guarded-handler tests here are the drift guard for the whole
/// control plane: the `ScmCiSyncTools` suites inject fake handler maps
/// that bypass `syncGuardRequired`, so only the REAL registry + handler
/// maps below can catch a schema/translation that dies in the guard or
/// dispatches to a concrete tool that does not exist.
library;

import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/tool_bridge.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  test(
      'DEFAULT_SCM=github: scm_get_pr dispatches through the provider '
      'handler (E1: present alias, provider auth error on missing creds)', () {
    PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute(
        'scm_get_pr',
        {'workspace': 'o', 'repository': 'r', 'pr': 1},
      ),
    ) as Map<String, dynamic>;
    expect(result['error'], 'GitHub not configured',
        reason: 'the alias is registered and routed — the concrete '
            'provider reports its own config error');
  });

  test('without DEFAULT_SCM the alias is unknown (tool-not-found shape)', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute(
        'scm_get_pr',
        {'workspace': 'o', 'repository': 'r', 'pr': 1},
      ),
    ) as Map<String, dynamic>;
    expect(result['error'], 'Unknown tool: scm_get_pr');
  });

  test('DEFAULT_CI unset: ci_* is unknown even when DEFAULT_SCM is set', () {
    PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute('ci_get_verdict', {'workspace': 'o', 'repository': 'r'}),
    ) as Map<String, dynamic>;
    expect(result['error'], 'Unknown tool: ci_get_verdict');
  });

  additiveOnlyTests();
  guardedTriggerSchemaTests();
  gitlabRunIdGapTests();
  gitlabEnvelopeSmokeTests();
  githubEnvelopeSmokeTests();
}

/// The alias must not die in the required-param guard: the schema
/// declares `workspace`/`repository`, so a schema-following caller sends
/// them and reaches the provider layer (gh-339 review, BLOCKING — the
/// fake-handler suites cannot see this, they bypass syncGuardRequired).
void guardedTriggerSchemaTests() {
  test(
      'ci_trigger_workflow accepts its own declared schema through the '
      'REAL guarded handlers (not a required-param rejection)', () {
    PropertyReader.setOverrides({
      'DEFAULT_SCM': 'github',
      'DEFAULT_CI': 'actions',
    });
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute('ci_trigger_workflow', {
        'workspace': 'o',
        'repository': 'r',
        'workflow': 'ci.yml',
        'ref': 'main',
      }),
    ) as Map<String, dynamic>;
    expect(
      result['error'],
      isNot(contains('Required parameter')),
      reason: 'the schema declares workspace/repository — a '
          'schema-following caller must reach the provider layer',
    );
    expect(
      result['error'],
      'GitHub not configured',
      reason: 'E1: with the guard passed, the provider reports its own '
          'config error',
    );
  });
}

/// `gitlab_get_pipeline_jobs` has no real handler (Java-parity gap) — the
/// runId form must degrade to the documented gap error, never a
/// null-check crash. Only the real handler map can prove this: the
/// injected fakes happen to contain the tool.
void gitlabRunIdGapTests() {
  test(
      'DEFAULT_CI=gitlab-ci: ci_get_verdict(runId) through the REAL '
      'handlers names the missing concrete tool (not a null crash)', () {
    PropertyReader.setOverrides({'DEFAULT_CI': 'gitlab-ci'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute('ci_get_verdict', {
        'workspace': 'g',
        'repository': 'r',
        'runId': '42',
      }),
    ) as Map<String, dynamic>;
    expect(
      result['error'],
      contains('gitlab_get_pipeline_jobs'),
      reason: 'the documented v1 gap names the missing concrete tool',
    );
    expect(
      result['error'],
      isNot(contains('null value')),
      reason: 'no null-check crash from a missing handler entry',
    );
  });
}

/// The GitLab `ci_*` reads must surface the provider auth error (E1) —
/// never a `List` type-cast crash on an error envelope.
void gitlabEnvelopeSmokeTests() {
  test(
      'DEFAULT_CI=gitlab-ci: ci_* reads through the REAL handlers surface '
      'the provider auth error (E1) — never a List type-cast crash', () {
    PropertyReader.setOverrides({'DEFAULT_CI': 'gitlab-ci'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    for (final call in [
      ('ci_list_runs', {'workspace': 'g', 'repository': 'r'}),
      ('ci_get_verdict', {'workspace': 'g', 'repository': 'r', 'pr': 4}),
      ('ci_get_verdict', {'workspace': 'g', 'repository': 'r', 'sha': 'abc'}),
      ('ci_get_merge_state', {'workspace': 'g', 'repository': 'r', 'pr': 4}),
    ]) {
      final result =
          jsonDecode(bridge.execute(call.$1, call.$2)) as Map<String, dynamic>;
      expect(result['error'], 'GitLab not configured', reason: call.$1);
    }
  });
}

/// Mirrors the `scm_get_pr` E1 pin for the GitHub control-plane reads:
/// a provider error envelope must reach the caller verbatim — `{runs: []}`
/// / `verdict: none` / `mergeState: UNKNOWN` are semantically meaningful
/// "no CI evidence" answers, so a misconfigured environment must never be
/// normalized into one (gh-339 review, IMPORTANT).
void githubEnvelopeSmokeTests() {
  test(
      'DEFAULT_CI=actions: ci_* reads through the REAL handlers surface '
      'the provider auth error (E1) — never a success-shaped no-evidence', () {
    PropertyReader.setOverrides({'DEFAULT_CI': 'actions'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    for (final call in [
      ('ci_list_runs', {'workspace': 'o', 'repository': 'r'}),
      ('ci_get_verdict', {'workspace': 'o', 'repository': 'r', 'sha': 'abc'}),
      (
        'ci_get_verdict',
        {
          'workspace': 'o',
          'repository': 'r',
          'sha': 'abc',
          'workflow': 'ci.yml'
        },
      ),
      ('ci_get_merge_state', {'workspace': 'o', 'repository': 'r', 'pr': 4}),
    ]) {
      final result =
          jsonDecode(bridge.execute(call.$1, call.$2)) as Map<String, dynamic>;
      expect(result['error'], 'GitHub not configured', reason: call.$1);
    }
  });
}

/// The concrete `github_*` tools stay untouched next to the aliases
/// (additive-only invariant).
void additiveOnlyTests() {
  test(
      'a concrete github tool still dispatches unchanged next to the '
      'aliases (additive-only invariant)', () {
    PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute(
        'github_get_pr',
        {'workspace': 'o', 'repository': 'r', 'pullRequestId': 1},
      ),
    ) as Map<String, dynamic>;
    expect(result['error'], 'GitHub not configured');
  });
}
