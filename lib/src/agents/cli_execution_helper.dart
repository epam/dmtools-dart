/// CLI command execution helper — Dart port of Java `CliExecutionHelper`.
///
/// Handles environment-variable filtering, subprocess execution, and output
/// response extraction. Used by [CliAgent] for the `cliCommands` phase.
library;

import 'dart:io';

/// The output response file name (both folders use the same file).
const String responseFileName = 'response.md';

/// Folder preference when reading the output response.
enum OutputFolderPreference {
  /// Check `output/` first, then `outputs/`.
  legacyOutputFirst,

  /// Check `outputs/` first, then `output/`.
  outputsFirst,
}

/// Result container for a CLI command batch.
class CliExecutionResult {
  /// Creates a result with accumulated [commandResponses] and optional
  /// [outputResponse].
  CliExecutionResult({
    required this.commandResponses,
    this.outputResponse,
    this.hasFatalError = false,
    this.lastExitCode,
    this.lastErrorMessage,
  });

  /// Accumulated stdout/stderr from all commands.
  final String commandResponses;

  /// Content of `outputs/response.md` (or legacy `output/response.md`).
  final String? outputResponse;

  /// True if any command failed with a non-zero exit code.
  final bool hasFatalError;

  /// Exit code of the last failing command, or null.
  final int? lastExitCode;

  /// Error message from the last failing command, or null.
  final String? lastErrorMessage;

  /// Returns true when [outputResponse] is non-null and non-empty.
  bool get hasOutputResponse =>
      outputResponse != null && outputResponse!.trim().isNotEmpty;
}

/// Executes CLI commands with environment filtering and output collection.
class CliExecutionHelper {
  /// Creates a helper.
  const CliExecutionHelper();

  // ------------------------------------------------------------------
  // Environment filtering
  // ------------------------------------------------------------------

  /// Filters [envVars] by removing exact-name and regex-matched keys.
  ///
  /// Returns a new map. When both filters are null/empty, returns the
  /// original map unchanged.
  ///
  /// Mirrors `CliExecutionHelper.filterEnvVariables()`.
  static Map<String, String> filterEnvVariables(
    Map<String, String> envVars,
    List<String>? excludedEnvVariables,
    List<String>? excludedEnvRegexes,
  ) {
    if (envVars.isEmpty) return envVars;

    final exact = _buildExactExclusions(excludedEnvVariables);
    final regexes = _compileRegexes(excludedEnvRegexes);
    if (exact.isEmpty && regexes.isEmpty) return envVars;

    return _applyFilters(envVars, exact, regexes);
  }

  static Set<String> _buildExactExclusions(List<String>? names) {
    if (names == null) return const {};
    return names.where((n) => n.trim().isNotEmpty).toSet();
  }

  static List<RegExp> _compileRegexes(List<String>? patterns) {
    if (patterns == null) return const [];
    return patterns
        .where((p) => p.trim().isNotEmpty)
        .map((p) => RegExp(p))
        .toList();
  }

  static Map<String, String> _applyFilters(
    Map<String, String> envVars,
    Set<String> exact,
    List<RegExp> regexes,
  ) {
    final filtered = <String, String>{};
    for (final entry in envVars.entries) {
      if (exact.contains(entry.key)) continue;
      if (regexes.any((r) => r.hasMatch(entry.key))) continue;
      filtered[entry.key] = entry.value;
    }
    return filtered;
  }

  // ------------------------------------------------------------------
  // Command execution
  // ------------------------------------------------------------------

  /// Executes [commands] sequentially, accumulating output.
  ///
  /// Each command is run via `/bin/sh -c` to allow arbitrary shell syntax.
  /// [workingDirectory] sets the subprocess CWD. [environment] replaces the
  /// inherited OS env when non-null.
  ///
  /// Returns a [CliExecutionResult] with accumulated responses and the
  /// output response file content (if present).
  Future<CliExecutionResult> executeCommands(
    List<String> commands, {
    String? workingDirectory,
    Map<String, String>? environment,
    OutputFolderPreference preference = OutputFolderPreference.outputsFirst,
  }) async {
    final responses = StringBuffer();
    var hasFatal = false;
    int? exitCode;
    String? errorMsg;

    for (final command in commands) {
      if (command.trim().isEmpty) continue;
      final result = await _runOne(command, workingDirectory, environment);
      responses.write('CLI Command: $command\n');
      if (result.exitCode != 0) {
        responses.write('Error: ${result.stderr}\n\n');
        hasFatal = true;
        exitCode = result.exitCode;
        errorMsg = result.stderr.toString();
      } else {
        responses.write('Response:\n${result.stdout}\n\n');
      }
    }

    final outputResponse = readOutputResponse(workingDirectory, preference);
    return CliExecutionResult(
      commandResponses: responses.toString(),
      outputResponse: outputResponse,
      hasFatalError: hasFatal,
      lastExitCode: exitCode,
      lastErrorMessage: errorMsg,
    );
  }

  /// Runs a single shell command.
  Future<ProcessResult> _runOne(
    String command,
    String? workingDirectory,
    Map<String, String>? environment,
  ) {
    return Process.run(
      '/bin/sh',
      ['-c', command.trim()],
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  // ------------------------------------------------------------------
  // Output response
  // ------------------------------------------------------------------

  /// Reads the output response file relative to [workingDirectory].
  ///
  /// Checks the folder determined by [preference] first, then falls back
  /// to the other. Returns null when neither file exists or is empty.
  ///
  /// Mirrors `CliExecutionHelper.processOutputResponse()`.
  String? readOutputResponse(
    String? workingDirectory,
    OutputFolderPreference preference,
  ) {
    final base = workingDirectory ?? Directory.current.path;
    final outputsFile = File('$base/outputs/$responseFileName');
    final legacyFile = File('$base/output/$responseFileName');
    final primary = preference == OutputFolderPreference.outputsFirst
        ? outputsFile
        : legacyFile;
    final fallback = preference == OutputFolderPreference.outputsFirst
        ? legacyFile
        : outputsFile;
    return _readFile(primary) ?? _readFile(fallback);
  }

  String? _readFile(File file) {
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    if (content.trim().isEmpty) return null;
    return content;
  }
}
