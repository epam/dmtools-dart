/// Creates job instances by name — Dart port of Java
/// `JobRunner.createJobInstance()`.
///
/// Matches the Java dispatch switch: names are matched case-insensitively,
/// and each name returns a fully constructed job instance ready to run.
library;

import '../js/job_runner.dart';
import 'cli_agent.dart';
import 'cli_agent_params.dart';

/// Creates job instances by name (case-insensitive).
///
/// Currently supported:
/// - `cliagent` → [CliAgent]
/// - `jsrunner` → [JsRunnerJob]
///
/// Throws [ArgumentError] for unknown job names.
class AgentFactory {
  /// Creates a job instance for [name] using [params].
  ///
  /// [name] is matched case-insensitively. [params] is the `params` block
  /// from the job config JSON.
  static dynamic create(String name, Map<String, dynamic> params) {
    switch (name.toLowerCase()) {
      case 'cliagent':
        return CliAgent(params: CliAgentParams.fromJson(params));
      case 'jsrunner':
        return JsRunnerJob(params);
      default:
        throw ArgumentError('Unknown job: $name');
    }
  }
}

/// Minimal JSRunner job — runs a `.js` script via [JsJobRunner].
///
/// Mirrors the Java `JobJavaScriptBridge` (JSRunner) contract: evaluates the
/// script, calls its `action(params)` when defined, and returns the result.
class JsRunnerJob {
  /// Creates a JSRunner job from the `params` block.
  JsRunnerJob(this.params);

  /// The raw params from the job config.
  final Map<String, dynamic> params;

  /// Runs the JS script and returns the result.
  ///
  /// Expects `jsPath` and optional `jobParams` in [params].
  Map<String, dynamic> run() {
    final jsPath = params['jsPath'] as String?;
    if (jsPath == null) {
      return {'success': false, 'error': 'jsPath is required'};
    }
    final jobParams = _parseJobParams(params['jobParams']);
    final result = const JsJobRunner().runScript(
      scriptPath: jsPath,
      jobParams: jobParams,
    );
    return {'success': true, 'result': result};
  }

  /// Extracts the `jobParams` block (defaults to an empty map).
  Map<String, dynamic> _parseJobParams(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return const {};
  }
}
