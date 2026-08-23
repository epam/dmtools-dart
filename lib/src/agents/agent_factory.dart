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

/// Minimal JSRunner job — runs a JS script via [JsJobRunner].
///
/// Mirrors the Java `JSRunner.runJobImpl` contract: resolves the script
/// (`jsPath` — file, inline code, or URL), forwards the job context
/// (`jobParams`, `ticket`, `response`, `initiator`, `inputJql`,
/// `metadata`) into the JS `params` object exactly as
/// `JavaScriptExecutor.withJobContext()` / `.with()` do, calls the script's
/// `action(params)`, and returns the result. JS execution failures become
/// `{'success': false, 'error': …}` results (Java
/// `JavaScriptExecutor.execute()` swallows exceptions into an error result
/// instead of failing the job).
class JsRunnerJob {
  /// Creates a JSRunner job from the `params` block.
  JsRunnerJob(this.params);

  /// The raw params from the job config.
  final Map<String, dynamic> params;

  /// Runs the JS script and returns the result.
  Map<String, dynamic> run() {
    final jsPath = params['jsPath'] as String?;
    if (jsPath == null || jsPath.trim().isEmpty) {
      // Java: IllegalArgumentException("jsPath parameter is required").
      return {'success': false, 'error': 'jsPath parameter is required'};
    }
    try {
      final result = const JsJobRunner().runScript(
        scriptPath: jsPath,
        jobParams: _parseJobParams(params['jobParams']),
        ticket: _asMap(params['ticket']),
        config: JsRunConfig(contextParams: _contextParams()),
      );
      return {'success': true, 'result': result};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Builds the extra `params.*` context entries (Java `.with()` calls).
  ///
  /// Null-valued fields are omitted — Java `JSONObject.put(key, null)`
  /// removes the key, and `JSRunner` guards `inputJql`/`metadata` on null.
  Map<String, dynamic> _contextParams() {
    return {
      if (params['response'] != null) 'response': params['response'],
      if (params['initiator'] != null) 'initiator': params['initiator'],
      if (params['inputJql'] != null) 'inputJql': params['inputJql'],
      if (params['metadata'] != null) 'metadata': params['metadata'],
    };
  }

  /// Extracts the `jobParams` block (defaults to an empty map).
  Map<String, dynamic> _parseJobParams(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return const {};
  }

  /// Coerces a raw JSON value to a map when possible.
  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }
}
