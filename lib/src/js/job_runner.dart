/// Runs JavaScript jobs in a QuickJS runtime with full tool bridge support.
///
/// Phase 4 orchestrator — mirrors the Java `JobJavaScriptBridge` /
/// `JavaScriptExecutor` pipeline:
/// 1. Create a QuickJS runtime.
/// 2. Register host functions (`executeToolViaJava`, `file_read`,
///    `set_env_variable`) via [ToolBridge].
/// 3. Inject job context (`params.jobParams`, `params.ticket`).
/// 4. Generate and eval snake_case tool wrapper JS for every tool.
/// 5. Eval the agent/test script.
/// 6. Return the JSON result.
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
  /// Returns the script's return value as a JSON string, or `null` when the
  /// result is JS `undefined`.
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
      return rt.eval(script, filename: scriptPath);
    } finally {
      rt.close();
    }
  }

  /// Wires up host functions, job context, and tool wrappers on [rt].
  void _wireRuntime(
    QuickjsRuntime rt,
    ToolRegistry registry,
    Map<String, dynamic> jobParams,
    Map<String, dynamic>? ticket,
    String? workingDirectory,
    Set<String>? integrationFilter,
  ) {
    ToolBridge(registry: registry, workingDirectory: workingDirectory)
        .registerOn(rt);
    _injectContext(rt, jobParams, ticket);
    final wrappers = _buildWrappers(registry, integrationFilter);
    rt.eval(wrappers, filename: '<tool_wrappers>');
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
