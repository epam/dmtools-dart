/// Runs JavaScript jobs in a QuickJS runtime with full tool bridge support.
///
/// Phase 4 orchestrator — mirrors the Java `JobJavaScriptBridge` /
/// `JavaScriptExecutor` pipeline:
/// 1. Create a QuickJS runtime.
/// 2. Inject job context (`params.jobParams`, `params.ticket`, …).
/// 3. Install the CommonJS `require` loader ([installRequireLoader]).
/// 4. Generate and eval snake_case tool wrapper JS for every tool.
/// 5. Register host functions (`executeToolViaJava`, `file_read`,
///    `set_env_variable`, `console`) via [ToolBridge] — last, so the direct
///    `file_read` global wins over the generated wrapper.
/// 6. Set the current script directory (relative `require` base), load the
///    script source (file / inline / URL — Java `loadJavaScriptCode`
///    parity), and eval it.
/// 7. Call the script's `action(params)` — the JSRunner contract. Scripts
///    without an `action` function fail with the Java-parity error
///    `JavaScript code must define an 'action' function`.
library;

import 'dart:convert';
import 'dart:io';

import '../mcp/default_tool_registry.dart';
import '../mcp/tool_registry.dart';
import 'package:quickjs_runtime/quickjs_runtime.dart';
import 'async_job_pool.dart';
import 'engine_factory.dart';
import 'sync_http_client.dart';

/// Optional configuration for [JsJobRunner.runScript].
///
/// Bundles the less-commonly-used parameters so that [JsJobRunner.runScript]
/// stays within the quality-gate param limit.
class JsRunConfig {
  /// Creates a run configuration.
  const JsRunConfig({
    this.integrationFilter,
    this.registry,
    this.extraGlobals,
    this.contextParams,
    this.pool,
    this.httpFetch,
  });

  /// Restricts generated wrappers to the named integrations.
  ///
  /// When null, wrappers for all integrations are generated.
  final Set<String>? integrationFilter;

  /// Tool registry to use; defaults to the full catalog when null.
  final ToolRegistry? registry;

  /// Additional top-level JS globals set after `params` but before the
  /// script runs.
  final Map<String, dynamic>? extraGlobals;

  /// Additional entries merged into the `params` object passed to
  /// `action(params)` — mirrors Java `JavaScriptExecutor.withJobContext()` /
  /// `.with()` bindings (`response`, `initiator`, `inputJql`, `metadata`, …).
  ///
  /// Null-valued entries must be omitted by the caller (Java's
  /// `JSONObject.put(key, null)` removes the key).
  final Map<String, dynamic>? contextParams;

  /// Worker pool for `runAsync(fn, args)` (defaults to
  /// [AsyncJobPool.instance]). Only consulted when `jobParams` carries
  /// `parallelWorkers >= 2`; tests boot a private pool and pass it here.
  final AsyncJobPool? pool;

  /// Alternate `fetch` transport for the node/js compat layer on the
  /// main engine (JSON in, JSON out). Defaults to the pooled
  /// [SyncHttpClient]; see [EngineSpec.httpFetch].
  final String? Function(String requestJson)? httpFetch;
}

/// A resolved script source: the [code] plus the [filename] used for eval
/// diagnostics.
class _LoadedScript {
  const _LoadedScript(this.code, this.filename);

  /// Inline code: the source itself is the "path", so eval diagnostics
  /// get a stable pseudo-filename.
  const _LoadedScript.inline(String code) : this(code, '<inline>');

  final String code;
  final String filename;
}

/// Runs JavaScript agent/test scripts in a QuickJS runtime.
class JsJobRunner {
  /// Creates a new job runner.
  const JsJobRunner();

  /// Runs [scriptPath] as a JS job with the given [jobParams].
  ///
  /// Mirrors the Java `JobJavaScriptBridge.executeJavaScript` contract:
  /// the script source is resolved via `loadJavaScriptCode` parity (file,
  /// inline code, or http(s) URL), evaluated, and its `action(params)`
  /// function is invoked — scripts without `action` fail with the
  /// Java-parity error. The action's return value (JSON) is the result;
  /// `null` means JS `undefined`.
  ///
  /// - [jobParams] — injected as `params.jobParams` in the JS global scope.
  /// - [ticket] — injected as `params.ticket` when non-null.
  /// - [workingDirectory] — base for relative file paths in tool calls.
  /// - [config] — optional [JsRunConfig] for integration filtering, custom
  ///   registries, and extra JS globals / params context.
  String? runScript({
    required String scriptPath,
    required Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
    String? workingDirectory,
    JsRunConfig? config,
  }) {
    final cfg = config ?? const JsRunConfig();
    final rt = QuickjsRuntime();
    try {
      final reg = cfg.registry ?? createDefaultToolRegistry();
      final compat =
          _wireRuntime(rt, reg, jobParams, ticket, workingDirectory, cfg);
      if (JsJobRunner.needsAsyncPool(jobParams)) {
        _wireAsyncPool(
          rt,
          scriptPath: scriptPath,
          jobParams: jobParams,
          ticket: ticket,
          workingDirectory: workingDirectory,
          cfg: cfg,
        );
      }
      setScriptDirectory(rt, scriptPath);
      final loaded = _loadJavaScriptCode(scriptPath);
      _evalScript(rt, loaded.code, loaded.filename);
      final result = _callAction(rt);
      // nodeCompat scripts may register timers (setTimeout-as-sleep etc.);
      // block-mode drain (dmtools default) settles them like Node would.
      // DRAIN-ERROR POLICY (epam/dmtools-dart#243): the MAIN engine
      // deliberately propagates a drain failure — for a script the timer
      // chain IS part of the run's contract (side-effect timers, sleep
      // pattern), and silently dropping callbacks would report success
      // with lost effects. Worker dispatches swallow-with-a-log instead
      // (async_job_pool.dart): there the fn's return value is the job.
      compat?.drainTimers();
      return result;
    } finally {
      rt.close();
    }
  }

  /// Whether [jobParams] enable the `runAsync` engine-worker surface —
  /// the single source of the `parallelWorkers >= 2` predicate, shared by
  /// [runScript] (pool wiring) and the CLI dispatcher (lazy pool boot,
  /// epam/dmtools-dart#241).
  static bool needsAsyncPool(Map<String, dynamic> jobParams) =>
      effectiveParallelWorkers(jobParams) >= 2;

  /// Effective `parallelWorkers` knob (0 when absent or non-numeric).
  ///
  /// Values >= 2 enable the `runAsync` API on the engine; everything else
  /// keeps the default sequential surface (default-off, zero deviation).
  static int effectiveParallelWorkers(Map<String, dynamic> jobParams) {
    final value = jobParams['parallelWorkers'];
    return value is num ? value.toInt() : 0;
  }

  /// Wires the `runAsync` / `AsyncJob` surface onto [rt] by delegating
  /// to [AsyncJobPool.attachMainRuntime] (quickjs_runtime owns the
  /// `__jsr*` host functions and the prelude — no adapter duplicate,
  /// epam/dmtools-dart#242).
  ///
  /// Uses [JsRunConfig.pool], defaulting to [AsyncJobPool.instance]. When
  /// the pool is not booted, `runAsync(...)` throws a clear JS error on
  /// first use (dispatch sentinel) instead of failing the engine wiring.
  void _wireAsyncPool(
    QuickjsRuntime rt, {
    required String scriptPath,
    required Map<String, dynamic> jobParams,
    required Map<String, dynamic>? ticket,
    required String? workingDirectory,
    required JsRunConfig cfg,
  }) {
    final pool = cfg.pool ?? AsyncJobPool.instance;
    final params = buildParamsMap(
      jobParams: jobParams,
      ticket: ticket,
      contextParams: cfg.contextParams,
      extraGlobals: cfg.extraGlobals,
    );
    pool.attachMainRuntime(
      rt,
      scriptDirectory: jsDirectoryOf(scriptPath),
      workingDirectory: workingDirectory,
      params: params,
    );
  }

  /// Evaluates the script source, surfacing JS exceptions.
  ///
  /// QuickJS reports eval exceptions through `errMsg` (the eval itself
  /// returns `null`); Java wraps the same failure in
  /// `RuntimeException("JavaScript execution failed: …")` — mirrored here.
  void _evalScript(QuickjsRuntime rt, String code, String filename) {
    final errors = <String?>[];
    rt.eval(code, filename: filename, errMsg: errors);
    if (errors.isNotEmpty) {
      throw StateError('JavaScript execution failed: ${errors.first}');
    }
  }

  /// Invokes the script's `action(params)` (JSRunner contract).
  ///
  /// Missing / non-function `action` fails with the Java-parity message;
  /// exceptions raised inside `action` surface as evaluation failures.
  String? _callAction(QuickjsRuntime rt) {
    final kind = rt.eval('typeof action', filename: '<action_check>');
    if (jsonDecode(kind ?? '"undefined"') != 'function') {
      throw StateError("JavaScript code must define an 'action' function");
    }
    final errors = <String?>[];
    final result = rt.eval(
      'action(params)',
      filename: '<action_call>',
      errMsg: errors,
    );
    if (errors.isNotEmpty) {
      throw StateError('JavaScript execution failed: ${errors.first}');
    }
    return result;
  }

  /// Wires up job context, require loader, tool wrappers, and host
  /// functions on [rt].
  ///
  /// Delegates to [wireEngine] — the shared wiring used verbatim by the
  /// `runAsync` worker engines, so both paths stay behaviorally identical.
  /// Host functions are registered **after** the generated tool wrappers so
  /// that the direct `file_read` global (returning the raw content string,
  /// as testRunner.js requires) takes precedence over the wrapper that
  /// dispatches through `executeToolViaJava` with an `{content: …}` shape.
  NodeCompatHandle? _wireRuntime(
    QuickjsRuntime rt,
    ToolRegistry registry,
    Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
    String? workingDirectory,
    JsRunConfig config,
  ) {
    return wireEngine(
      rt,
      EngineSpec(
        context: EngineContext(
          jobParams: jobParams,
          ticket: ticket,
          contextParams: config.contextParams,
          extraGlobals: config.extraGlobals,
        ),
        registry: registry,
        integrationFilter: config.integrationFilter,
        workingDirectory: workingDirectory,
        httpFetch: config.httpFetch,
      ),
    );
  }

  // ── Script source resolution (Java loadJavaScriptCode parity) ─────────

  /// Resolves [jsSourceOrPath] to script code — Java
  /// `JobJavaScriptBridge.loadJavaScriptCode` parity:
  /// http(s) URLs fetch remotely; inline code (starts with `function` or
  /// contains `action`) and strings without `/` / `.js` pass through
  /// as-is; everything else loads from the filesystem.
  _LoadedScript _loadJavaScriptCode(String jsSourceOrPath) {
    if (jsSourceOrPath.startsWith('http://') ||
        jsSourceOrPath.startsWith('https://')) {
      return _LoadedScript(
        _loadFromUrl(jsSourceOrPath),
        jsSourceOrPath,
      );
    }
    final isInline = jsSourceOrPath.trim().startsWith('function') ||
        jsSourceOrPath.contains('action') ||
        (!jsSourceOrPath.contains('/') && !jsSourceOrPath.endsWith('.js'));
    if (isInline) return _LoadedScript.inline(jsSourceOrPath);
    return _LoadedScript(_loadFromFile(jsSourceOrPath), jsSourceOrPath);
  }

  /// Loads script code from the filesystem, or fails with the Java-parity
  /// `JavaScript file not found` message.
  String _loadFromFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      throw StateError(
        'JavaScript file not found in resources or filesystem: $path',
      );
    }
  }

  /// Synchronously fetches [url] via [SyncHttpClient] (curl subprocess).
  String _loadFromUrl(String url) {
    final response = SyncHttpClient.get(url);
    if (!response.isOk) {
      throw StateError(
        'Failed to load JS from source code: $url '
        '(HTTP ${response.statusCode}: ${response.body})',
      );
    }
    return response.body;
  }
}
