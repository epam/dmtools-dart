/// MCP tool definition and executor for Mermaid diagrams.
///
/// Ports the `mermaid_render` tool from the Java DMTools `@MCPTool` catalog.
/// No external API is required: [MermaidToolExecutor] validates the diagram
/// syntax locally and wraps it in a fenced Markdown code block.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';

/// Diagram-type keywords recognized by the lightweight syntax validator.
const Set<String> mermaidDiagramKeywords = {
  'flowchart',
  'graph',
  'sequencediagram',
  'classdiagram',
  'statediagram',
  'statediagram-v2',
  'erdiagram',
  'journey',
  'gantt',
  'pie',
  'quadrantchart',
  'requirementdiagram',
  'gitgraph',
  'mindmap',
  'timeline',
  'block-beta',
  'packet-beta',
  'architecture-beta',
  'sankey-beta',
  'xychart-beta',
};

/// Returns the Mermaid MCP tool definition.
///
/// The tool name and argument schema mirror the Java `@MCPTool` annotation.
List<ToolDefinition> mermaidTools() => [
      ToolDefinition(
        name: 'mermaid_render',
        description:
            'Validate Mermaid diagram syntax and wrap it in a code block',
        integration: 'mermaid',
        category: 'diagrams',
        params: [
          ToolParam(name: 'diagram', description: 'The Mermaid diagram source'),
          ToolParam(
            name: 'format',
            description: 'Output format: markdown (default) or raw',
            required: false,
          ),
        ],
      ),
    ];

/// Executes the Mermaid MCP tool.
///
/// [render] validates the diagram and returns it wrapped in a fenced
/// `mermaid` Markdown block (or verbatim for the `raw` format).
class MermaidToolExecutor {
  /// Creates a stateless Mermaid tool executor.
  MermaidToolExecutor();

  /// Dispatches [toolName] with [args] to [render].
  ///
  /// Throws [ArgumentError] for an unknown Mermaid tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    if (toolName != 'mermaid_render') {
      throw ArgumentError('Unknown Mermaid tool: $toolName');
    }
    return render(args['diagram'] as String, args['format'] as String?);
  }

  /// Validates [diagram] and returns it in the requested [format].
  ///
  /// [format] defaults to `"markdown"`, which wraps the diagram in a fenced
  /// `mermaid` code block; `"raw"` returns the trimmed source unchanged.
  /// Throws [ArgumentError] when the syntax is invalid or [format] is
  /// unsupported.
  Future<String> render(String diagram, [String? format]) async {
    final validated = _validateSyntax(diagram);
    final out = (format ?? 'markdown').toLowerCase();
    switch (out) {
      case 'markdown':
        return '```mermaid\n$validated\n```';
      case 'raw':
        return validated;
      default:
        throw ArgumentError('Unsupported format: $out');
    }
  }

  /// Checks that [diagram] starts with a recognized diagram-type keyword.
  ///
  /// Returns the trimmed diagram source on success.
  String _validateSyntax(String diagram) {
    final trimmed = diagram.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Diagram must not be empty');
    }
    final keyword = trimmed.split(RegExp(r'[\s;]')).first.toLowerCase();
    if (!mermaidDiagramKeywords.contains(keyword)) {
      throw ArgumentError('Unknown diagram type: $keyword');
    }
    return trimmed;
  }
}
