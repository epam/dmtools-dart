/// gh-315 — the sharded agents-suite runner: validation, pre-flight,
/// engine invocation, and manifest writing.
///
/// Sharding is opt-in via flags; the no-flag invocation is the historical
/// serial run with byte-identical behavior and exit contract (AC5). The
/// Dart-side pre-flight (every planned file exists and is non-empty)
/// closes the silent-skip hole: `testRunner.js` `continue`s unreadable
/// files, which used to allow a green run with fewer tests — now it is a
/// hard red before the engine starts (AC3, strictly stricter gate).
library;

import 'dart:convert';
import 'dart:io';

import '../js/job_runner.dart';
import 'suite_shard_args.dart';
import 'suite_sharding.dart';

/// Resolved `run_all.json` content.
class AgentsSuiteConfig {
  /// Resolved config.
  const AgentsSuiteConfig({
    required this.jsPath,
    required this.testFiles,
    required this.jobParams,
  });

  /// `params.jsPath` — the runner script, relative to the agents root.
  final String jsPath;

  /// `params.jobParams.testFiles` — the canonical L4 test file list.
  final List<String> testFiles;

  /// The raw `params.jobParams` map. The historical serial runner
  /// forwarded the WHOLE map to the engine (edge case E2: nothing
  /// hardcoded, re-derived from run_all.json every run) — only
  /// `testFiles` is replaced by the planned subset. Typed loosely on
  /// purpose: a future upstream key of any JSON shape must survive.
  final Map<String, dynamic> jobParams;
}

/// Builds the engine's jobParams for [testFiles]: every run_all.json
/// `jobParams` key verbatim, with `testFiles` replaced by the planned
/// subset (the one key the runner owns).
Map<String, dynamic> buildSuiteJobParams(
  AgentsSuiteConfig config,
  List<String> testFiles,
) {
  return <String, dynamic>{
    ...config.jobParams,
    'testFiles': testFiles,
  };
}

/// Thrown when `run_all.json` is missing or malformed.
class SuiteConfigException implements Exception {
  /// Creates an exception with a [message] naming the problem.
  const SuiteConfigException(this.message);

  /// The problem description.
  final String message;

  @override
  String toString() => message;
}

/// Loads and validates `js/unit-tests/run_all.json` under [agentsPath].
AgentsSuiteConfig loadAgentsSuiteConfig(String agentsPath) {
  final decoded = _readRunAllJson(agentsPath);
  final params = _requireMap(decoded, 'params');
  final jobParams = _requireMap(params, 'jobParams');
  return AgentsSuiteConfig(
    jsPath: _requireString(params, 'jsPath'),
    testFiles: _requireStringList(jobParams, 'testFiles'),
    jobParams: Map<String, dynamic>.from(jobParams),
  );
}

dynamic _readRunAllJson(String agentsPath) {
  final configPath = '$agentsPath/js/unit-tests/run_all.json';
  if (!File(configPath).existsSync()) {
    throw SuiteConfigException(
      'Config not found: $configPath\n'
      'Clone dmtools-agents or pass its path as the first arg.',
    );
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(File(configPath).readAsStringSync());
  } on FormatException catch (e) {
    throw SuiteConfigException('Config is not valid JSON: $configPath ($e)');
  }
  if (decoded is! Map) {
    throw SuiteConfigException('Config must be a JSON object: $configPath');
  }
  return decoded;
}

Map<dynamic, dynamic> _requireMap(Map<dynamic, dynamic> parent, String key) {
  final value = parent[key];
  if (value is Map) return value;
  throw SuiteConfigException('Config "$key" must be a JSON object');
}

String _requireString(Map<dynamic, dynamic> parent, String key) {
  final value = parent[key];
  if (value is String) return value;
  throw SuiteConfigException('Config "$key" must be a string');
}

List<String> _requireStringList(Map<dynamic, dynamic> parent, String key) {
  final value = parent[key];
  if (value is List && value.every((f) => f is String)) {
    return [for (final f in value) f as String];
  }
  throw SuiteConfigException('Config "$key" must be a list of strings');
}

/// Runs the agents suite per [args]; returns the process exit code.
///
/// - 0 — green suite (or green shard + manifest written).
/// - 1 — invalid flags, pre-flight failure, red suite, or engine crash.
/// - 2 — `run_all.json` missing or malformed.
///
/// [out]/[err] default to stdout/stderr and are injectable for tests.
int runAgentsSuite(
  SuiteShardArgs args, {
  void Function(String line) out = print,
  void Function(String line) err = _printErr,
}) {
  final problems = _validationProblems(args);
  if (problems.isNotEmpty) {
    for (final problem in problems) {
      err(problem);
    }
    return 1;
  }
  final config = _loadConfigOrReport(args, err);
  if (config == null) return 2;
  final planned = _planOrReport(args, config, err);
  if (planned == null) return 1;
  if (!_preflightOrReport(args, planned, err)) return 1;
  return _runEngine(args, planned, config, out, err);
}

/// Semantic flag-combination validation (AC2); serial runs only carry the
/// parse-level problems through.
List<String> _validationProblems(SuiteShardArgs args) {
  final problems = [...args.problems];
  if (!args.isSharded) return problems;
  _shardFlagProblems(args, problems);
  return problems;
}

/// Shard-combo validation: both flags together, `total >= 1`,
/// `0 <= index < total`, and a manifest path for the gate to parse.
void _shardFlagProblems(SuiteShardArgs args, List<String> problems) {
  if (args.shardIndex == null || args.totalShards == null) {
    problems.add('--shard-index and --total-shards must be given together');
  }
  _totalRangeProblems(args.totalShards, problems);
  _indexRangeProblems(args, problems);
  if (args.manifestOut == null || args.manifestOut!.isEmpty) {
    problems.add('--manifest-out <path> is required for sharded runs: the '
        'agents-gate merge job parses it (never evaled)');
  }
}

void _totalRangeProblems(int? total, List<String> problems) {
  if (total != null && total < 1) {
    problems.add('--total-shards must be >= 1, got $total');
  }
}

void _indexRangeProblems(SuiteShardArgs args, List<String> problems) {
  final index = args.shardIndex;
  if (index != null && index < 0) {
    problems.add('--shard-index must be >= 0, got $index');
  }
  if (index != null && args.totalShards != null && index >= args.totalShards!) {
    problems.add('--shard-index $index must be < '
        '--total-shards ${args.totalShards}');
  }
}

AgentsSuiteConfig? _loadConfigOrReport(
  SuiteShardArgs args,
  void Function(String line) err,
) {
  try {
    return loadAgentsSuiteConfig(args.agentsPath);
  } on SuiteConfigException catch (e) {
    err(e.message);
    return null;
  }
}

/// Plans the shard subset; null after reporting when the shard is empty.
List<String>? _planOrReport(
  SuiteShardArgs args,
  AgentsSuiteConfig config,
  void Function(String line) err,
) {
  if (!args.isSharded) return config.testFiles;
  final planned = ShardPlanner.split(
    config.testFiles,
    args.shardIndex!,
    args.totalShards!,
  );
  if (planned.isNotEmpty) return planned;
  err('Shard ${args.shardIndex}/${args.totalShards} is empty: the suite '
      'has ${config.testFiles.length} files, which cannot fill '
      '${args.totalShards} shards. Reduce --total-shards.');
  return null;
}

/// Pre-flight readability check: every planned file must exist and be
/// non-empty (relative to the agents root) — `testRunner.js` would
/// silently skip the rest.
List<String> preflightTestFiles(String agentsPath, List<String> planned) {
  final problems = <String>[];
  for (final file in planned) {
    final path = '$agentsPath/$file';
    if (!File(path).existsSync()) {
      problems.add('$file: missing');
      continue;
    }
    if (File(path).lengthSync() == 0) {
      problems.add('$file: empty');
    }
  }
  return problems;
}

bool _preflightOrReport(
  SuiteShardArgs args,
  List<String> planned,
  void Function(String line) err,
) {
  final problems = preflightTestFiles(args.agentsPath, planned);
  if (problems.isEmpty) return true;
  err('Pre-flight failed — planned test files are missing or empty '
      '(testRunner.js would silently skip them):');
  for (final problem in problems) {
    err('  - $problem');
  }
  _writeManifest(args, planned, success: false, passed: 0, failed: 0);
  return false;
}

/// Runs the engine over [planned] and applies the acceptance contract.
int _runEngine(
  SuiteShardArgs args,
  List<String> planned,
  AgentsSuiteConfig config,
  void Function(String line) out,
  void Function(String line) err,
) {
  if (args.isSharded) {
    out('Shard ${args.shardIndex}/${args.totalShards}: '
        'planned ${planned.length} test file(s)');
  }

  String? result;
  try {
    result = const JsJobRunner().runScript(
      scriptPath: '${args.agentsPath}/${config.jsPath}',
      jobParams: buildSuiteJobParams(config, planned),
      workingDirectory: args.agentsPath,
    );
  } catch (e) {
    err('Agents suite crashed: $e');
    _writeManifest(args, planned, success: false, passed: 0, failed: 0);
    return 1;
  }

  out('Result: $result');

  // The agents suite is the primary acceptance gate: require a
  // well-formed, fully-passing result. A missing/malformed result (script
  // crash returning undefined) fails the run instead of silently exiting 0.
  final failure = _acceptanceFailure(result);
  if (failure != null) {
    err(failure);
    final counters = _countersFrom(result);
    _writeManifest(
      args,
      planned,
      success: false,
      passed: counters.$1,
      failed: counters.$2,
    );
    return 1;
  }
  final decoded = jsonDecode(result!) as Map;
  final passed = decoded['passed'] as int;
  final failed = decoded['failed'] as int;
  if (args.isSharded) {
    _writeManifest(
      args,
      planned,
      success: true,
      passed: passed,
      failed: failed,
    );
  }
  out('Agents suite green: $passed passed, $failed failed.');
  return 0;
}

/// Maps a raw engine result to a failure message, or null when the result
/// satisfies the acceptance contract (success=true, passed>0, failed=0).
String? _acceptanceFailure(String? result) {
  if (result == null) {
    return 'Agents suite returned no result (script crashed?).';
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(result);
  } on FormatException {
    return 'Agents suite returned non-JSON result: $result';
  }
  if (decoded is! Map) {
    return 'Agents suite returned a non-object result: $decoded';
  }
  if (!_isPassingResult(decoded)) {
    return 'Agents suite failed: $decoded';
  }
  return null;
}

/// The acceptance contract: fully passing AND demonstrably non-empty.
bool _isPassingResult(Map<dynamic, dynamic> decoded) {
  final passed = decoded['passed'];
  final failed = decoded['failed'];
  return decoded['success'] == true &&
      passed is int &&
      failed is int &&
      passed > 0 &&
      failed == 0;
}

/// Extracts upstream's (passed, failed) counters verbatim when the result
/// carries them; (0, 0) when the result is unusable (crash, non-JSON).
(int, int) _countersFrom(String? result) {
  if (result == null) return (0, 0);
  try {
    final decoded = jsonDecode(result);
    if (decoded is Map &&
        decoded['passed'] is int &&
        decoded['failed'] is int) {
      return (decoded['passed'] as int, decoded['failed'] as int);
    }
  } on FormatException {
    // Fall through to the (0, 0) default.
  }
  return (0, 0);
}

/// Writes the shard manifest (sharded runs only). Written for every
/// completed attempt — green, red, or crashed — so a manual re-merge has
/// the full picture; parsed by the gate, never evaled.
void _writeManifest(
  SuiteShardArgs args,
  List<String> planned, {
  required bool success,
  required int passed,
  required int failed,
}) {
  if (!args.isSharded || args.manifestOut == null) {
    return;
  }
  final manifest = ShardManifest(
    shard: args.shardIndex!,
    total: args.totalShards!,
    plannedFiles: planned,
    success: success,
    passed: passed,
    failed: failed,
  );
  final file = File(args.manifestOut!);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
  );
}

void _printErr(String line) => stderr.writeln(line);
