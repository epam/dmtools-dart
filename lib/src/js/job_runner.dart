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
import 'require_loader.dart';
import 'sync_http_client.dart';
import 'tool_bridge.dart';
import 'tool_wrapper_generator.dart';

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
      _wireRuntime(rt, reg, jobParams, ticket, workingDirectory, cfg);
      _setScriptDirectory(rt, scriptPath);
      final loaded = _loadJavaScriptCode(scriptPath);
      _evalScript(rt, loaded.code, loaded.filename);
      return _callAction(rt);
    } finally {
      rt.close();
    }
  }

  /// Sets the `require` base directory from the top-level script path.
  ///
  /// Java `setCurrentScriptDirectory` parity: the last `/`-separated
  /// parent, or `''` when there is none — applied verbatim even when the
  /// "path" is inline code.
  void _setScriptDirectory(QuickjsRuntime rt, String scriptPath) {
    rt.eval(
      '__setScriptDirectory(${jsonEncode(scriptPath)})',
      filename: '<set_script_dir>',
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
  /// Host functions are registered **after** the generated tool wrappers so
  /// that the direct `file_read` global (returning the raw content string,
  /// as testRunner.js requires) takes precedence over the wrapper that
  /// dispatches through `executeToolViaJava` with an `{content: …}` shape.
  void _wireRuntime(
    QuickjsRuntime rt,
    ToolRegistry registry,
    Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
    String? workingDirectory,
    JsRunConfig config,
  ) {
    _injectContext(rt, jobParams, ticket, config.contextParams);
    _injectExtraGlobals(rt, config.extraGlobals);
    installRequireLoader(rt);
    final wrappers = _buildWrappers(registry, config.integrationFilter);
    rt.eval(wrappers, filename: '<tool_wrappers>');
    ToolBridge(registry: registry, workingDirectory: workingDirectory)
        .registerOn(rt);
  }

  /// Injects `params` into the JS global scope.
  void _injectContext(
    QuickjsRuntime rt,
    Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
    Map<String, dynamic>? contextParams,
  ) {
    rt.setGlobal('params', {
      'jobParams': jobParams,
      if (ticket != null) 'ticket': ticket,
      ...?contextParams,
    });
  }

  /// Sets each [extraGlobals] entry as a top-level JS global on [rt].
  void _injectExtraGlobals(
    QuickjsRuntime rt,
    Map<String, dynamic>? extraGlobals,
  ) {
    if (extraGlobals == null) return;
    for (final entry in extraGlobals.entries) {
      rt.setGlobal(entry.key, entry.value);
    }
  }

  /// Generates tool wrappers, optionally narrowed by integration.
  String _buildWrappers(ToolRegistry registry, Set<String>? filter) {
    final source = filter == null ? registry : ToolRegistry()
      ..registerAll(registry.toolsForIntegrations(filter));
    return const ToolWrapperGenerator().generate(source);
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
