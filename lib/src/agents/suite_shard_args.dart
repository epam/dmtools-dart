/// gh-315 — CLI flags of `bin/run_agents_suite.dart` (parsed here, thin
/// bin shell delegates).
///
/// Parsing is deliberately lenient: unknown or malformed input is recorded
/// in [problems] instead of throwing, so the runner can print every problem
/// to stderr and exit non-zero in one place (AC2: invalid flag combos exit
/// non-zero with a clear message).
library;

/// Parsed `run_agents_suite.dart` argv.
class SuiteShardArgs {
  /// Parsed args with any parse-level [problems] collected.
  const SuiteShardArgs({
    required this.agentsPath,
    required this.problems,
    this.shardIndex,
    this.totalShards,
    this.manifestOut,
  });

  /// dmtools-agents checkout root (positional; defaults to
  /// `/tmp/dmtools-agents` when absent — the historical default).
  final String agentsPath;

  /// Value of `--shard-index <i>` (null when the flag is absent or
  /// malformed — malformed input lands in [problems]).
  final int? shardIndex;

  /// Value of `--total-shards <n>` (null when absent or malformed).
  final int? totalShards;

  /// Value of `--manifest-out <path>` — where the shard manifest JSON is
  /// written (required for sharded runs).
  final String? manifestOut;

  /// Parse-level problems (unknown flag, non-integer value, stray
  /// positional). Empty when the argv is well-formed.
  final List<String> problems;

  /// Whether any shard flag was given at all — sharding is strictly
  /// opt-in; the no-flag invocation is the historical serial run (AC5).
  bool get isSharded =>
      shardIndex != null || totalShards != null || manifestOut != null;

  /// Parses raw argv: positional agents path plus the optional
  /// `--shard-index`, `--total-shards`, `--manifest-out` value flags
  /// (`--flag value` and `--flag=value` forms).
  factory SuiteShardArgs.parse(List<String> args) {
    var agentsPath = '/tmp/dmtools-agents';
    var positionalSeen = false;
    int? shardIndex;
    int? totalShards;
    String? manifestOut;
    final problems = <String>[];

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--shard-index' || arg.startsWith('--shard-index=')) {
        shardIndex = _intValue(
          _valueOf(args, i, problems),
          problems,
          '--shard-index',
        );
        if (!arg.contains('=')) i++; // space form consumed the next token
      } else if (arg == '--total-shards' || arg.startsWith('--total-shards=')) {
        totalShards = _intValue(
          _valueOf(args, i, problems),
          problems,
          '--total-shards',
        );
        if (!arg.contains('=')) i++;
      } else if (arg == '--manifest-out' || arg.startsWith('--manifest-out=')) {
        manifestOut = _valueOf(args, i, problems);
        if (!arg.contains('=')) i++;
      } else if (arg.startsWith('--')) {
        problems.add('unknown flag: $arg');
      } else if (!positionalSeen) {
        agentsPath = arg;
        positionalSeen = true;
      } else {
        problems.add('unexpected positional argument: $arg');
      }
    }
    return SuiteShardArgs(
      agentsPath: agentsPath,
      problems: problems,
      shardIndex: shardIndex,
      totalShards: totalShards,
      manifestOut: manifestOut,
    );
  }

  /// Value of the flag at [index]: the `=value` suffix or the next token.
  static String _valueOf(List<String> args, int index, List<String> problems) {
    final arg = args[index];
    final eq = arg.indexOf('=');
    if (eq >= 0) return arg.substring(eq + 1);
    if (index + 1 >= args.length) {
      problems.add('flag $arg requires a value');
      return '';
    }
    return args[index + 1];
  }

  static int? _intValue(
    String raw,
    List<String> problems,
    String flagName,
  ) {
    final value = int.tryParse(raw);
    if (value == null) {
      problems.add('$flagName expects an integer, got "$raw"');
    }
    return value;
  }
}
