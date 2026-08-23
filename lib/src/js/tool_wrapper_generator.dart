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
  /// Every tool gets a wrapper under its canonical name and under each alias
  /// — the Java schema registry exposes aliases as dispatchable tools too, so
  /// scripts may call either name (e.g. `jira_create_ticket_basic` or its
  /// canonical name). Alias wrappers dispatch under the canonical tool name.
  String generate(ToolRegistry registry) {
    final buffer = StringBuffer()
      ..writeln('// Auto-generated MCP tool wrappers');
    for (final tool in registry.allTools) {
      buffer.writeln(_wrapperFor(tool.name, tool.params));
      for (final alias in tool.aliases) {
        buffer.writeln(_wrapperFor(alias, tool.params, dispatchAs: tool.name));
      }
    }
    return buffer.toString();
  }

  /// Returns the wrapper JS for a single [tool].
  String _wrapperFor(
    String name,
    List<ToolParam> params, {
    String? dispatchAs,
  }) {
    if (params.isEmpty) return _noArgWrapper(name, dispatchAs);
    return _paramWrapper(name, params, dispatchAs);
  }

  /// Wrapper for a tool that takes no parameters.
  static String _noArgWrapper(String name, [String? dispatchAs]) =>
      'globalThis.$name = function() {\n'
      "  return executeToolViaJava('${dispatchAs ?? name}', {});\n"
      '};\n';

  /// Wrapper for a tool with positional [params].
  ///
  /// Accepts either positional arguments or a single object argument that
  /// passes through directly.
  String _paramWrapper(
    String name,
    List<ToolParam> params, [
    String? dispatchAs,
  ]) {
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
        "  return executeToolViaJava('${dispatchAs ?? name}', args);\n"
        '};\n';
  }
}
