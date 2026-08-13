/// Parameters for [CliAgent] — Dart port of Java `CliAgentParams`.
///
/// Extends the `TrackerParams` contract (outputType, envVariables, metadata,
/// preJSAction, postJSAction, ...) but does not require `inputJql`. The job
/// is designed to run CLI agents in a lightweight, ticket-agnostic mode.
///
/// Every key, type, and default matches the Java contract exactly — see
/// the parameter table in GOAL.md → Phase 5.
library;

/// Parameters for the [CliAgent] job.
///
/// Ported from Java `CliAgentParams` which extends `TrackerParams`.
/// The `cliPrompts` field accepts both a flat string array (backward
/// compatibility) and a structured config (array of strings and/or
/// `{"id":"…","prompts":[…]}` section objects).
///
/// Fields are mutable so that [fromJson] and test code can set them
/// without a 26-parameter constructor (quality-gate max-params = 6).
class CliAgentParams {
  /// Creates params with all defaults applied.
  ///
  /// Use [CliAgentParams.fromJson] for production, or set fields directly
  /// via cascade syntax in tests:
  /// ```dart
  /// CliAgentParams()..cliCommands = ['echo']..setup = 'make setup';
  /// ```
  CliAgentParams();

  /// Optional smart input context (plain ticket-key string or config object).
  dynamic input;

  /// CLI commands to execute — required for the job to do anything.
  List<String> cliCommands = const [];

  /// Single base CLI prompt (appended to every command via temp file).
  String? cliPrompt;

  /// Structured CLI prompts — array of strings and/or section objects.
  dynamic cliPrompts;

  /// Tracker-specific CLI prompts, keyed by tracker type name.
  Map<String, List<String>>? cliPromptsByTracker;

  /// Setup hook — shell command or `.js` path (runs first).
  String? setup;

  /// Cache hook — shell command or `.js` path (runs after postJSAction).
  String? cache;

  /// Reset hook — shell command or `.js` path (always runs, even on failure).
  String? reset;

  /// Pre-CLI JS action path (runs before cliCommands).
  String? preCliJSAction;

  /// Whether to clean up the input folder after execution. Default: `true`.
  bool cleanupInputFolder = true;

  /// Whether to require an output file for success. Default: `false`.
  bool requireCliOutputFile = false;

  /// Working directory for command execution. Default: CWD.
  String? workingDirectory;

  /// Exact env variable names to exclude from the subprocess.
  List<String>? excludedEnvVariables;

  /// Regex patterns; matching env variable names are excluded.
  List<String>? excludeEnvVariablesByRegex;

  /// Timer JS action path, fired periodically during CLI execution.
  String? timerJSAction;

  /// Timer interval in seconds. Default: `60`.
  int timerIntervalSeconds = 60;

  /// Whether to clean up the outputs folder after execution.
  bool cleanupOutputsFolder = false;

  /// JS action path fired when a CLI command fails.
  String? cliExecutionErrorJSAction;

  /// JS action path fired for each output line; returning true stops.
  String? cliOutputLineJSAction;

  // --- Inherited from TrackerParams ---

  /// Output type — `comment`, `field`, `creation`, or `none`.
  String? outputType;

  /// Per-job environment variable overrides.
  Map<String, String>? envVariables;

  /// Job metadata (contains `contextId`, etc.).
  Map<String, dynamic>? metadata;

  /// Job initiator.
  String? initiator;

  /// Pre-JS action path (runs after setup, before preCliJSAction).
  String? preJSAction;

  /// Post-JS action path (runs after cliCommands, before cache).
  String? postJSAction;

  /// Custom parameters exposed to JS actions as `customParams`.
  Map<String, dynamic>? customParams;

  /// Returns the context ID from metadata, or `"cli-agent"` fallback.
  ///
  /// Mirrors `CliAgent.getContextId()`.
  String get contextId {
    final md = metadata;
    if (md != null && md['contextId'] is String) {
      final id = md['contextId'] as String;
      if (id.isNotEmpty) return id;
    }
    return 'cli-agent';
  }

  /// Returns `cliPrompts` as a flat string array, or `null`.
  ///
  /// Handles both plain string arrays and structured config (objects with
  /// `id`/`prompts` fields), matching the Java `CliPromptsConfig.toStringArray()`.
  List<String>? get cliPromptsAsArray => _flattenCliPrompts(cliPrompts);

  /// Creates params from a JSON map (the `params` block of a job config).
  factory CliAgentParams.fromJson(Map<String, dynamic> json) {
    return CliAgentParams()
      ..input = json['input']
      ..cliCommands = _parseStringList(json['cliCommands'])
      ..cliPrompt = _parseString(json['cliPrompt'])
      ..cliPrompts = json['cliPrompts']
      ..cliPromptsByTracker =
          _parsePromptsByTracker(json['cliPromptsByTracker'])
      ..setup = _parseString(json['setup'])
      ..cache = _parseString(json['cache'])
      ..reset = _parseString(json['reset'])
      ..preCliJSAction = _parseString(json['preCliJSAction'])
      ..cleanupInputFolder = _parseBool(json['cleanupInputFolder'], true)
      ..requireCliOutputFile = _parseBool(json['requireCliOutputFile'], false)
      ..workingDirectory = _parseString(json['workingDirectory'])
      ..excludedEnvVariables = _parseStringList(json['excludedEnvVariables'])
      ..excludeEnvVariablesByRegex =
          _parseStringList(json['excludeEnvVariablesByRegex'])
      ..timerJSAction = _parseString(json['timerJSAction'])
      ..timerIntervalSeconds = _parseInt(json['timerIntervalSeconds'], 60)
      ..cleanupOutputsFolder = _parseBool(json['cleanupOutputsFolder'], false)
      ..cliExecutionErrorJSAction =
          _parseString(json['cliExecutionErrorJSAction'])
      ..cliOutputLineJSAction = _parseString(json['cliOutputLineJSAction'])
      ..outputType = _parseString(json['outputType'])
      ..envVariables = _parseStringMap(json['envVariables'])
      ..metadata = _parseDynamicMap(json['metadata'])
      ..initiator = _parseString(json['initiator'])
      ..preJSAction = _parseString(json['preJSAction'])
      ..postJSAction = _parseString(json['postJSAction'])
      ..customParams = _parseDynamicMap(json['customParams']);
  }
}

// ----------------------------------------------------------------------
// JSON parsing helpers (top-level, private to this library).
// ----------------------------------------------------------------------

String? _parseString(dynamic value) => value == null ? null : value.toString();

bool _parseBool(dynamic value, bool defaultValue) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return defaultValue;
}

int _parseInt(dynamic value, int defaultValue) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return defaultValue;
}

List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const [];
}

Map<String, String>? _parseStringMap(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  return null;
}

Map<String, dynamic>? _parseDynamicMap(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

Map<String, List<String>>? _parsePromptsByTracker(dynamic value) {
  if (value is! Map) return null;
  final result = <String, List<String>>{};
  for (final entry in value.entries) {
    if (entry.value is List) {
      result[entry.key.toString()] =
          (entry.value as List).whereType<String>().toList();
    }
  }
  return result;
}

/// Flattens `cliPrompts` (string array or structured config) to a flat list.
///
/// Each element can be a plain string or an object with `id` and `prompts`
/// keys (the `CliPromptsConfig` structured form). Returns `null` when the
/// input is null or empty.
List<String>? _flattenCliPrompts(dynamic value) {
  if (value == null || value is! List) return null;
  final result = <String>[];
  for (final item in value) {
    result.addAll(_flattenCliPromptItem(item));
  }
  return result.isEmpty ? null : result;
}

/// Flattens a single `cliPrompts` element (string or section object).
List<String> _flattenCliPromptItem(dynamic item) {
  if (item is String) return [item];
  if (item is! Map) return const [];
  final prompts = item['prompts'];
  if (prompts is! List) return const [];
  return prompts.whereType<String>().toList();
}
