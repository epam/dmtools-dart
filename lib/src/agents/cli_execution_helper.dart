/// CLI command execution helper — Dart port of Java `CliExecutionHelper`.
///
/// Handles environment-variable filtering, subprocess execution, and output
/// response extraction. Used by [CliAgent] for the `cliCommands` phase.
library;

import 'dart:async';
import 'dart:convert';
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

/// Mutable holder for the live CLI-output snapshot.
///
/// Dart port of the Java `AtomicReference<String> liveOutput`: updated after
/// every output line and after each command so a concurrent timer JS action
/// can observe partial output.
class LiveCliOutput {
  /// Current accumulated output snapshot.
  String value = '';
}

/// Hooks for monitored CLI execution.
///
/// Dart port of the Java `executeCliCommandsWithResult` overload that accepts a
/// timer action, an error handler, and a per-line stop predicate. When any hook
/// is set, [CliExecutionHelper.executeCommandsWithCallbacks] streams each
/// command's merged stdout/stderr line-by-line instead of buffering.
class CliExecutionCallbacks {
  /// Creates a callbacks bundle.
  const CliExecutionCallbacks({
    this.timerAction,
    required this.timerIntervalSeconds,
    this.errorHandler,
    this.lineStopPredicate,
    this.liveOutput,
  });

  /// Fired every [timerIntervalSeconds] during execution and once more after
  /// the batch completes (final tick).
  final void Function()? timerAction;

  /// Seconds between timer firings; no timer when `<= 0`.
  final int timerIntervalSeconds;

  /// Invoked with the formatted error message when a command exits non-zero.
  final void Function(String errorMessage)? errorHandler;

  /// Invoked per output line; returning `true` kills the process and aborts
  /// the remaining command batch.
  final bool Function(String line)? lineStopPredicate;

  /// Shared live-output snapshot updated after each line/command.
  final LiveCliOutput? liveOutput;

  /// True when at least one hook is configured.
  bool get hasHooks =>
      timerAction != null || errorHandler != null || lineStopPredicate != null;
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
  // Monitored execution (timer / error / line hooks)
  // ------------------------------------------------------------------

  /// Executes [commands] with optional timer/error/line [callbacks].
  ///
  /// When [callbacks] has no hooks, delegates to [executeCommands]. Otherwise
  /// each command is streamed line-by-line (stdout+stderr merged, mirroring the
  /// Java `redirectErrorStream` behaviour) so [CliExecutionCallbacks.lineStopPredicate]
  /// can stop mid-output; a background [Timer] fires [CliExecutionCallbacks.timerAction]
  /// periodically and once more after the batch (final tick). Port of Java
  /// `executeCliCommandsWithResult`.
  Future<CliExecutionResult> executeCommandsWithCallbacks(
    List<String> commands, {
    String? workingDirectory,
    Map<String, String>? environment,
    CliExecutionCallbacks? callbacks,
    OutputFolderPreference preference = OutputFolderPreference.outputsFirst,
  }) async {
    if (callbacks == null || !callbacks.hasHooks) {
      return executeCommands(
        commands,
        workingDirectory: workingDirectory,
        environment: environment,
        preference: preference,
      );
    }
    final timer = _startTimer(callbacks);
    try {
      final outcome = await _runMonitoredBatch(
        commands,
        workingDirectory,
        environment,
        callbacks,
      );
      return CliExecutionResult(
        commandResponses: outcome.responses,
        outputResponse: readOutputResponse(workingDirectory, preference),
        hasFatalError: outcome.hasFatal,
        lastExitCode: outcome.exitCode,
        lastErrorMessage: outcome.errorMsg,
      );
    } finally {
      timer?.cancel();
      if (callbacks.timerAction != null) callbacks.timerAction!();
    }
  }

  /// Starts the periodic timer for [cb], or `null` when disabled.
  Timer? _startTimer(CliExecutionCallbacks cb) {
    final action = cb.timerAction;
    if (action == null || cb.timerIntervalSeconds <= 0) return null;
    return Timer.periodic(
      Duration(seconds: cb.timerIntervalSeconds),
      (_) {
        try {
          action();
        } catch (e) {
          stderr.writeln('timerJSAction threw (ignored): $e');
        }
      },
    );
  }

  /// Runs the full command batch with monitoring, returning the accumulated
  /// responses and the last fatal-error signal.
  Future<_BatchOutcome> _runMonitoredBatch(
    List<String> commands,
    String? workDir,
    Map<String, String>? env,
    CliExecutionCallbacks cb,
  ) async {
    final responses = StringBuffer();
    var hasFatal = false;
    int? lastExit;
    String? lastErr;
    for (final command in commands) {
      if (command.trim().isEmpty) continue;
      responses.write('CLI Command: $command\n');
      final one = await _runStreamedCommand(
        command,
        workDir,
        env,
        responses,
        cb,
      );
      if (one.stopped) {
        responses.write(
          'Stopped: CLI execution stopped by line callback at line: '
          '${one.stopLine}\n\n',
        );
        break;
      }
      if (one.exitCode != 0) {
        hasFatal = true;
        lastExit = one.exitCode;
        final msg = 'Command failed (exit code ${one.exitCode}): $command\n'
            'Output:\n${one.output.trim()}';
        lastErr = msg;
        responses.write('Error: $msg\n\n');
        cb.errorHandler?.call(msg);
      } else {
        responses.write('Response:\n${one.output}\n\n');
      }
      final live = cb.liveOutput;
      if (live != null) live.value = responses.toString();
    }
    return _BatchOutcome(responses.toString(), hasFatal, lastExit, lastErr);
  }

  /// Streams one command's merged stdout/stderr line-by-line.
  ///
  /// Updates [CliExecutionCallbacks.liveOutput] after each line so a concurrent
  /// timer tick sees partial output. When the line-stop predicate returns
  /// `true`, the process is killed and execution stops.
  Future<_CommandOutcome> _runStreamedCommand(
    String command,
    String? workDir,
    Map<String, String>? env,
    StringBuffer responses,
    CliExecutionCallbacks cb,
  ) async {
    final proc = await Process.start(
      '/bin/sh',
      ['-c', '${command.trim()} 2>&1'],
      workingDirectory: workDir,
      environment: env,
    );
    final output = StringBuffer();
    var stopped = false;
    String? stopLine;
    await for (final line in proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      output.writeln(line);
      final live = cb.liveOutput;
      if (live != null) live.value = '$responses$output';
      if (cb.lineStopPredicate != null && cb.lineStopPredicate!(line)) {
        stopLine = line;
        stopped = true;
        proc.kill(ProcessSignal.sigkill);
        break;
      }
    }
    final code = await proc.exitCode;
    return _CommandOutcome(output.toString(), code, stopped, stopLine);
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

/// Accumulated result of a monitored command batch.
class _BatchOutcome {
  const _BatchOutcome(
    this.responses,
    this.hasFatal,
    this.exitCode,
    this.errorMsg,
  );

  final String responses;
  final bool hasFatal;
  final int? exitCode;
  final String? errorMsg;
}

/// Result of a single streamed command.
class _CommandOutcome {
  const _CommandOutcome(
    this.output,
    this.exitCode,
    this.stopped,
    this.stopLine,
  );

  final String output;
  final int exitCode;
  final bool stopped;
  final String? stopLine;
}
