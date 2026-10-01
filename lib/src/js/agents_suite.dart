/// Parallel execution of the dmtools-agents JS unit-test suite.
///
/// `run_all.json` feeds ~95 test files to `testRunner.js` as ONE
/// synchronous QuickJS job — ~12 min wall time on a CI runner. This
/// library cuts `jobParams.testFiles` into contiguous chunks and runs
/// them on a pull queue of N worker isolates (N = `DMTOOLS_SUITE_SHARDS`
/// / `numberOfProcessors`, capped at 8):
///
/// - `JsJobRunner.runScript` is fully synchronous FFI (`qjs_eval` blocks
///   the calling thread), so `Future.wait` inside one isolate adds zero
///   parallelism — real concurrency needs one isolate per in-flight
///   chunk.
/// - One isolate per chunk is also what the FFI layer requires: host
///   functions are `NativeCallable.isolateLocal`, legal only when invoked
///   on the owning isolate's thread — exactly the thread blocked inside
///   `qjs_eval` for that chunk.
/// - Concurrent runtimes are safe. The C bridge keeps a process-global
///   host-callback table whose indices are monotonic and atomic
///   (`quickjs_bridge.c`: `qjs_reset_callbacks` is an intentional no-op),
///   so registrations from parallel isolates never clobber each other —
///   the same pattern the `runAsync` worker pool already uses in
///   production (`async_job_pool.dart`).
///
/// ## Why contiguous chunks + prefix priming (not round-robin)
///
/// `testRunner.js` evals every test file inside `action(params)` with
/// `eval(testCode)`, so all files share one variable scope in run order:
/// later files freely read globals defined by earlier files (measured:
/// ~45 of 94 files change pass/fail counts when run out of order — e.g.
/// `test_workingDir.js` reads `commentMarkupModule` defined by
/// `test_postPRReviewComments.js`). Arbitrary sharding would corrupt the
/// counts. Instead every chunk is a contiguous slice and PRIMES the
/// exact serial prefix: the files before its slice are eval'd with
/// `test()` / `suite()` neutralized (bodies skipped, nothing counted —
/// [primePreludeJs]), then the slice runs with the real runner restored.
/// Every counted file therefore sees byte-for-byte the same scope state
/// as in a serial run, so totals match the serial run exactly — no
/// matter how the pull queue interleaves the chunks.
///
/// ## Why every chunk runs in a disposable tree copy
///
/// The suite is NOT read-only over the agents checkout: tests persist
/// cross-file state on disk (fixture caches, `outputs/` artifacts) and
/// some wait on those files with real-time CLI-resume backoffs. On a
/// shared working tree, concurrent chunks interleave those writes — on
/// CI (slow disk) this opened a minutes-wide race window: a chunk's
/// prefix rebuild could momentarily truncate `outputs/response.md`, the
/// `publishDiscoveryToConfluence` test then sat in its resume-backoff
/// for 6+ minutes before giving up, and two such stragglers pinned the
/// whole run at ~12.7 min despite the other 46 chunks finishing in
/// under a second (2026-10-01, run 36891377431). Each chunk therefore
/// gets its own copy of the tree (`.git`/`.dart_tool` skipped, ~11 MB)
/// and is its single writer; the prefix priming rebuilds the exact
/// serial on-disk state inside that copy, so counts stay identical to
/// a serial run. `DMTOOLS_SUITE_ISOLATED_COPIES=0` falls back to the
/// shared tree.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'job_runner.dart';

/// Parsed `run_all.json` (JSRunner job config) — everything the suite
/// runner needs to execute the job.
class AgentsSuiteConfig {
  /// Creates a suite config.
  const AgentsSuiteConfig({
    required this.jsPath,
    required this.jobParams,
    required this.testFiles,
  });

  /// Loads and validates the suite config at
  /// `<agentsPath>/js/unit-tests/run_all.json`.
  ///
  /// Throws [StateError] with a descriptive message when the file is
  /// missing or malformed (the caller maps that to a hard failure).
  factory AgentsSuiteConfig.load(String agentsPath) {
    final configPath = '$agentsPath/js/unit-tests/run_all.json';
    final file = File(configPath);
    if (!file.existsSync()) {
      throw StateError('Config not found: $configPath');
    }
    final Map config;
    try {
      config = jsonDecode(file.readAsStringSync()) as Map;
    } on FormatException catch (e) {
      throw StateError('Config is not valid JSON: $e');
    }
    final params = config['params'];
    if (params is! Map) throw StateError('Config has no params object');
    final jsPath = params['jsPath'];
    if (jsPath is! String || jsPath.isEmpty) {
      throw StateError('Config params.jsPath must be a non-empty string');
    }
    final jobParams = params['jobParams'];
    if (jobParams is! Map) {
      throw StateError('Config params.jobParams must be an object');
    }
    final testFiles = jobParams['testFiles'];
    if (testFiles is! List || testFiles.whereType<String>().isEmpty) {
      throw StateError('Config params.jobParams.testFiles must be a '
          'non-empty array of strings');
    }
    return AgentsSuiteConfig(
      jsPath: jsPath,
      jobParams: Map<String, dynamic>.from(jobParams),
      testFiles: List<String>.from(testFiles.whereType<String>()),
    );
  }

  /// `params.jsPath` — the runner script, relative to the agents path.
  final String jsPath;

  /// `params.jobParams` verbatim (shards get a copy with `testFiles`
  /// replaced by prime files + their own slice).
  final Map<String, dynamic> jobParams;

  /// `jobParams.testFiles` — the flat, serial-order list to shard.
  final List<String> testFiles;
}

/// Resolves the effective shard count.
///
/// [envOverride] is the raw `DMTOOLS_SUITE_SHARDS` value: an integer >= 1
/// wins as-is (explicit intent, still clamped to the file count by the
/// shard planner); anything else (null, garbage, < 1) falls back to
/// `min([processors], [autoCap])` with a floor of 1.
int resolveShardCount(
  String? envOverride, {
  required int processors,
  int autoCap = 8,
}) {
  final parsed = int.tryParse(envOverride?.trim() ?? '');
  if (parsed != null && parsed >= 1) return parsed;
  if (processors < 1) return 1;
  return processors > autoCap ? autoCap : processors;
}

/// One planned work unit ("chunk"): the serial [primeFiles] prefix
/// (eval'd uncounted) plus this chunk's [countedFiles] slice. Order
/// within both lists is the original `run_all.json` order.
class ShardChunk {
  /// Creates a chunk.
  const ShardChunk({required this.primeFiles, required this.countedFiles});

  /// Files evaluated with counting neutralized to reproduce the serial
  /// scope state (empty for the first chunk).
  final List<String> primeFiles;

  /// The files this chunk owns — the only ones whose tests are counted.
  final List<String> countedFiles;
}

/// How many chunks to cut per worker. Chunks are deliberately much
/// smaller than a worker's share: per-file cost is heavy-tailed and
/// size-unpredictable (a few agent-workflow files cost seconds —
/// `test_developTicketAndCreatePR.js` alone is ~4.7 s — while most cost
/// milliseconds), so fine chunks let the pull queue split clustered
/// heavy files across workers. Measured overhead per extra chunk: one
/// engine boot + prime ≈ 100–200 ms, far below the balance it buys.
const int chunksPerWorker = 12;

/// Chunk count for [shardCount] workers over [fileCount] files.
int chunkCountFor(int fileCount, int shardCount) {
  final chunks = shardCount * chunksPerWorker;
  return chunks > fileCount || chunks < 1 ? fileCount : chunks;
}

/// Plans [chunkCount] contiguous, weight-balanced chunks of [files].
///
/// Boundaries sit at the cumulative-[weightOf] fractions of the total
/// (file size by default — a cheap, deterministic tiebreaker; real
/// balance comes from the dynamic chunk queue, not the weights), then
/// clamp so every chunk stays non-empty. Contiguity is what makes
/// prefix priming exact — see [primePreludeJs]. A chunk count below 1
/// yields one chunk; above the file count, one file per chunk.
List<ShardChunk> planChunks(
  List<String> files,
  int chunkCount,
  int Function(String file) weightOf,
) {
  if (files.isEmpty) return const [];
  final n = chunkCount <= 1
      ? 1
      : (chunkCount > files.length ? files.length : chunkCount);
  final weights = [for (final f in files) weightOf(f)];
  final total = weights.fold<int>(0, (a, w) => a + w);
  final starts = _chunkStarts(weights, total, n);
  return [
    for (var j = 0; j < n; j++)
      ShardChunk(
        primeFiles: files.sublist(0, starts[j]),
        countedFiles: files.sublist(starts[j], starts[j + 1]),
      ),
  ];
}

/// First index of each chunk plus the sentinel end index.
///
/// Boundary j sits at the first index whose preceding weight sum reaches
/// the j-th quota fraction (`j * total / n`), clamped to keep every
/// chunk non-empty: strictly after the previous boundary, with at least
/// one file left for each remaining chunk. Prefix-sum based — pure and
/// deterministic for identical inputs.
List<int> _chunkStarts(List<int> weights, int total, int n) {
  final prefix = <int>[0];
  for (final w in weights) {
    prefix.add(prefix.last + w);
  }
  final starts = <int>[0];
  for (var j = 1; j < n; j++) {
    final quota = (j * total) / n;
    var index = starts.last + 1;
    while (index < weights.length && prefix[index] < quota) {
      index++;
    }
    final lastPossible = weights.length - (n - j);
    if (index > lastPossible) index = lastPossible;
    starts.add(index);
  }
  starts.add(weights.length);
  return starts;
}

/// JS evaluated (via `JsRunConfig.preActionCode`) after `testRunner.js`
/// is evaluated but before `action(params)` runs — the priming hook.
///
/// Neutralizes the runner's `test()`/`suite()` (prime files' top-level
/// statements still eval, so their globals materialize exactly as in a
/// serial run, but no test bodies execute and nothing is counted) and
/// diverts result counting into a dump object. The wrapper restores the
/// real `test`/`suite`/`file_read`/`_results_` the moment the runner
/// reads the [primeCount]+1-th suite file — the first file of this
/// chunk's own slice — so from that file on, execution is
/// byte-for-byte the serial one.
///
/// The trigger counts suite-file READS instead of matching a path:
/// `run_all.json` legitimately lists `test_postPRReviewComments.js`
/// twice (verified against the upstream repo), and a path match would
/// fire on the prime copy. Counting reads also tolerates any future
/// duplicate. Module `loadModule` reads never hit suite paths, so they
/// cannot advance the counter.
String primePreludeJs(List<String> suiteFiles, int primeCount) {
  return '(function () {\n'
      '  var suiteFiles = ${jsonEncode(suiteFiles)};\n'
      '  var primeCount = $primeCount;\n'
      '  var seen = 0;\n'
      '  var real = { results: _results_, test: test, suite: suite,'
      ' read: file_read };\n'
      '  var restore = function () {\n'
      '    _results_ = real.results; test = real.test;\n'
      '    suite = real.suite; file_read = real.read;\n'
      '  };\n'
      '  test = function () {};\n'
      '  suite = function (name, fn) { try { fn(); } catch (e) {} };\n'
      '  file_read = function (args) {\n'
      '    var p = args && (args.path || args);\n'
      '    if (p != null && suiteFiles.indexOf(p) !== -1) {\n'
      '      seen++;\n'
      '      if (seen > primeCount) restore();\n'
      '    }\n'
      '    return real.read(args);\n'
      '  };\n'
      '})();';
}

/// One shard's inputs — everything a fresh isolate needs to run its
/// slice of the suite. Deeply sendable across `Isolate.run`.
class ShardInvocation {
  /// Creates a shard invocation.
  const ShardInvocation({
    required this.index,
    required this.total,
    required this.scriptPath,
    required this.jobParams,
    required this.workingDirectory,
    required this.preludeCode,
  });

  /// Zero-based shard number (for log attribution).
  final int index;

  /// Total shard count (for log attribution).
  final int total;

  /// Absolute path of `testRunner.js`.
  final String scriptPath;

  /// Job params with `testFiles` set to prime files + this shard's slice.
  final Map<String, dynamic> jobParams;

  /// Working directory for the run (the agents checkout).
  final String workingDirectory;

  /// The priming prelude ([primePreludeJs]) for this shard.
  final String preludeCode;
}

/// Builds the invocation for each chunk against [agentsPath].
List<ShardInvocation> invocationsFor({
  required String agentsPath,
  required AgentsSuiteConfig config,
  required List<ShardChunk> chunks,
}) {
  return [
    for (var i = 0; i < chunks.length; i++)
      ShardInvocation(
        index: i,
        total: chunks.length,
        scriptPath: '${agentsPath}/${config.jsPath}',
        jobParams: {
          ...config.jobParams,
          'testFiles': [...chunks[i].primeFiles, ...chunks[i].countedFiles],
        },
        workingDirectory: agentsPath,
        preludeCode: primePreludeJs(
          [...chunks[i].primeFiles, ...chunks[i].countedFiles],
          chunks[i].primeFiles.length,
        ),
      ),
  ];
}

/// One shard's outcome — the raw `action()` result JSON, or the error
/// text when the shard never produced one (isolate crash, wiring error,
/// script exception). Deeply sendable across `Isolate.run`.
class ShardOutcome {
  /// Creates a shard outcome.
  const ShardOutcome({required this.index, this.result, this.error});

  /// Creates the outcome for a shard that crashed before producing a
  /// result ([error] text only).
  const ShardOutcome.crashed(this.index, this.error) : result = null;

  /// Zero-based shard number.
  final int index;

  /// Raw JSON string returned by `action(params)`; null when the shard
  /// crashed (mirrors `runScript` returning null on a JS `undefined`).
  final String? result;

  /// Why the shard crashed, when it did.
  final String? error;

  /// Whether the shard produced a well-formed result object with integer
  /// `passed`/`failed` counters (see [_decodedMap]). Malformed ⇒ the
  /// whole run fails, exactly like a malformed single-run result did
  /// before sharding.
  bool get malformed => _decodedMap == null;

  /// Passed tests reported by this shard (0 when malformed/crashed).
  int get passed => _decodedMap?['passed'] as int? ?? 0;

  /// Failed tests reported by this shard (0 when malformed/crashed).
  int get failed => _decodedMap?['failed'] as int? ?? 0;

  /// The shard's result map when well-formed (integer `passed`/`failed`
  /// counters present), else null — crashed, undecodable, non-object, or
  /// missing counters all collapse to "no usable result".
  Map? get _decodedMap {
    if (result == null) return null;
    final dynamic decoded;
    try {
      decoded = jsonDecode(result!);
    } on FormatException {
      return null;
    }
    return decoded is Map &&
            decoded['passed'] is int &&
            decoded['failed'] is int
        ? decoded
        : null;
  }
}

/// Aggregated suite totals across all shards.
class AgentsSuiteReport {
  /// Creates a report.
  const AgentsSuiteReport({
    required this.success,
    required this.passed,
    required this.failed,
    required this.malformedShards,
    required this.crashedShards,
  });

  /// Aggregates shard outcomes into suite totals.
  ///
  /// `success` requires EVERY shard to be well-formed, crash-free, and
  /// green, plus a non-zero total pass count — the sharded equivalent
  /// of the old single-run gate (`success && passed > 0 && failed == 0`).
  factory AgentsSuiteReport.fromShards(List<ShardOutcome> outcomes) {
    var passed = 0;
    var failed = 0;
    var allGreen = true;
    final malformed = <int>[];
    final crashed = <int>[];
    for (final outcome in outcomes) {
      if (outcome.error != null) {
        crashed.add(outcome.index);
        allGreen = false;
        continue;
      }
      if (outcome.malformed) {
        malformed.add(outcome.index);
        allGreen = false;
        continue;
      }
      passed += outcome.passed;
      failed += outcome.failed;
      allGreen = allGreen && outcome.failed == 0;
    }
    return AgentsSuiteReport(
      success: allGreen && outcomes.isNotEmpty && passed > 0 && failed == 0,
      passed: passed,
      failed: failed,
      malformedShards: malformed,
      crashedShards: crashed,
    );
  }

  /// Whether the whole suite is green (the `Result:` success field).
  final bool success;

  /// Total passed tests, summed over shards.
  final int passed;

  /// Total failed tests, summed over shards.
  final int failed;

  /// Indices of shards whose result was missing/malformed.
  final List<int> malformedShards;

  /// Indices of shards that crashed before producing a result.
  final List<int> crashedShards;

  /// The exit code for `bin/run_agents_suite.dart`: 0 when green, 1 when
  /// the suite failed or any shard was malformed/crashed — the same
  /// contract the serial runner had (`exit(1)` on red or malformed).
  int get exitCode =>
      success && malformedShards.isEmpty && crashedShards.isEmpty ? 0 : 1;

  /// The `Result:` JSON body — same shape the serial `testRunner.js`
  /// result had (`{"success":…,"passed":…,"failed":…}`).
  Map<String, dynamic> toJson() => {
        'success': success,
        'passed': passed,
        'failed': failed,
      };
}

/// Per-chunk stderr diagnostics for crashed/malformed chunks (one line
/// each; empty when every chunk produced a well-formed result).
String shardDiagnostics(List<ShardOutcome> outcomes) {
  final lines = <String>[];
  for (final outcome in outcomes) {
    if (outcome.error != null) {
      lines.add('Chunk ${outcome.index + 1} crashed: ${outcome.error}');
    } else if (outcome.malformed) {
      lines.add(
        'Chunk ${outcome.index + 1} returned a malformed result: '
        '${outcome.result ?? '<none>'}',
      );
    }
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// One-line stderr summary for a red run.
String failureSummary(AgentsSuiteReport report) {
  return '${report.passed} passed, ${report.failed} failed, '
      '${report.crashedShards.length} crashed, '
      '${report.malformedShards.length} malformed chunks.';
}

/// Signature of the per-chunk executor — [runChunkInIsolate] in
/// production, fakes in unit tests.
typedef ShardRunner = Future<ShardOutcome> Function(ShardInvocation chunk);

/// Runs [chunks] through [runChunk] with at most [concurrency] in flight.
///
/// A pull-based queue, not one isolate per chunk: per-file test cost is
/// heavy-tailed (a few agent-workflow files cost seconds, most cost
/// milliseconds) and unpredictable from file size, so fixed chunks would
/// strand a slow file behind one worker. Workers claim the next chunk
/// when they finish, which absorbs the skew. Results keep chunk order
/// regardless of completion order, and every counted file still runs
/// exactly once with its exact serial prefix — totals are identical to
/// a serial run no matter how the queue interleaves.
Future<List<ShardOutcome>> runChunkQueue(
  List<ShardInvocation> chunks,
  ShardRunner runChunk, {
  required int concurrency,
}) async {
  final outcomes = List<ShardOutcome?>.filled(chunks.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < chunks.length) {
      final claimed = next++;
      outcomes[claimed] = await runChunk(chunks[claimed]);
    }
  }

  final workers = concurrency < 1
      ? 1
      : (concurrency > chunks.length ? chunks.length : concurrency);
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return [for (final o in outcomes) o!];
}

/// Default [ShardRunner]: runs the chunk on its own isolate.
///
/// `Isolate.run` gives the chunk its own thread, so its synchronous
/// `qjs_eval` FFI blocks only that isolate while the siblings keep
/// running; `NativeCallable.isolateLocal` host functions stay legal
/// because each callback fires on the isolate that registered it (the
/// same thread that is inside `qjs_eval`). Errors are captured inside
/// the isolate and returned as a crashed outcome — one dead chunk fails
/// the run instead of killing the sibling chunks.
Future<ShardOutcome> runChunkInIsolate(ShardInvocation chunk) {
  return Isolate.run(() => _runChunkSync(chunk));
}

/// Synchronous chunk body: fresh `JsJobRunner` + QuickJS context, prime
/// files + chunk slice injected as `jobParams.testFiles`, priming
/// prelude, `[chunk k/N]` console attribution. The chunk runs in a
/// disposable copy of the agents tree (see the library docs) unless
/// `DMTOOLS_SUITE_ISOLATED_COPIES=0`. Never rethrows — a crash becomes
/// a crashed outcome.
ShardOutcome _runChunkSync(ShardInvocation chunk) {
  if (!_copiesEnabled()) return _evalChunk(chunk);
  final copyRoot =
      Directory.systemTemp.createTempSync('dmtools-suite-chunk-').path;
  try {
    final copyWatch = Stopwatch()..start();
    copyAgentTree(chunk.workingDirectory, copyRoot);
    final outcome = _evalChunk(_rebasedChunk(chunk, copyRoot));
    _logChunkTiming(chunk, copyWatch, label: 'copy+run');
    return outcome;
  } catch (e) {
    return ShardOutcome.crashed(chunk.index, '$e');
  } finally {
    Directory(copyRoot).deleteSync(recursive: true);
  }
}

/// One stderr timing line per chunk — wall-clock attribution for CI
/// (chunk ends alone don't show when a chunk started or how long the
/// tree copy took).
void _logChunkTiming(ShardInvocation chunk, Stopwatch copyWatch,
    {required String label}) {
  final secs = (copyWatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
  stderr.writeln(
    '[chunk ${chunk.index + 1}/${chunk.total}] ⏱ $label took ${secs}s',
  );
}

/// Whether chunks get disposable tree copies (on unless explicitly
/// disabled via `DMTOOLS_SUITE_ISOLATED_COPIES=0`).
bool _copiesEnabled() =>
    Platform.environment['DMTOOLS_SUITE_ISOLATED_COPIES'] != '0';

/// The chunk with every [ShardInvocation.workingDirectory]-rooted path
/// rebased onto [copyRoot] (script, working dir, absolute job params).
ShardInvocation _rebasedChunk(ShardInvocation chunk, String copyRoot) {
  return ShardInvocation(
    index: chunk.index,
    total: chunk.total,
    scriptPath:
        rebasePath(chunk.scriptPath, chunk.workingDirectory, copyRoot) ??
            chunk.scriptPath,
    jobParams:
        rebaseJobParams(chunk.jobParams, chunk.workingDirectory, copyRoot),
    workingDirectory: copyRoot,
    preludeCode: chunk.preludeCode,
  );
}

/// Recursively copies the agents tree [source] → [destination].
///
/// Skips `.dart_tool` (never read by the suite) and symlinks (none in
/// a plain checkout). `.git` is never copied as data: the copy gets a
/// one-line `.git` gitfile pointing at the ORIGINAL git dir by absolute
/// path (see [_writeGitFileRef]) so the read-only git commands the
/// suite really runs — `git ls-files` in `test_agentDocsCoverage.js`
/// and `test_agentValidator.js` — answer from the original index, while
/// the worktree they see is the copy. Every other git call in the suite
/// is a mocked tool.
void copyAgentTree(String source, String destination) {
  const skipDirs = {'.dart_tool'};
  for (final entity in Directory(source).listSync(followLinks: false)) {
    // Directory URIs end in '/', so the raw last pathSegment is '' —
    // filter empties before taking the name.
    final name =
        entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    final target = '$destination/$name';
    if (entity is Directory) {
      if (name == '.git') {
        _writeGitFileRef(entity, target);
      } else if (!skipDirs.contains(name)) {
        Directory(target).createSync();
        copyAgentTree(entity.path, target);
      }
    } else if (name == '.git') {
      // The source itself is a submodule-style gitfile — re-point it.
      _writeGitFileRef(entity, target);
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// Writes [destination] as a `.git` gitfile redirecting git to the
/// ORIGINAL repository metadata ([gitEntity] being the source's `.git`
/// — either a real directory, or itself a gitfile whose `gitdir:` may
/// be relative, e.g. a submodule's `../.git/modules/agents`).
void _writeGitFileRef(FileSystemEntity gitEntity, String destination) {
  var gitDir = gitEntity.path;
  if (gitEntity is File) {
    final raw = gitEntity.readAsStringSync().trim();
    const marker = 'gitdir:';
    if (!raw.startsWith(marker)) return;
    gitDir = raw.substring(marker.length).trim();
  }
  // Absolute always: a relative gitdir would dangle once the copy lives
  // in the system temp dir (CI passes `agents` as a relative path).
  if (!gitDir.startsWith('/')) {
    final base = Directory(gitEntity.parent.path).absolute.path;
    gitDir = '$base/$gitDir';
  }
  File(destination).writeAsStringSync('gitdir: $gitDir\n');
}

/// [path] re-based from the [from] root onto [to], or null when [path]
/// does not live under [from].
String? rebasePath(String path, String from, String to) {
  if (path == from) return to;
  final prefix = '$from/';
  return path.startsWith(prefix)
      ? '$to/${path.substring(prefix.length)}'
      : null;
}

/// Deep-copies [params], re-basing every [agentsRoot]-rooted string
/// (maps and lists included) onto [copyRoot]. Relative paths such as
/// `testFiles` entries are left untouched.
Map<String, dynamic> rebaseJobParams(
  Map<String, dynamic> params,
  String agentsRoot,
  String copyRoot,
) {
  return _rebaseValue(params, agentsRoot, copyRoot) as Map<String, dynamic>;
}

dynamic _rebaseValue(dynamic value, String from, String to) {
  if (value is String) return rebasePath(value, from, to) ?? value;
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _rebaseValue(entry.value, from, to),
    };
  }
  if (value is List) {
    return <dynamic>[for (final item in value) _rebaseValue(item, from, to)];
  }
  return value;
}

/// Evaluates the chunk in its own `JsJobRunner` — the part after any
/// tree copy/rebase has happened.
ShardOutcome _evalChunk(ShardInvocation chunk) {
  final prefix = '[chunk ${chunk.index + 1}/${chunk.total}] ';
  final fileCount = (chunk.jobParams['testFiles'] as List?)?.length ?? 0;
  stderr.writeln('$prefix▶ start ($fileCount files to eval)');
  try {
    final result = const JsJobRunner().runScript(
      scriptPath: chunk.scriptPath,
      jobParams: chunk.jobParams,
      workingDirectory: chunk.workingDirectory,
      config: JsRunConfig(
        consolePrefix: prefix,
        preActionCode: chunk.preludeCode,
      ),
    );
    return ShardOutcome(index: chunk.index, result: result);
  } catch (e) {
    return ShardOutcome.crashed(chunk.index, '$e');
  }
}
