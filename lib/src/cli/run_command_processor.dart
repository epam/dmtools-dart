/// `dmtools run` command argument processing — Dart port of Java
/// `RunCommandProcessor`.
///
/// Resolves the three `run` invocation modes:
/// - `.js` script → JSRunner config.
/// - Known job name (no matching file) → minimal job config.
/// - JSON config file → full resolution (parent chain, encoded override,
///   CLI parameter overrides).
library;

import 'dart:convert';
import 'dart:io';

import 'config_merger.dart';
import 'encoding_detector.dart';
import 'job_registry.dart';

/// Processes `dmtools run` command arguments into resolved config JSON.
class RunCommandProcessor {
  /// Creates a run-command processor.
  const RunCommandProcessor();

  /// Processes run command args and returns resolved config JSON.
  ///
  /// [args] layout (first element is `run`):
  /// ```
  /// ["run", filePath, encodedConfig?, --key, value, ...]
  /// ["run", jobName,  --key, value, ...]
  /// ["run", script.js, encodedConfig?]
  /// ```
  ///
  /// Returns the resolved config as a compact JSON string.
  /// Throws [ArgumentError] on invalid arguments or missing files.
  String process(List<String> args) {
    if (args.length < 2) {
      throw ArgumentError(
        'run command requires at least a file path or job name',
      );
    }
    final target = args[1];
    final runArgs = _extractRunArgs(args.sublist(2));
    if (target.endsWith('.js')) {
      return _processJsFile(target, runArgs);
    }
    if (JobRegistry.isKnownJob(target) && !File(target).existsSync()) {
      return _processJobName(target, runArgs);
    }
    return _processConfigFile(target, runArgs);
  }

  // ------------------------------------------------------------------
  // Argument extraction
  // ------------------------------------------------------------------

  /// Extracts the encoded config (first non-flag arg) and `--key value`
  /// overrides from the tokens after the target.
  _RunArgs _extractRunArgs(List<String> remaining) {
    String? encodedConfig;
    final overrides = <String, String>{};
    var foundEncoded = false;
    var i = 0;
    while (i < remaining.length) {
      final arg = remaining[i];
      if (arg.startsWith('--')) {
        final key = arg.substring(2);
        if (i + 1 < remaining.length) {
          overrides[key] = remaining[i + 1];
          i += 2;
        } else {
          i++;
        }
      } else if (!foundEncoded) {
        encodedConfig = arg;
        foundEncoded = true;
        i++;
      } else {
        i++;
      }
    }
    return _RunArgs(encodedConfig, overrides);
  }

  /// Parses a CLI override value into its typed form.
  ///
  /// - Strings starting with `[` → JSON arrays.
  /// - Strings starting with `{` → JSON objects.
  /// - Other strings → left as strings.
  dynamic _parseOverrideValue(String value) {
    if (value.startsWith('[') || value.startsWith('{')) {
      return jsonDecode(value);
    }
    return value;
  }

  // ------------------------------------------------------------------
  // Mode A — .js script → JSRunner
  // ------------------------------------------------------------------

  /// Builds a JSRunner config for a `.js` script, applying encoded config and
  /// CLI overrides (the latter land in `jobParams`).
  String _processJsFile(String jsPath, _RunArgs runArgs) {
    var config = <String, dynamic>{
      'name': 'JSRunner',
      'params': <String, dynamic>{
        'jsPath': jsPath,
        'jobParams': <String, dynamic>{},
      },
    };
    config = _applyEncodedConfig(config, runArgs.encodedConfig);
    _injectJobParams(config, runArgs.overrides);
    return jsonEncode(config);
  }

  /// Injects CLI overrides into `params.jobParams` of [config] (mutates in
  /// place).
  void _injectJobParams(
      Map<String, dynamic> config, Map<String, String> overrides) {
    if (overrides.isEmpty) return;
    final params = config['params'] as Map<String, dynamic>;
    final jobParams = Map<String, dynamic>.from(
      params['jobParams'] as Map<String, dynamic>? ?? const {},
    );
    for (final entry in overrides.entries) {
      jobParams[entry.key] = _parseOverrideValue(entry.value);
    }
    params['jobParams'] = jobParams;
  }

  // ------------------------------------------------------------------
  // Mode B — known job name
  // ------------------------------------------------------------------

  /// Builds a minimal config for a known job name, applying encoded config and
  /// CLI overrides into `params`.
  String _processJobName(String jobName, _RunArgs runArgs) {
    var config = <String, dynamic>{
      'name': jobName,
      'params': <String, dynamic>{},
    };
    config = _applyEncodedConfig(config, runArgs.encodedConfig);
    _injectParams(config, runArgs.overrides);
    return jsonEncode(config);
  }

  // ------------------------------------------------------------------
  // Mode C — JSON config file
  // ------------------------------------------------------------------

  /// Loads, resolves and merges a JSON config file.
  String _processConfigFile(String path, _RunArgs runArgs) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('Config file not found: $path');
    }
    final raw = file.readAsStringSync();
    var config = jsonDecode(raw) as Map<String, dynamic>;
    config = _ParentConfigResolver().resolve(config, file.parent.path);
    config = _applyEncodedConfig(config, runArgs.encodedConfig);
    _injectParams(config, runArgs.overrides);
    return jsonEncode(config);
  }

  // ------------------------------------------------------------------
  // Shared helpers
  // ------------------------------------------------------------------

  /// Deep-merges a decoded encoded config onto [config] (no-op when null/empty).
  Map<String, dynamic> _applyEncodedConfig(
      Map<String, dynamic> config, String? encodedConfig) {
    if (encodedConfig == null || encodedConfig.isEmpty) return config;
    final decoded = autoDetectAndDecode(encodedConfig);
    final override = jsonDecode(decoded) as Map<String, dynamic>;
    return deepMerge(config, override);
  }

  /// Injects CLI overrides into `params` of [config] (mutates in place).
  void _injectParams(
      Map<String, dynamic> config, Map<String, String> overrides) {
    if (overrides.isEmpty) return;
    final params = Map<String, dynamic>.from(
      config['params'] as Map<String, dynamic>? ?? const {},
    );
    for (final entry in overrides.entries) {
      params[entry.key] = _parseOverrideValue(entry.value);
    }
    config['params'] = params;
  }
}

/// Internal container for the two pieces extracted from the post-target args.
class _RunArgs {
  /// The optional encoded config (first non-flag token).
  final String? encodedConfig;

  /// `--key value` CLI overrides.
  final Map<String, String> overrides;

  _RunArgs(this.encodedConfig, this.overrides);
}

// ======================================================================
// Parent-config resolution
// ======================================================================

/// Simplified port of Java `ParentConfigResolver`.
///
/// Walks the `"parent"` chain declared in a config, deep-merging each child
/// onto its resolved parent while honouring `"override"` and `"merge"`
/// directives.
class _ParentConfigResolver {
  /// Resolves [child] by walking up its parent chain.
  ///
  /// [configDir] is the directory of the file that [child] was loaded from;
  /// parent paths are resolved relative to it.
  Map<String, dynamic> resolve(Map<String, dynamic> child, String configDir) {
    final parentBlock = child['parent'];
    if (parentBlock is! Map<String, dynamic>) {
      return _stripMeta(child);
    }
    final path = parentBlock['path'];
    if (path is! String) {
      return _stripMeta(child);
    }
    final resolvedParent = _loadAndResolve(path, configDir);
    final overridePaths = _readStringList(child, 'override');
    final mergePaths = _readStringList(child, 'merge');
    final strippedChild = _stripMeta(child);
    return _mergeWithDirectives(
      resolvedParent,
      strippedChild,
      overridePaths,
      mergePaths,
    );
  }

  /// Loads the parent file and recursively resolves it.
  Map<String, dynamic> _loadAndResolve(String parentPath, String configDir) {
    final file = File('$configDir/$parentPath');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return resolve(json, file.parent.path);
  }

  /// Removes `parent`, `override` and `merge` meta keys, returning a copy.
  Map<String, dynamic> _stripMeta(Map<String, dynamic> config) {
    final result = Map<String, dynamic>.from(config);
    result
      ..remove('parent')
      ..remove('override')
      ..remove('merge');
    return result;
  }

  /// Deep-merges then applies explicit override and merge directives.
  Map<String, dynamic> _mergeWithDirectives(
    Map<String, dynamic> parent,
    Map<String, dynamic> child,
    List<String> overridePaths,
    List<String> mergePaths,
  ) {
    var result = deepMerge(parent, child);
    for (final path in overridePaths) {
      final childValue = _getByPath(child, path);
      if (childValue != null) {
        _setByPath(result, path, childValue);
      }
    }
    for (final path in mergePaths) {
      _applyMergeDirective(result, parent, child, path);
    }
    return result;
  }

  /// Concatenates parent + child arrays at [path] inside [result].
  void _applyMergeDirective(
    Map<String, dynamic> result,
    Map<String, dynamic> parent,
    Map<String, dynamic> child,
    String path,
  ) {
    final parentValue = _getByPath(parent, path);
    final childValue = _getByPath(child, path);
    if (parentValue is List && childValue is List) {
      _setByPath(result, path, [...parentValue, ...childValue]);
    }
  }

  /// Reads a top-level string-list key from [config] (empty when absent).
  List<String> _readStringList(Map<String, dynamic> config, String key) {
    final value = config[key];
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  /// Gets the value at a dot-separated [path] within [map], or `null`.
  dynamic _getByPath(Map<String, dynamic> map, String path) {
    final parts = path.split('.');
    dynamic current = map;
    for (final part in parts) {
      if (current is! Map<String, dynamic>) return null;
      current = current[part];
    }
    return current;
  }

  /// Sets [value] at a dot-separated [path] within [map], creating
  /// intermediate maps as needed (mutates [map]).
  void _setByPath(Map<String, dynamic> map, String path, dynamic value) {
    final parts = path.split('.');
    var current = map;
    for (var i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      current[part] ??= <String, dynamic>{};
      current = current[part] as Map<String, dynamic>;
    }
    current[parts.last] = value;
  }
}
