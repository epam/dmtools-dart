/// `scm_*` / `ci_*` alias catalog — availability and normalized schemas
/// (gh-339 AC1).
///
/// Availability rule (AC1, the tracker-alias pattern): the `scm_*` family
/// is registered when `DEFAULT_SCM` resolves to `github` or `gitlab`, the
/// `ci_*` family when `DEFAULT_CI` resolves to `actions` or `gitlab-ci`;
/// unset (or unknown) means the family is absent from the registry and
/// `dmtools list`. Values resolve through the standard property chain
/// (overrides → config.properties → dmtools.env → OS env).
library;

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/integrations/scm/scm_ci_alias_catalog.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:dmtools/src/mcp/tool_registry.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() => PropertyReader.setOverrides(const {}));
  tearDown(PropertyReader.clearOverrides);

  availabilityTests();
  schemaTests();
  catalogParityTests();
}

RegistryAndCatalog buildRegistry({Map<String, String> overrides = const {}}) {
  PropertyReader.setOverrides(overrides);
  final registry = createDefaultToolRegistry();
  return (
    registry: registry,
    names: registry.allTools.map((t) => t.name).toSet(),
  );
}

typedef RegistryAndCatalog = ({ToolRegistry registry, Set<String> names});

/// AC1 — the families appear when the env vars are set and vanish when
/// they are not.
void availabilityTests() {
  group('scm_*/ci_* availability (AC1)', () {
    test('nothing registered when neither env var is set', () {
      final r = buildRegistry();
      expect(r.names.where((n) => n.startsWith('scm_')), isEmpty);
      expect(r.names.where((n) => n.startsWith('ci_')), isEmpty);
    });

    test('DEFAULT_SCM=github registers the scm_ family only', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': 'github'});
      expect(r.names, contains('scm_get_pr'));
      expect(r.names.any((n) => n.startsWith('ci_')), isFalse);
    });

    test('DEFAULT_CI=actions registers the ci_ family only', () {
      final r = buildRegistry(overrides: {'DEFAULT_CI': 'actions'});
      expect(r.names, containsAll(['ci_trigger_workflow', 'ci_get_verdict']));
      expect(r.names.any((n) => n.startsWith('scm_')), isFalse);
    });

    test('both axes are independent (the recommended env pair)', () {
      final r = buildRegistry(
        overrides: {'DEFAULT_SCM': 'gitlab', 'DEFAULT_CI': 'gitlab-ci'},
      );
      expect(r.names, contains('scm_get_pr'));
      expect(r.names, contains('ci_get_verdict'));
    });

    test('dmtools list shows the family when set', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': 'github'});
      final list = r.registry.generateToolsListResponse();
      final names = (list['tools'] as List)
          .map((t) => (t as Map)['name'] as String)
          .toSet();
      expect(names, contains('scm_get_pr'));
    });

    test('dmtools list hides the family when unset', () {
      final r = buildRegistry();
      final list = r.registry.generateToolsListResponse();
      final names = (list['tools'] as List)
          .map((t) => (t as Map)['name'] as String)
          .toSet();
      expect(names.any((n) => n.startsWith('scm_')), isFalse);
    });

    test('unknown provider values mean unavailable (same as unset)', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': 'bitbucket'});
      expect(r.names.any((n) => n.startsWith('scm_')), isFalse);
    });

    test('values are trimmed and lowercased like the tracker env reads', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': ' GitHub '});
      expect(r.names, contains('scm_get_pr'));
    });
  });
}

/// The alias schemas are the NORMALIZED shape — not the GitHub shape
/// copied (gh-339 invariant 2).
void schemaTests() {
  group('normalized schemas', () {
    test('every scm/ci alias resolves in a configured registry', () {
      final r = buildRegistry(
        overrides: {'DEFAULT_SCM': 'github', 'DEFAULT_CI': 'actions'},
      );
      for (final name in scmAliasToolNames) {
        expect(r.registry.getTool(name), isNotNull, reason: name);
      }
      for (final name in ciAliasToolNames) {
        expect(r.registry.getTool(name), isNotNull, reason: name);
      }
    });

    test('the PR reference is the neutral `pr`, not `pullRequestId`', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': 'github'});
      final pr = r.registry.getTool('scm_get_pr')!;
      expect(pr.params.map((p) => p.name), contains('pr'));
      expect(pr.params.map((p) => p.name), isNot(contains('pullRequestId')));
      expect(pr.requiredParams, ['workspace', 'repository', 'pr']);
    });

    test('the state filter carries the normalized state enum', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': 'github'});
      final list = r.registry.getTool('scm_list_prs')!;
      final state = list.params.firstWhere((p) => p.name == 'state');
      expect(state.required, isFalse);
      expect(
        state.description,
        contains('open, closed, merged, all'),
      );
    });

    test('ci_trigger_workflow takes workflow/ref/inputs, not workflowId', () {
      final r = buildRegistry(overrides: {'DEFAULT_CI': 'actions'});
      final t = r.registry.getTool('ci_trigger_workflow')!;
      final names = t.params.map((p) => p.name).toSet();
      expect(names, containsAll(['workflow', 'ref', 'inputs']));
      expect(names, isNot(contains('workflowId')));
      expect(t.requiredParams, ['workflow']);
    });

    test('ci_get_verdict accepts runId XOR (sha[, workflow])', () {
      final r = buildRegistry(overrides: {'DEFAULT_CI': 'actions'});
      final t = r.registry.getTool('ci_get_verdict')!;
      final names = t.params.map((p) => p.name).toSet();
      expect(names, containsAll(['runId', 'sha', 'workflow']));
      expect(t.requiredParams, ['workspace', 'repository']);
    });

    test('ci_get_merge_state speaks the SM mergeState enum', () {
      final r = buildRegistry(overrides: {'DEFAULT_CI': 'actions'});
      final t = r.registry.getTool('ci_get_merge_state')!;
      expect(t.requiredParams, ['workspace', 'repository', 'pr']);
      expect(t.description, contains('CLEAN'));
      expect(t.description, contains('BLOCKED'));
    });

    test('alias tools own the scm/ci integrations for list filtering', () {
      final catalog = [
        ...scmAliasTools(),
        ...ciAliasTools(),
      ];
      expect(
          catalog.every((t) => t.integration == 'scm' || t.integration == 'ci'),
          isTrue);
    });
  });
}

/// The concrete github_*/gitlab_* names and schemas stay bit-identical —
/// the alias layer is purely additive (gh-339 AC4 guard).
void catalogParityTests() {
  group('additive-only catalog (AC4 guard)', () {
    test('no alias tool shadows a concrete tool name', () {
      final r = buildRegistry(
        overrides: {'DEFAULT_SCM': 'github', 'DEFAULT_CI': 'actions'},
      );
      final aliasNames = {...scmAliasToolNames, ...ciAliasToolNames};
      expect(r.registry.allTools.where((t) => aliasNames.contains(t.name)),
          hasLength(aliasNames.length),
          reason: 'each alias must be a distinct new tool');
    });

    test('a concrete github tool keeps its exact schema alongside aliases', () {
      final r = buildRegistry(overrides: {'DEFAULT_SCM': 'github'});
      final gh = r.registry.getTool('github_get_pr')!;
      expect(gh.integration, 'github');
      expect(gh.requiredParams, ['workspace', 'repository', 'pullRequestId']);
      expect(
        gh.aliases.where((a) => a.startsWith('scm_') || a.startsWith('ci_')),
        isEmpty,
        reason: 'scm_*/ci_* are standalone tools, never aliases on github_*',
      );
    });
  });
}
