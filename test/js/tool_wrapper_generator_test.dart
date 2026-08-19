import 'package:dmtools/src/js/tool_wrapper_generator.dart';
import 'package:dmtools/src/mcp/tool_definition.dart';
import 'package:dmtools/src/mcp/tool_param.dart';
import 'package:dmtools/src/mcp/tool_registry.dart';
import 'package:test/test.dart';

/// Tests for [ToolWrapperGenerator] — wrapper JS structure and marshaling
/// semantics for tools with and without parameters.
void main() {
  _testMultiParamTools();
  _testNoParamTools();
  _testObjectArgPassthrough();
  _testMultipleTools();
  _testSingleParamTool();
}

ToolRegistry _registryWith(ToolDefinition tool) =>
    ToolRegistry()..register(tool);

void _testMultiParamTools() {
  group('multi-param tools', () {
    test('generates wrapper with positional params and assignments', () {
      final registry = _registryWith(ToolDefinition(
        name: 'jira_post_comment',
        description: 'Post a comment',
        integration: 'jira',
        params: [
          ToolParam(name: 'key', description: 'Ticket key'),
          ToolParam(name: 'comment', description: 'Comment text'),
        ],
      ));
      final code = const ToolWrapperGenerator().generate(registry);

      expect(code, contains('globalThis.jira_post_comment'));
      expect(code, contains('function(key, comment)'));
      expect(code, contains('args.key = arguments[0]'));
      expect(code, contains('args.comment = arguments[1]'));
      expect(code, contains("executeToolViaJava('jira_post_comment', args)"));
    });
  });
}

void _testNoParamTools() {
  group('no-param tools', () {
    test('generates empty-arg wrapper calling with empty object', () {
      final registry = _registryWith(ToolDefinition(
        name: 'system_info',
        description: 'Get system info',
        integration: 'jira',
      ));
      final code = const ToolWrapperGenerator().generate(registry);

      expect(code, contains('globalThis.system_info = function()'));
      expect(code, contains("executeToolViaJava('system_info', {})"));
    });

    test('starts with auto-generated header comment', () {
      final code = const ToolWrapperGenerator().generate(ToolRegistry());
      expect(code, startsWith('// Auto-generated MCP tool wrappers'));
    });
  });
}

void _testObjectArgPassthrough() {
  group('single object arg passthrough', () {
    test('passes object through directly without positional unpacking', () {
      final registry = _registryWith(ToolDefinition(
        name: 'tool_x',
        description: 'X',
        integration: 'test',
        params: [ToolParam(name: 'a', description: 'A')],
      ));
      final code = const ToolWrapperGenerator().generate(registry);

      expect(code, contains("typeof arguments[0] === 'object'"));
      expect(code, contains('arguments[0] !== null'));
    });
  });
}

void _testMultipleTools() {
  group('multiple tools', () {
    test('wraps all tools in a single code block', () {
      final registry = ToolRegistry()
        ..register(ToolDefinition(
          name: 'tool_a',
          description: 'A',
          integration: 'test',
          params: [ToolParam(name: 'x', description: 'X')],
        ))
        ..register(ToolDefinition(
          name: 'tool_b',
          description: 'B',
          integration: 'test',
        ));
      final code = const ToolWrapperGenerator().generate(registry);

      expect(code, contains('globalThis.tool_a'));
      expect(code, contains('globalThis.tool_b'));
    });
  });
}

void _testSingleParamTool() {
  group('single-param tool', () {
    test('sets property from first positional arg', () {
      final registry = _registryWith(ToolDefinition(
        name: 'file_read',
        description: 'Read file',
        integration: 'file',
        params: [ToolParam(name: 'path', description: 'Path')],
      ));
      final code = const ToolWrapperGenerator().generate(registry);

      expect(code, contains('function(path)'));
      expect(code, contains('args.path = arguments[0]'));
    });
  });
}
