/// Executes a CliAgent job — Dart port of Java `CliAgent`.
///
/// Lifecycle (exact order, mirrors Java `CliAgent.runJobImpl`):
/// ```text
/// setup → preJSAction → preCliJSAction → cliCommands → postJSAction →
/// cache → reset (always runs, even on failure)
/// ```
///
/// Script hooks (`setup`/`cache`/`reset`) run as shell commands unless the
/// path ends with `.js` — then they execute via [JsJobRunner]. JS actions
/// (`preJSAction`/`preCliJSAction`/`postJSAction`) always run via
/// [JsJobRunner]. During the `cliCommands` phase, three further JS actions may
/// fire when configured: `timerJSAction` (periodic, plus a final tick),
/// `cliExecutionErrorJSAction` (on a non-zero exit), and `cliOutputLineJSAction`
/// (per output line; returning `true` stops the batch). Errors in hooks and
/// actions are caught and logged (the lifecycle continues); only CLI command
/// failures can fail the run.
library;

import 'dart:io';

import '../config/env_file_parser.dart';
import '../config/property_reader.dart';
import '../js/job_runner.dart';
import 'cli_agent_params.dart';
import 'cli_command_builder.dart';
import 'cli_execution_helper.dart';
import 'ticket_input_context_builder.dart';

/// Executes a CliAgent job — lightweight CLI-agent orchestrator.
///
/// Takes the CLI-execution parts of `Teammate` and removes the
/// tracker-ticket plumbing: runs cursor-agent / claude / copilot-style CLI
/// tools with aggregated prompts and optional setup/cache/reset hooks,
/// without needing an `inputJql` or a ticket system.
class CliAgent {
  /// Creates a CliAgent with the given [params].
  ///
  /// - [workingDirectory] — overrides `params.workingDirectory` when set.
  /// - [ticketData] — raw tracker ticket JSON for the input context; in a
  ///   real run this is fetched from Jira/ADO via the tracker client.
  /// - [propertyReader] — property resolution; defaults to a new reader.
  /// - [jsRunner] — JS execution engine; defaults to [JsJobRunner].
  CliAgent({
    required this.params,
    this.workingDirectory,
    this.ticketData,
    PropertyReader? propertyReader,
    JsJobRunner? jsRunner,
  })  : propertyReader = propertyReader ?? PropertyReader(),
        jsRunner = jsRunner ?? const JsJobRunner();

  /// Parameters from the job config.
  final CliAgentParams params;

  /// Working-directory override; when null, `params.workingDirectory` or
  /// the CWD is used.
  final String? workingDirectory;

  /// Raw tracker ticket JSON used to populate the input context.
  ///
  /// When null (no tracker configured), the input context folder is created
  /// empty — the ticket-agnostic behavior.
  final Map<String, dynamic>? ticketData;

  /// Property reader for environment resolution.
  final PropertyReader propertyReader;

  /// JS runner for `.js` actions and hooks.
  final JsJobRunner jsRunner;

  /// Result of the `cliCommands` phase — used by the reset hook.
  CliExecutionResult? _cliResult;

  /// Input context path — cleaned up in the finally block.
  String? _inputContextPath;

  /// Runs the full lifecycle. Returns a result map.
  ///
  /// - Success: `{'success': true, 'contextId': …, 'response': …}`
  /// - Failure: `{'success': false, 'error': …}`
  ///
  /// The reset hook and folder cleanup always run (in a `finally` block),
  /// mirroring the Java `runJobImpl` finally semantics.
  Future<Map<String, dynamic>> run() async {
    if (params.cliCommands.isEmpty) {
      return {'success': true, 'message': 'No cliCommands provided'};
    }
    final workDir = _resolveWorkingDirectory();
    PropertyReader.setOverrides(params.envVariables ?? {});
    try {
      return await _runLifecycle(workDir);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    } finally {
      PropertyReader.clearOverrides();
    }
  }

  /// Executes the main lifecycle phases inside [workDir].
  Future<Map<String, dynamic>> _runLifecycle(String workDir) async {
    String? response;
    try {
      _clearStaleOutputs(workDir);
      await _executeScriptHook('setup', params.setup, workDir, null);
      _executeJsAction('preJSAction', params.preJSAction, null, null, workDir);
      _inputContextPath = _createInputContext(workDir);
      _executeJsAction(
        'preCliJSAction',
        params.preCliJSAction,
        null,
        _inputContextPath,
        workDir,
      );
      response = await _executeCliCommands(workDir);
      _executeJsAction(
        'postJSAction',
        params.postJSAction,
        response,
        _inputContextPath,
        workDir,
      );
      await _executeScriptHook('cache', params.cache, workDir, response);
      return {
        'success': true,
        'contextId': params.contextId,
        'response': response,
      };
    } finally {
      await _executeScriptHook(
        'reset',
        params.reset,
        workDir,
        _cliResult != null ? _extractResponse(_cliResult!) : null,
      );
      _performCleanup(workDir);
    }
  }

  // ------------------------------------------------------------------
  // Script hooks (setup / cache / reset)
  // ------------------------------------------------------------------

  /// Executes a script hook: `.js` path via [JsJobRunner], else shell.
  ///
  /// Errors are caught and logged — the lifecycle continues (mirrors Java
  /// `executeScriptHook`).
  Future<void> _executeScriptHook(
    String name,
    String? script,
    String workDir,
    String? response,
  ) async {
    if (script == null || script.trim().isEmpty) return;
    try {
      if (script.endsWith('.js')) {
        jsRunner.runScript(
          scriptPath: script,
          jobParams: _buildJobParams(response, null),
          workingDirectory: workDir,
          config: JsRunConfig(
            extraGlobals: {'workingDirectory': workDir},
          ),
        );
      } else {
        await _runShell(script, workDir, applyEnvFilters: false);
      }
    } catch (e) {
      stderr.writeln('$name hook failed, continuing: $e');
    }
  }

  /// Runs [command] as a shell command in [workDir].
  Future<void> _runShell(
    String command,
    String workDir, {
    required bool applyEnvFilters,
  }) async {
    final env = _buildSubprocessEnvironment(workDir, applyEnvFilters);
    await Process.run(
      '/bin/sh',
      ['-c', command.trim()],
      workingDirectory: workDir,
      environment: env,
    );
  }

  // ------------------------------------------------------------------
  // JS actions (preJSAction / preCliJSAction / postJSAction)
  // ------------------------------------------------------------------

  /// Executes a JS action via [JsJobRunner] with context bindings.
  ///
  /// Errors are caught and logged — the lifecycle continues (mirrors Java
  /// `executeJsAction`).
  void _executeJsAction(
    String name,
    String? actionPath,
    String? response,
    String? inputFolderPath,
    String workDir,
  ) {
    if (actionPath == null || actionPath.trim().isEmpty) return;
    try {
      jsRunner.runScript(
        scriptPath: actionPath,
        jobParams: _buildJobParams(response, inputFolderPath),
        workingDirectory: workDir,
        config: JsRunConfig(
          extraGlobals: _buildExtraGlobals(response, inputFolderPath, workDir),
        ),
      );
    } catch (e) {
      stderr.writeln('$name failed, continuing: $e');
    }
  }

  // ------------------------------------------------------------------
  // CLI command phase
  // ------------------------------------------------------------------

  /// Builds and executes CLI commands, returning the extracted response.
  ///
  /// When any of `timerJSAction`, `cliExecutionErrorJSAction`, or
  /// `cliOutputLineJSAction` is configured, commands run through the monitored
  /// path ([CliExecutionHelper.executeCommandsWithCallbacks]) so the hooks fire
  /// periodically / per-line / on error. Otherwise the buffered path is used.
  Future<String> _executeCliCommands(String workDir) async {
    final builder = const CliCommandBuilder();
    final finalCommands = builder.buildCommands(
      params.cliCommands,
      params.cliPrompt,
      params.cliPromptsAsArray,
      params.cliPromptsByTracker,
      workingDirectory: workDir,
    );
    _ensureOutputFolder(workDir);
    final env = _buildSubprocessEnvironment(workDir, true);
    final live = LiveCliOutput();
    final callbacks = _buildCliCallbacks(workDir, live);
    final helper = const CliExecutionHelper();
    _cliResult = callbacks == null
        ? await helper.executeCommands(
            finalCommands,
            workingDirectory: workDir,
            environment: env,
          )
        : await helper.executeCommandsWithCallbacks(
            finalCommands,
            workingDirectory: workDir,
            environment: env,
            callbacks: callbacks,
          );
    return _extractResponse(_cliResult!);
  }

  // ------------------------------------------------------------------
  // Context JS actions (timer / error / line)
  // ------------------------------------------------------------------

  /// Builds CLI-execution callbacks for the timer/error/line JS actions, or
  /// `null` when none are configured.
  CliExecutionCallbacks? _buildCliCallbacks(
    String workDir,
    LiveCliOutput live,
  ) {
    final timer = _buildTimerAction(workDir, live);
    final error = _buildErrorHandler(workDir, live);
    final stop = _buildLineStopPredicate(workDir, live);
    if (timer == null && error == null && stop == null) return null;
    return CliExecutionCallbacks(
      timerAction: timer,
      timerIntervalSeconds: params.timerIntervalSeconds,
      errorHandler: error,
      lineStopPredicate: stop,
      liveOutput: live,
    );
  }

  /// Builds the periodic timer callback (Java `buildTimerRunnable`).
  void Function()? _buildTimerAction(String workDir, LiveCliOutput live) {
    final action = params.timerJSAction;
    if (action == null || action.trim().isEmpty) return null;
    return () => _runContextJsAction(
          'timerJSAction',
          action,
          workDir,
          {'currentCliOutput': live.value},
        );
  }

  /// Builds the CLI-failure callback (Java `buildErrorHandler`).
  void Function(String)? _buildErrorHandler(
      String workDir, LiveCliOutput live) {
    final action = params.cliExecutionErrorJSAction;
    if (action == null || action.trim().isEmpty) return null;
    return (String errorMessage) => _runContextJsAction(
          'cliExecutionErrorJSAction',
          action,
          workDir,
          {'errorMessage': errorMessage, 'currentCliOutput': live.value},
        );
  }

  /// Builds the per-line stop predicate (Java `buildLineStopPredicate`).
  bool Function(String)? _buildLineStopPredicate(
    String workDir,
    LiveCliOutput live,
  ) {
    final action = params.cliOutputLineJSAction;
    if (action == null || action.trim().isEmpty) return null;
    return (String line) {
      final result = _runContextJsAction(
        'cliOutputLineJSAction',
        action,
        workDir,
        {'line': line, 'currentCliOutput': live.value},
      );
      return result?.toLowerCase() == 'true';
    };
  }

  /// Runs a context JS action via [JsJobRunner], injecting [context] globals.
  ///
  /// Returns the JSON-serialized result (for line-stop boolean parsing).
  /// Errors are caught and logged — the lifecycle continues — mirroring the
  /// Java `executeJsAction` / `buildLineStopPredicate` swallow-and-continue
  /// contract.
  String? _runContextJsAction(
    String name,
    String actionPath,
    String workDir,
    Map<String, dynamic> context,
  ) {
    try {
      return jsRunner.runScript(
        scriptPath: actionPath,
        jobParams: _buildJobParams(null, null),
        workingDirectory: workDir,
        config: JsRunConfig(
          extraGlobals: _mergeContextGlobals(context, workDir),
        ),
      );
    } catch (e) {
      stderr.writeln('$name failed, continuing: $e');
      return null;
    }
  }

  /// Merges the standard JS action globals with action-specific [context].
  Map<String, dynamic> _mergeContextGlobals(
    Map<String, dynamic> context,
    String workDir,
  ) {
    return {..._buildExtraGlobals(null, null, workDir), ...context};
  }

  /// Extracts the response from the CLI result.
  ///
  /// Mirrors Java `extractResponse`: `requireCliOutputFile` turns a missing
  /// output file into an error; the output file content is preferred;
  /// command responses are the fallback.
  String _extractResponse(CliExecutionResult result) {
    if (params.requireCliOutputFile && !result.hasOutputResponse) {
      return 'CLI command executed but did not produce output file:\n'
          '${result.commandResponses}';
    }
    if (result.hasOutputResponse) {
      return result.outputResponse!;
    }
    return result.commandResponses;
  }

  // ------------------------------------------------------------------
  // Environment
  // ------------------------------------------------------------------

  /// Builds the subprocess environment.
  ///
  /// Starts from the OS env, overlays `dmtools.env` from [workDir], then
  /// the per-job `envVariables` overrides. When [applyEnvFilters] is true,
  /// the `excludedEnvVariables`/`excludeEnvVariablesByRegex` filters are
  /// applied (CLI command phase only — script hooks do not filter).
  Map<String, String> _buildSubprocessEnvironment(
    String workDir,
    bool applyEnvFilters,
  ) {
    var env = <String, String>{}
      ..addAll(Platform.environment)
      ..addAll(parseEnvFile('$workDir/dmtools.env'))
      ..addAll(PropertyReader.getOverrides());
    if (applyEnvFilters) {
      env = CliExecutionHelper.filterEnvVariables(
        env,
        params.excludedEnvVariables,
        params.excludeEnvVariablesByRegex,
      );
    }
    return env;
  }

  // ------------------------------------------------------------------
  // Filesystem operations
  // ------------------------------------------------------------------

  /// Resolves the working directory (param → existing dir → CWD).
  String _resolveWorkingDirectory() {
    final candidate = workingDirectory ?? params.workingDirectory;
    if (candidate != null && candidate.trim().isNotEmpty) {
      final dir = Directory(candidate);
      if (dir.existsSync()) {
        return dir.absolute.path;
      }
    }
    return Directory.current.absolute.path;
  }

  /// Deletes stale `outputs/response.md` and `output/response.md`.
  void _clearStaleOutputs(String workDir) {
    _deleteFileIfPresent(File('$workDir/outputs/$responseFileName'));
    _deleteFileIfPresent(File('$workDir/output/$responseFileName'));
  }

  /// Deletes [file] when it exists; errors are ignored.
  void _deleteFileIfPresent(File file) {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  /// Creates the input context folder: `input/<contextId>/`.
  ///
  /// When [ticketData] is set (fetched from a tracker), the folder is
  /// populated with `ticket.md`, `ticket.json`, `subtasks/`, and
  /// `comments.md` via [TicketInputContextBuilder]. Otherwise an empty folder
  /// is created — the ticket-agnostic behavior.
  String _createInputContext(String workDir) {
    return TicketInputContextBuilder(workDir).build(
      params.contextId,
      ticketData: ticketData,
    );
  }

  /// Ensures the `outputs/` folder exists before CLI commands run.
  void _ensureOutputFolder(String workDir) {
    Directory('$workDir/outputs').createSync(recursive: true);
  }

  /// Cleans up the input and outputs folders per params flags.
  ///
  /// Mirrors the Java `finally` block cleanup logic.
  void _performCleanup(String workDir) {
    final inputPath = _inputContextPath;
    if (inputPath != null && params.cleanupInputFolder) {
      _deleteDirectory(Directory(inputPath));
    }
    if (params.cleanupOutputsFolder) {
      _deleteDirectory(Directory('$workDir/outputs'));
      _deleteDirectory(Directory('$workDir/output'));
    }
  }

  /// Recursively deletes [dir] if it exists.
  void _deleteDirectory(Directory dir) {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  // ------------------------------------------------------------------
  // JS context building
  // ------------------------------------------------------------------

  /// Builds the job-params map passed as `params.jobParams` to JS actions.
  Map<String, dynamic> _buildJobParams(
    String? response,
    String? inputFolderPath,
  ) {
    return {
      'cliCommands': params.cliCommands,
      if (params.cliPrompt != null) 'cliPrompt': params.cliPrompt,
      if (params.contextId.isNotEmpty) 'contextId': params.contextId,
      if (response != null) 'response': response,
      if (inputFolderPath != null) 'inputFolderPath': inputFolderPath,
    };
  }

  /// Builds the extra top-level JS globals for JS actions.
  ///
  /// Mirrors Java `prepareJsExecutor` `.with()` bindings.
  Map<String, dynamic> _buildExtraGlobals(
    String? response,
    String? inputFolderPath,
    String workDir,
  ) {
    return {
      if (response != null) 'response': response,
      if (inputFolderPath != null) 'inputFolderPath': inputFolderPath,
      'workingDirectory': workDir,
      if (params.customParams != null) 'customParams': params.customParams,
    };
  }
}
