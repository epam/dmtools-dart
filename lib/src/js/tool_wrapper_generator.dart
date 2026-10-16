/// Generates JS code that creates snake_case global functions for each tool.
///
/// Each generated function marshals positional arguments into an object and
/// calls `executeToolViaJava(toolName, args)`. When called with a single
/// object argument, that object is passed through directly — matching the
/// Java wrapper generation approach where `arguments[0]` is treated as the
/// args bag.
///
/// Example output for `jira_post_comment`:
/// ```js
/// globalThis.jira_post_comment = function(key, comment) {
///   var args = {};
///   if (arguments.length === 1 && typeof arguments[0] === 'object'
///       && arguments[0] !== null) {
///     args = arguments[0];
///   } else {
///     if (arguments.length > 0) args.key = arguments[0];
///     if (arguments.length > 1) args.comment = arguments[1];
///   }
///   return executeToolViaJava('jira_post_comment', args);
/// };
/// ```
library;

import '../mcp/tool_param.dart';
import '../mcp/tool_registry.dart';

/// Generates global JS function wrappers for every tool in a registry.
class ToolWrapperGenerator {
  /// Creates a new wrapper generator.
  const ToolWrapperGenerator();

  /// Generates JS code for all tools in [registry].
  ///
  /// Every tool gets a wrapper under its canonical name, and each
  /// vendor-agnostic alias (`tracker_*`, `source_code_*`) gets a wrapper
  /// dispatching under the ALIAS name (dm.ai #577) — the bridge resolves
  /// the backend on every call, so key-format routing stays dynamic. A
  /// canonical tool name is never shadowed and a shared alias is exposed
  /// exactly once.
  String generate(ToolRegistry registry) {
    final buffer = StringBuffer()
      ..writeln('// Auto-generated MCP tool wrappers');
    final canonicalNames = registry.allTools.map((tool) => tool.name).toSet();
    final exposedAliases = <String>{};
    for (final tool in registry.allTools) {
      buffer.writeln(_wrapperFor(tool.name, tool.params));
      // Java JobJavaScriptBridge.exposeMCPToolsUsingGenerated parity
      // (dm.ai #577): vendor-agnostic aliases (tracker_*, source_code_*)
      // are exposed as first-class JS globals dispatching under the ALIAS
      // name, so the bridge re-routes every call — per-call key-format
      // detection (gh-123 → GitHub, PROJ-123 → Jira, bare integer → ADO)
      // stays dynamic even when DEFAULT_TRACKER is unset. A canonical tool
      // name is never shadowed and a shared alias is exposed once.
      for (final alias in tool.aliases) {
        if (canonicalNames.contains(alias) || !exposedAliases.add(alias)) {
          continue;
        }
        buffer.writeln(_wrapperFor(alias, tool.params));
      }
    }
    return buffer.toString();
  }

  /// Returns the wrapper JS for a single [tool].
  String _wrapperFor(String name, List<ToolParam> params) {
    if (params.isEmpty) return _noArgWrapper(name);
    return _paramWrapper(name, params);
  }

  /// The call log statement emitted into every wrapper — Java
  /// `JobJavaScriptBridge.exposeToolToJS` parity:
  /// `console.log('Calling tool <name> with args:', JSON.stringify(args));`
  /// placed after args assembly, right before dispatch.
  String _callLog(String name) =>
      "  console.log('Calling tool $name with args:', "
      'JSON.stringify(args));\n';

  /// Wrapper for a tool that takes no parameters.
  String _noArgWrapper(String name) => 'globalThis.$name = function() {\n'
      '  var args = {};\n'
      '${_callLog(name)}'
      "  return executeToolViaJava('$name', args);\n"
      '};\n';

  /// Wrapper for a tool with positional [params].
  ///
  /// Accepts either positional arguments or a single object argument that
  /// passes through directly.
  String _paramWrapper(String name, List<ToolParam> params) {
    final paramList = params.map((p) => p.name).join(', ');
    final assignments = [
      for (var i = 0; i < params.length; i++)
        '    if (arguments.length > $i) args.${params[i].name}'
            ' = arguments[$i];',
    ].join('\n');
    return 'globalThis.$name = function($paramList) {\n'
        '  var args = {};\n'
        "  if (arguments.length === 1 && typeof arguments[0] === 'object'"
        ' && arguments[0] !== null) {\n'
        '    args = arguments[0];\n'
        '  } else {\n'
        '$assignments\n'
        '  }\n'
        '${_callLog(name)}'
        "  return executeToolViaJava('$name', args);\n"
        '};\n';
  }
}
