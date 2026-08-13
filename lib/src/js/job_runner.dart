/// Runs JavaScript jobs in a QuickJS runtime with full tool bridge support.
///
/// Phase 4 orchestrator — mirrors the Java `JobJavaScriptBridge` /
/// `JavaScriptExecutor` pipeline:
/// 1. Create a QuickJS runtime.
/// 2. Inject job context (`params.jobParams`, `params.ticket`).
/// 3. Generate and eval snake_case tool wrapper JS for every tool.
/// 4. Register host functions (`executeToolViaJava`, `file_read`,
///    `set_env_variable`, `console`) via [ToolBridge] — last, so the direct
///    `file_read` global wins over the generated wrapper.
/// 5. Eval the agent/test script.
/// 6. Call the script's `action(params)` when defined (JSRunner contract)
///    and return its JSON result.
library;

import 'dart:io';

import '../mcp/default_tool_registry.dart';
import '../mcp/tool_registry.dart';
import 'quickjs_runtime.dart';
import 'tool_bridge.dart';
import 'tool_wrapper_generator.dart';

/// Runs JavaScript agent/test scripts in a QuickJS runtime.
class JsJobRunner {
  /// Creates a new job runner.
  const JsJobRunner();

  /// Runs [scriptPath] as a JS job with the given [jobParams].
  ///
  /// Mirrors the Java JSRunner contract: after evaluating the script, if it
  /// defines a global `action(params)` function, that function is invoked
  /// and its return value (JSON) becomes the result. Otherwise the script's
  /// own eval result is returned.
  ///
  /// Returns the result as a JSON string, or `null` when the result is JS
  /// `undefined`.
  ///
  /// - [jobParams] — injected as `params.jobParams` in the JS global scope.
  /// - [ticket] — injected as `params.ticket` when non-null.
  /// - [workingDirectory] — base for relative file paths in tool calls.
  /// - [integrationFilter] — restricts generated wrappers to the named
  ///   integrations; `null` means all integrations.
  /// - [registry] — tool registry to use; defaults to the full catalog.
  String? runScript({
    required String scriptPath,
    required Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
    String? workingDirectory,
    Set<String>? integrationFilter,
    ToolRegistry? registry,
  }) {
    final rt = QuickjsRuntime();
    try {
      final reg = registry ?? createDefaultToolRegistry();
      _wireRuntime(
          rt, reg, jobParams, ticket, workingDirectory, integrationFilter);
      final script = File(scriptPath).readAsStringSync();
      final scriptResult = rt.eval(script, filename: scriptPath);
      return _callAction(rt) ?? scriptResult;
    } finally {
      rt.close();
    }
  }

  /// Calls the script's `action(params)` when it is defined (JSRunner job
  /// contract); returns `null` (JS `undefined`) when it is not.
  ///
  /// The raw return value flows to the C bridge, which serializes it to
  /// JSON — pre-stringifying here would double-encode the result.
  String? _callAction(QuickjsRuntime rt) {
    return rt.eval(
      '(function() {'
      '  if (typeof action !== "function") return undefined;'
      '  try { return action(params); }'
      '  catch (e) {'
      '    return {success: false, error: String(e && e.message || e)};'
      '  }'
      '})()',
      filename: '<action_call>',
    );
  }

  /// Wires up job context, tool wrappers, and host functions on [rt].
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
    Set<String>? integrationFilter,
  ) {
    _injectContext(rt, jobParams, ticket);
    final wrappers = _buildWrappers(registry, integrationFilter);
    rt.eval(wrappers, filename: '<tool_wrappers>');
    ToolBridge(registry: registry, workingDirectory: workingDirectory)
        .registerOn(rt);
  }

  /// Injects `params` into the JS global scope.
  void _injectContext(
    QuickjsRuntime rt,
    Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
  ) {
    rt.setGlobal('params', {
      'jobParams': jobParams,
      if (ticket != null) 'ticket': ticket,
    });
  }

  /// Generates tool wrappers, optionally narrowed by integration.
  String _buildWrappers(ToolRegistry registry, Set<String>? filter) {
    final source = filter == null ? registry : ToolRegistry()
      ..registerAll(registry.toolsForIntegrations(filter));
    return const ToolWrapperGenerator().generate(source);
  }
}
