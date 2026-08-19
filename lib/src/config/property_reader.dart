/// Property resolution engine for DMTools — Dart port of Java `PropertyReader`.
///
/// Resolution chain (first non-null, non-empty wins):
/// 1. Static overrides — equivalent of Java's `ThreadLocal` overrides,
///    set by `setOverrides` before job execution.
/// 2. `dmtools.env` file — loaded from CWD or project root (mirrors Java's
///    direct file load, which has higher priority than OS env).
/// 3. `dmtools-local.env` file — loaded from CWD (replaces the shell-launcher
///    `export` behaviour from `dmtools.sh`, since the Dart CLI has no shell
///    wrapper).
/// 4. OS environment variables — `Platform.environment`.
/// 5. Method-level default (if provided).
///
/// **Note on Java discrepancy:** GOAL.md states "real env always wins", but
/// the actual Java `PropertyReader.getValue()` checks OS env *last*. The Dart
/// port follows the Java source (the spec per AGENTS.md). A `dmtools.env` in
/// the working directory overrides a real env var set in the shell.
library;

import 'dart:async';
import 'dart:io';

import 'env_file_parser.dart';

/// Core property reader with resolution chain and override management.
///
/// Integration-specific getters live in the `PropertyReaderGetters` extension.
class PropertyReader {
  /// Project-root marker file (Dart equivalent of `settings.gradle`).
  static const _rootMarker = 'pubspec.yaml';

  // --- Static overrides (Java ThreadLocal equivalent) ---

  /// Zone key carrying the per-job override map inside [runWithOverrides].
  ///
  /// Dart's [Zone] is the analog of Java's `ThreadLocal`: values flow
  /// through `await` boundaries and stay isolated between concurrently
  /// running jobs in the same isolate.
  static const _overridesZoneKey = #dmtoolsPropertyOverrides;

  /// Root-level overrides, used outside a [runWithOverrides] scope.
  ///
  /// Safe for the single-job CLI flow; concurrent jobs must use
  /// [runWithOverrides] so one job's [clearOverrides] cannot wipe another's
  /// overrides mid-flight.
  static Map<String, String>? _overrides;

  /// Sets zone-static overrides for the current isolate.
  ///
  /// Called by `JobRunner` before job execution, built from
  /// `TrackerParams.getEnvVariables()`.
  static void setOverrides(Map<String, String> overrides) {
    _overrides = overrides;
  }

  /// Clears the static overrides.
  ///
  /// Always called in a `finally` block after job execution.
  static void clearOverrides() {
    _overrides = null;
  }

  /// Runs [body] with [overrides] active for the current async context.
  ///
  /// The overrides live in a [Zone] value, so two concurrently running jobs
  /// each keep their own map across `await` boundaries (the Java original
  /// gets the same isolation from `ThreadLocal`).
  static Future<T> runWithOverrides<T>(
    Map<String, String> overrides,
    Future<T> Function() body,
  ) {
    return runZoned(
      body,
      zoneValues: {_overridesZoneKey: overrides},
    );
  }

  /// Returns the current override map (empty if none set).
  ///
  /// Zone-scoped overrides ([runWithOverrides]) take precedence over the
  /// root static map ([setOverrides]).
  static Map<String, String> getOverrides() {
    final zoned = Zone.current[_overridesZoneKey];
    if (zoned is Map<String, String>) return Map.unmodifiable(zoned);
    final o = _overrides;
    return o != null ? Map.unmodifiable(o) : const <String, String>{};
  }

  // --- Test isolation (hermetic L1 tests) ---

  /// Testing-only switch: when `true`, `dmtools.env` / `dmtools-local.env`
  /// discovery via CWD/project root is skipped (readers with an explicit
  /// [basePath] still load files) and the OS-environment source is replaced
  /// by [testEnvironment].
  ///
  /// Keeps unit tests hermetic: a developer's real `dmtools.env` in the
  /// project root (the normal L3 setup) otherwise leaks live credentials
  /// into tests that expect empty configuration.
  static bool testIsolation = false;

  /// The environment map consulted instead of `Platform.environment` when
  /// [testIsolation] is enabled. Tests may populate it to exercise the
  /// OS-variable tier of the resolution chain.
  static final Map<String, String> testEnvironment = {};

  /// Optional base directory override (for testing).
  ///
  /// When set, `.env` files are loaded from this directory instead of
  /// [Directory.current]. Production code leaves this `null`.
  final String? basePath;

  /// Creates a property reader.
  ///
  /// Pass [basePath] to override the directory where `dmtools.env` and
  /// `dmtools-local.env` are searched (testing only — production code
  /// omits it so files load from the current working directory).
  PropertyReader({this.basePath});

  // --- Instance state ---

  Map<String, String>? _envProps;
  bool _envPropsLoaded = false;
  Map<String, String>? _localEnvProps;
  bool _localEnvPropsLoaded = false;
  String? _projectRoot;

  /// Resolves a property key through the full chain.
  ///
  /// Returns `null` if not found anywhere.
  String? getValue(String key) {
    // 1. Static overrides (highest priority).
    final overrides = getOverrides();
    if (overrides.containsKey(key)) {
      return overrides[key];
    }
    // 2. dmtools.env.
    _ensureEnvLoaded();
    if (_envProps!.containsKey(key)) {
      return _envProps![key];
    }
    // 3. dmtools-local.env.
    _ensureLocalEnvLoaded();
    if (_localEnvProps!.containsKey(key)) {
      return _localEnvProps![key];
    }
    // 4. OS environment variables (or the isolated test map).
    final env = testIsolation ? testEnvironment : Platform.environment;
    if (env.containsKey(key)) {
      return env[key];
    }
    return null;
  }

  /// Resolves a property key, returning [defaultValue] if not found or empty.
  String getValueWithDefault(String key, String defaultValue) {
    final value = getValue(key);
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    return value;
  }

  // --- File loading (lazy, cached) ---

  void _ensureEnvLoaded() {
    if (_envPropsLoaded) return;
    _envProps =
        _isolationBlocksDefaultFiles() ? {} : _loadEnvFile('dmtools.env');
    _envPropsLoaded = true;
  }

  void _ensureLocalEnvLoaded() {
    if (_localEnvPropsLoaded) return;
    _localEnvProps =
        _isolationBlocksDefaultFiles() ? {} : _loadEnvFile('dmtools-local.env');
    _localEnvPropsLoaded = true;
  }

  /// Whether test isolation is active and this reader uses the default
  /// (CWD/project-root) search — under isolation only explicit
  /// [basePath] directories are still loaded.
  bool _isolationBlocksDefaultFiles() => testIsolation && basePath == null;

  /// Loads an `.env` file from the base path (CWD by default).
  Map<String, String> _loadEnvFile(String filename) {
    final dir = basePath ?? Directory.current.path;
    final file = File('$dir/$filename');
    if (file.existsSync()) {
      return parseEnvFile(file.path);
    }
    if (basePath == null) {
      final root = _findProjectRoot();
      if (root != null && root != dir) {
        final rootFile = File('$root/$filename');
        if (rootFile.existsSync()) {
          return parseEnvFile(rootFile.path);
        }
      }
    }
    return {};
  }

  /// Walks up from CWD looking for [_rootMarker] (`pubspec.yaml`).
  String? _findProjectRoot() {
    if (_projectRoot != null) return _projectRoot;
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}/$_rootMarker').existsSync()) {
        _projectRoot = dir.path;
        return _projectRoot;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break; // filesystem root
      dir = parent;
    }
    return null;
  }

  /// Resets cached state so the next `getValue` reloads files.
  ///
  /// For unit tests that change env between test cases.
  void resetForTesting() {
    _envProps = null;
    _envPropsLoaded = false;
    _localEnvProps = null;
    _localEnvPropsLoaded = false;
    _projectRoot = null;
  }
}
