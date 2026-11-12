/// Resolves matching unit tests for staged `lib/` and `test/` Dart files
/// during the `.githooks/pre-commit` quality gate.
library;

import 'dart:convert';
import 'dart:io';

const String _libPrefix = 'lib/';
const String _libSrcPrefix = 'lib/src/';
const String _binPrefix = 'bin/';
const String _testPrefix = 'test/';
const String _dartSuffix = '.dart';
const String _testFileSuffix = '_test.dart';

/// Partitioned staged Dart files and resolved matching unit tests.
class PreCommitSelection {
  /// Staged `.dart` files under `lib/`, `bin/`, or `test/`.
  final List<String> stagedDart;

  /// Staged production `.dart` files under `lib/`.
  final List<String> stagedLib;

  /// Staged test `.dart` files under `test/` (`*_test.dart`).
  final List<String> stagedTests;

  /// Resolved unit-test files (`test/..._test.dart`) to run for coverage.
  final List<String> targetTests;

  /// Creates a [PreCommitSelection].
  const PreCommitSelection({
    required this.stagedDart,
    required this.stagedLib,
    required this.stagedTests,
    required this.targetTests,
  });

  /// Serializes this selection as a JSON-encodable map.
  Map<String, List<String>> toJson() => {
        'stagedDart': stagedDart,
        'stagedLib': stagedLib,
        'stagedTests': stagedTests,
        'targetTests': targetTests,
      };
}

/// Normalizes a relative path and returns whether it is a tracked source path
/// (`lib/`, `bin/`, or `test/`).
bool isTrackedDartSource(String relPath) {
  final p = relPath.trim();
  if (!p.endsWith(_dartSuffix)) return false;
  return p.startsWith(_libPrefix) ||
      p.startsWith(_binPrefix) ||
      p.startsWith(_testPrefix);
}

/// Candidate `test/..._test.dart` paths for a `lib/.../*.dart` path.
List<String> candidateTestPathsForLib(String libPath) {
  if (!libPath.startsWith(_libPrefix) || !libPath.endsWith(_dartSuffix)) {
    return const [];
  }
  final candidates = <String>[];
  if (libPath.startsWith(_libSrcPrefix)) {
    final stem = libPath.substring(
      _libSrcPrefix.length,
      libPath.length - _dartSuffix.length,
    );
    candidates.add('$_testPrefix$stem$_testFileSuffix');
  }
  final rootStem = libPath.substring(
    _libPrefix.length,
    libPath.length - _dartSuffix.length,
  );
  final direct = '$_testPrefix$rootStem$_testFileSuffix';
  if (!candidates.contains(direct)) candidates.add(direct);
  return candidates;
}

/// Resolves the [PreCommitSelection] for [stagedPaths].
///
/// [fileExists] checks if a candidate relative path exists; [allTestFiles]
/// maps relative `test/..._test.dart` paths to their source text for fallback
/// import/reference matching when no 1:1 `test/<stem>_test.dart` exists.
PreCommitSelection resolvePreCommitSelection(
  List<String> stagedPaths, {
  required bool Function(String relPath) fileExists,
  Map<String, String> allTestFiles = const {},
}) {
  final stagedDart = <String>[];
  final stagedLib = <String>[];
  final stagedTests = <String>[];
  final targetTests = <String>{};

  for (final raw in stagedPaths) {
    final p = raw.trim().replaceFirst(RegExp(r'^\./'), '');
    if (!isTrackedDartSource(p) || !fileExists(p)) continue;
    stagedDart.add(p);
    if (p.startsWith(_libPrefix)) {
      stagedLib.add(p);
    } else if (p.startsWith(_testPrefix) && p.endsWith(_testFileSuffix)) {
      stagedTests.add(p);
      targetTests.add(p);
    }
  }

  for (final libFile in stagedLib) {
    final directMatches =
        candidateTestPathsForLib(libFile).where(fileExists).toList();
    if (directMatches.isNotEmpty) {
      targetTests.addAll(directMatches);
    } else {
      targetTests.addAll(_findReferencingTests(libFile, allTestFiles));
    }
  }

  return PreCommitSelection(
    stagedDart: stagedDart,
    stagedLib: stagedLib,
    stagedTests: stagedTests,
    targetTests: targetTests.toList()..sort(),
  );
}

List<String> _findReferencingTests(
  String libFile,
  Map<String, String> allTestFiles,
) {
  final subPath = libFile.startsWith(_libPrefix)
      ? libFile.substring(_libPrefix.length)
      : libFile;
  final baseName = libFile.split('/').last;
  final matches = <String>[];
  for (final entry in allTestFiles.entries) {
    final content = entry.value;
    if (content.contains(subPath) || content.contains('/$baseName')) {
      matches.add(entry.key);
    }
  }
  matches.sort();
  return matches.take(5).toList();
}

Map<String, String> _scanTestFiles(Directory root) {
  final testDir = Directory('${root.path}/test');
  if (!testDir.existsSync()) return const {};
  final map = <String, String>{};
  for (final entity in testDir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith(_testFileSuffix)) {
      final rel = entity.path.substring(root.path.length + 1);
      map[rel] = entity.readAsStringSync();
    }
  }
  return map;
}

/// CLI entry point: prints JSON selection for the given staged file paths.
void main(List<String> args) {
  final root = Directory.current;
  final selection = resolvePreCommitSelection(
    args,
    fileExists: (rel) => File('${root.path}/$rel').existsSync(),
    allTestFiles: _scanTestFiles(root),
  );
  stdout.writeln(jsonEncode(selection.toJson()));
}
