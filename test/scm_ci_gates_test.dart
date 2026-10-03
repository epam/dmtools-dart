/// REG gates for the `scm_*`/`ci_*` alias layer (gh-339).
///
/// - AC2: the committed usage census (`scm_alias_usage_census.txt`) is
///   current (recomputed from `agents/js` on every run) and every census
///   tool is covered by a registered alias (census ⊆ alias set).
/// - AC3: the SM loop files contain zero `github_*` call sites after
///   migration — the grep gate. Any red here blocks merge even with
///   UT/IT green.
///
/// AC4 (catalog parity) lives in `test/mcp/catalog_parity_test.dart`
/// (unchanged and green); AC5 (agents suite) is the dedicated CI job.
library;

import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/integrations/scm/scm_ci_alias_catalog.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

import '../tool/scm_alias_census.dart';

void main() {
  setUpAll(() {
    PropertyReader.testIsolation = true;
    PropertyReader.testEnvironment.clear();
  });
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  censusTests();
  grepGateTests();
}

/// AC2 — the census is the tiering witness for the core alias subset.
void censusTests() {
  group('scm alias usage census (AC2)', () {
    test('the committed fixture is current (regenerate when js/ changes)',
        () {
      final computed = computeCensus();
      final committed = File('test/fixtures/scm_alias_usage_census.txt')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
          .toList()
        ..sort();
      expect(
        committed,
        computed,
        reason: 'test/fixtures/scm_alias_usage_census.txt is stale — '
            'regenerate with: dart run tool/scm_alias_census.dart',
      );
    });

    test('the census is non-empty (the scan actually sees agents/js)', () {
      expect(computeCensus(), isNotEmpty);
    });

    test('census ⊆ alias set — every census tool has a covering alias', () {
      PropertyReader.setOverrides({
        'DEFAULT_SCM': 'github',
        'DEFAULT_CI': 'actions',
      });
      final aliasNames = createDefaultToolRegistry()
          .allTools
          .map((t) => t.name)
          .toSet();
      final censusTools =
          computeCensus().map((l) => l.split(' ').first).toSet();
      expect(censusTools, isNotEmpty);
      for (final tool in censusTools) {
        final alias = kCensusToolAlias[tool];
        expect(alias, isNotNull,
            reason: '$tool appears in agents/js but has no census mapping');
        expect(aliasNames, contains(alias),
            reason: '$tool is covered by $alias — alias must be registered');
      }
    });

    test('every alias that the SM gate files need is in the census map', () {
      // The grep-gate files must be migratable with ONLY the core
      // subset — a gate file needing an unmapped tool is a tiering bug.
      final gateSites = computeCensus()
          .map((l) => l.split(' ').last)
          .where((p) =>
              p.contains('js/sm/') ||
              p.endsWith('agents/js/machineSmAgent.js') ||
              p.endsWith('agents/js/smAgent.js'))
          .toSet();
      expect(gateSites, isNotEmpty);
    });
  });
}

/// AC3 — the SM loop runs on the aliases: zero `github_*` tokens in the
/// gate files (mentions included — a stale comment would rot first).
void grepGateTests() {
  group('SM loop grep gate (AC3)', () {
    const gateFiles = [
      'agents/js/sm/sources/githubSource.js',
      'agents/js/sm/mergeBot.js',
      'agents/js/sm/sourceResolver.js',
      'agents/js/machineSmAgent.js',
    ];

    test('the gate files exist (the gate cannot silently pass on a move)',
        () {
      for (final f in gateFiles) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }
    });

    test('zero github_* tokens in the SM loop files', () {
      final violations = <String>[];
      final pattern = RegExp(r'github_[a-z]');
      for (final f in gateFiles) {
        var lineNo = 0;
        for (final line in File(f).readAsLinesSync()) {
          lineNo++;
          if (pattern.hasMatch(line)) violations.add('$f:$lineNo: $line');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'AC3: the SM loop must run on the vendor-neutral scm_*/'
            'ci_* aliases — migrate the sites above (ci_get_verdict, '
            'ci_list_runs, scm_* data plane) instead of calling github_* '
            'directly',
      );
    });
  });
}
