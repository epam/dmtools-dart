// gh-315 — agents-gate merge tool: the CI merge job's single assertion
// point. Reads every downloaded suite-shard manifest (parsed, never
// evaled), merges them against the canonical `run_all.json` testFiles
// list, and exits 0 only when every shard is green AND the planned-file
// multiset equals the canonical list exactly (missing or duplicated file
// ⇒ red, never a silent green with fewer tests).
//
// Usage (from the repo root, manifests downloaded into a directory tree):
//   dart run scripts/agents_shard_gate.dart <manifests-dir> <run_all.json>
//
// The merge logic itself lives in lib/src/agents/suite_sharding.dart and
// is unit-tested in test/agents/suite_sharding_test.dart (AC4 hooks).
import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/agents/suite_sharding.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run scripts/agents_shard_gate.dart '
      '<manifests-dir> <run_all.json>',
    );
    exit(2);
  }
  final manifestsDir = Directory(args[0]);
  final runAllPath = args[1];

  if (!manifestsDir.existsSync()) {
    stderr.writeln('Manifests directory not found: ${manifestsDir.path}');
    exit(2);
  }
  final payloads = _collectManifestPayloads(manifestsDir);
  if (payloads.isEmpty) {
    stderr.writeln('No manifest JSON files under ${manifestsDir.path}');
    exit(1);
  }

  final expectedFiles = _expectedFiles(runAllPath);

  final result = ShardManifestMerger.merge(
    manifestJsons: payloads,
    expectedFiles: expectedFiles,
  );

  final passed = result.passedTotal;
  final failed = result.failedTotal;
  stdout.writeln(
    'agents-gate: ${payloads.length} shard manifest(s), '
    '$passed passed, $failed failed',
  );
  for (final problem in result.problems) {
    stdout.writeln('  ✗ $problem');
  }
  if (!result.ok) {
    stderr.writeln(
      'agents-gate RED: ${result.problems.length} merge problem(s) — '
      'the suite partition is broken or a shard is red',
    );
    exit(1);
  }
  stdout.writeln(
    'agents-gate green: partition exact, all shards green '
    '($passed passed, $failed failed).',
  );
}

/// Every `*.json` file under [dir], recursively (download-artifact with a
/// pattern restores one subdirectory per shard artifact).
List<String> _collectManifestPayloads(Directory dir) {
  final payloads = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.json')) {
      payloads.add(entity.readAsStringSync());
    }
  }
  return payloads;
}

/// The canonical `params.jobParams.testFiles` list.
List<String> _expectedFiles(String runAllPath) {
  final file = File(runAllPath);
  if (!file.existsSync()) {
    stderr.writeln('run_all.json not found: $runAllPath '
        '(agents-gate needs the agents/ submodule checked out)');
    exit(2);
  }
  final config = jsonDecode(file.readAsStringSync());
  final params = config is Map ? config['params'] : null;
  final jobParams = params is Map ? params['jobParams'] : null;
  final testFiles = jobParams is Map ? jobParams['testFiles'] : null;
  if (testFiles is! List || testFiles.any((f) => f is! String)) {
    stderr.writeln(
      'Malformed run_all.json: params.jobParams.testFiles must be a list '
      'of strings ($runAllPath)',
    );
    exit(2);
  }
  return [for (final f in testFiles) f as String];
}
