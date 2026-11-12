/// Unit tests for `tool/pre_commit_gate.dart` and `.githooks/pre-commit`.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/pre_commit_gate.dart';

void main() {
  pathHelperTests();
  selectionResolverTests();
  hookContractTests();
}

void pathHelperTests() {
  group('isTrackedDartSource / candidateTestPathsForLib', () {
    test('recognizes lib/, bin/, test/ dart files only', () {
      expect(isTrackedDartSource('lib/src/version.dart'), isTrue);
      expect(isTrackedDartSource('bin/dmtools.dart'), isTrue);
      expect(isTrackedDartSource('test/version_test.dart'), isTrue);
      expect(isTrackedDartSource('tool/pre_commit_gate.dart'), isFalse);
      expect(isTrackedDartSource('README.md'), isFalse);
    });

    test('computes candidate test paths for lib/src and lib/', () {
      expect(
        candidateTestPathsForLib('lib/src/cli/cli_args.dart'),
        equals([
          'test/cli/cli_args_test.dart',
          'test/src/cli/cli_args_test.dart',
        ]),
      );
      expect(
        candidateTestPathsForLib('lib/dmtools.dart'),
        equals(['test/dmtools_test.dart']),
      );
      expect(candidateTestPathsForLib('test/foo_test.dart'), isEmpty);
    });
  });
}

void selectionResolverTests() {
  group('resolvePreCommitSelection', () {
    test('maps staged lib/src/<stem>.dart to direct test/<stem>_test.dart', () {
      final existing = <String>{
        'lib/src/version.dart',
        'test/version_test.dart',
      };
      final res = resolvePreCommitSelection([
        './lib/src/version.dart',
        'README.md',
      ], fileExists: existing.contains);
      expect(res.stagedDart, equals(['lib/src/version.dart']));
      expect(res.stagedLib, equals(['lib/src/version.dart']));
      expect(res.stagedTests, isEmpty);
      expect(res.targetTests, equals(['test/version_test.dart']));
    });

    test('falls back to import reference scan when no 1:1 test exists', () {
      final existing = <String>{
        'lib/src/mcp/default_tool_registry.dart',
        'test/scm_ci_gates_test.dart',
      };
      final res = resolvePreCommitSelection(
        ['lib/src/mcp/default_tool_registry.dart'],
        fileExists: existing.contains,
        allTestFiles: {
          'test/scm_ci_gates_test.dart':
              "import 'package:dmtools/src/mcp/default_tool_registry.dart';",
        },
      );
      expect(res.targetTests, equals(['test/scm_ci_gates_test.dart']));
    });

    test('includes staged test files in targetTests', () {
      final existing = <String>{'test/tool/pre_commit_gate_test.dart'};
      final res = resolvePreCommitSelection([
        'test/tool/pre_commit_gate_test.dart',
      ], fileExists: existing.contains);
      expect(res.stagedLib, isEmpty);
      expect(res.stagedTests, equals(['test/tool/pre_commit_gate_test.dart']));
      expect(res.targetTests, equals(['test/tool/pre_commit_gate_test.dart']));
      expect(
        res.toJson()['targetTests'],
        equals(['test/tool/pre_commit_gate_test.dart']),
      );
    });
  });
}

void hookContractTests() {
  group('.githooks/pre-commit contract', () {
    test('hook file is executable and enforces static + CRAP gates', () {
      final hook = File('.githooks/pre-commit').readAsStringSync();
      expect(hook, contains('dart format --output=none --set-exit-if-changed'));
      expect(hook, contains('dart analyze --fatal-infos --fatal-warnings'));
      expect(hook, contains('crap4dart check --staged'));
      expect(hook, contains('complexity'));
      expect(hook, contains('method_size'));
      expect(hook, contains('loc'));
      expect(hook, contains('test_assertions'));
      expect(hook, contains('crap4dart analyze --threshold 8.0'));
    });
  });
}
