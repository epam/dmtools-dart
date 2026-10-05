/// `dmtools compile` — builds a versioned agent pack — Dart port of the
/// Java `CompileCommand` (dm.ai #595).
///
/// Parses `entry.json` plus `--agent-root` / `--version` /
/// `--versions-file` / `--out` / `--source-commit` and delegates to
/// [AgentPackCompiler]. Extracted from [CliDispatcher] (mirrors
/// [DoctorCommand]) to keep the dispatcher under its file-size gate.
library;

import 'dart:convert';
import 'dart:io';

import '../compile/agent_pack_compiler.dart';

/// Builds a versioned, self-contained agent pack (zip + manifest +
/// sha256).
class CompileCommand {
  /// Creates the command.
  ///
  /// [writer] receives every output line (defaults to `print`) — the
  /// dispatcher injects its own writer so command output flows through
  /// one channel.
  CompileCommand({void Function(String line)? writer})
      : _writer = writer ?? print;

  final void Function(String line) _writer;

  /// Runs `compile` with [rest] (the argv after the command name) and
  /// returns the exit code (`0` on success, `1` on any guard or build
  /// failure).
  int run(List<String> rest) {
    final guardExit = _guardExit(rest);
    if (guardExit != null) return guardExit;
    final agentName = _stripJsonExtension(_basename(rest.first));
    final agentRoot =
        _optionValue(rest, '--agent-root') ?? _dirname(rest.first);
    final version = _resolveVersion(rest, agentName);
    if (version == null) {
      _writer(
          'Error: --version <semver> or --versions-file versions.json is required');
      return 1;
    }
    try {
      final result = AgentPackCompiler(agentRoot).compile(
          File(rest.first),
          version,
          _optionValue(rest, '--source-commit') ??
              _detectSourceCommit(agentRoot),
          Directory(_optionValue(rest, '--out') ?? 'dist'),
          extraDirs: _optionValues(rest, '--include'));
      _printResult(agentName, version, result);
      return 0;
    } on AgentPackException catch (e) {
      _writer('Error: ${e.message}');
      return 1;
    }
  }

  /// Handles the help/usage and missing-entry guard cases; returns the exit
  /// code to short-circuit with, or `null` to proceed with the build.
  int? _guardExit(List<String> rest) {
    if (rest.isEmpty || rest.first == '--help' || rest.first == '-h') {
      _writer(_usage);
      return rest.isEmpty ? 1 : 0;
    }
    if (!File(rest.first).existsSync()) {
      _writer('Error: entry config not found: ${rest.first}');
      return 1;
    }
    return null;
  }

  /// Version precedence: explicit `--version`, else the agent's versions.json entry.
  String? _resolveVersion(List<String> rest, String agentName) =>
      _optionValue(rest, '--version') ??
      _versionFromFile(_optionValue(rest, '--versions-file'), agentName);

  /// Prints the successful compile summary.
  void _printResult(String agentName, String version, PackResult result) {
    _writer('Agent pack built successfully:');
    _writer('  agent:    $agentName');
    _writer('  version:  $version');
    _writer('  files:    ${result.fileCount}');
    _writer('  zip:      ${result.zipFile.path}');
    _writer('  manifest: ${result.manifestFile.path}');
    _writer('  sha256:   ${result.shaFile.path}');
  }

  static const String _usage = '''
Usage: dmtools compile <entry.json> [options]

Build a versioned, self-contained agent pack (zip + manifest + sha256).

Options:
  --agent-root <dir>             Agents checkout root (default: entry.json's directory)
  --version <semver>             Pack version (required unless --versions-file)
  --versions-file versions.json  Per-agent versions map
  --out <dir>                    Output directory (default: ./dist)
  --source-commit <sha>          Source commit (default: git rev-parse HEAD)
  --include <dir>                Embed a whole repo-relative dir (repeatable; for files only `pack:`-consuming children reference)
''';

  /// Reads the agent's version from a `versions.json` map; `null` when absent.
  String? _versionFromFile(String? versionsFile, String agentName) {
    if (versionsFile == null) return null;
    final file = File(versionsFile);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        final version = decoded[agentName];
        return version is String ? version : null;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Best-effort source commit: `git rev-parse HEAD` in the agent root.
  String _detectSourceCommit(String agentRoot) {
    try {
      final result = Process.runSync('git', ['rev-parse', 'HEAD'],
          workingDirectory: agentRoot);
      final out = (result.stdout as String).trim();
      if (result.exitCode == 0 && out.isNotEmpty) return out;
    } on Object {
      // fall through — git unavailable or not a repo
    }
    return 'unknown';
  }

  String? _optionValue(List<String> args, String flag) {
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == flag) return args[i + 1];
    }
    return null;
  }

  /// All values of a repeatable option flag (e.g. `--include`), in order.
  List<String> _optionValues(List<String> args, String flag) {
    final values = <String>[];
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == flag) values.add(args[i + 1]);
    }
    return values;
  }

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

  String _dirname(String path) {
    final idx = path.replaceAll('\\', '/').lastIndexOf('/');
    return idx >= 0 ? path.substring(0, idx) : '.';
  }

  String _stripJsonExtension(String fileName) => fileName.endsWith('.json')
      ? fileName.substring(0, fileName.length - '.json'.length)
      : fileName;
}
