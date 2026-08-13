/// MCP tool definitions and executor for Mermaid diagrams.
///
/// Ports the `mermaid_*` tools from the Java DMTools `@MCPTool` catalog.
/// No external API is required: [MermaidToolExecutor] validates the diagram
/// syntax locally and formats it for the requested output format.
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

/// Returns the Mermaid MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> mermaidTools() => [
      _renderTool(),
      _validateTool(),
      _exportTool(),
    ];

/// `mermaid_render` — validate and wrap a diagram in a code block.
ToolDefinition _renderTool() => ToolDefinition(
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
    );

/// `mermaid_validate` — check diagram syntax without rendering it.
ToolDefinition _validateTool() => ToolDefinition(
      name: 'mermaid_validate',
      description: 'Validate Mermaid diagram syntax without rendering it',
      integration: 'mermaid',
      category: 'diagrams',
      params: [
        ToolParam(name: 'diagram', description: 'The Mermaid diagram source'),
      ],
    );

/// `mermaid_export` — return a diagram in a requested output format.
ToolDefinition _exportTool() => ToolDefinition(
      name: 'mermaid_export',
      description:
          'Validate a Mermaid diagram and return it in the requested format '
          '(markdown, raw, or svg)',
      integration: 'mermaid',
      category: 'diagrams',
      params: [
        ToolParam(name: 'diagram', description: 'The Mermaid diagram source'),
        ToolParam(
          name: 'format',
          description: 'Output format: markdown (default), raw, or svg',
          required: false,
        ),
      ],
    );

/// Executes the Mermaid MCP tools.
///
/// [render] validates the diagram and wraps it in a fenced `mermaid`
/// Markdown block (or returns it verbatim for the `raw` format).
/// [validate] reports syntax validity without producing output. [export]
/// additionally supports an `svg` wrapper document; raster formats such as
/// `png` need an external renderer and are rejected.
class MermaidToolExecutor {
  /// Creates a stateless Mermaid tool executor.
  MermaidToolExecutor();

  /// Dispatches [toolName] with [args] to the matching Mermaid operation.
  ///
  /// Throws [ArgumentError] for an unknown Mermaid tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Mermaid tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'mermaid_render': (a) =>
        render(a['diagram'] as String, a['format'] as String?),
    'mermaid_validate': (a) => validate(a['diagram'] as String),
    'mermaid_export': (a) =>
        export(a['diagram'] as String, a['format'] as String?),
  };

  /// Validates [diagram] and returns it in the requested [format].
  ///
  /// [format] defaults to `"markdown"`, which wraps the diagram in a fenced
  /// `mermaid` code block; `"raw"` returns the trimmed source unchanged.
  /// Throws [ArgumentError] when the syntax is invalid or [format] is
  /// unsupported.
  Future<String> render(String diagram, [String? format]) async =>
      _format(_validateSyntax(diagram), format ?? 'markdown', allowSvg: false);

  /// Checks [diagram] syntax without rendering it.
  ///
  /// Returns `{"valid": true, "diagram_type": ...}` for a recognized diagram
  /// and `{"valid": false, "error": ...}` otherwise — invalid syntax is a
  /// result here, not an exception.
  Future<Map<String, dynamic>> validate(String diagram) async {
    final trimmed = diagram.trim();
    if (trimmed.isEmpty) {
      return {'valid': false, 'error': 'Diagram must not be empty'};
    }
    final type = _diagramType(trimmed);
    if (!mermaidDiagramKeywords.contains(type)) {
      return {'valid': false, 'error': 'Unknown diagram type: $type'};
    }
    return {'valid': true, 'diagram_type': type};
  }

  /// Validates [diagram] and returns it in the requested [format].
  ///
  /// Accepts the same formats as [render] plus `"svg"`, which wraps the
  /// validated source in a standalone SVG document (no layout engine is
  /// bundled, so the SVG carries the diagram source as text). Raster formats
  /// such as `png` are rejected. Throws [ArgumentError] when the syntax is
  /// invalid or [format] is unsupported.
  Future<String> export(String diagram, [String? format]) async =>
      _format(_validateSyntax(diagram), format ?? 'markdown', allowSvg: true);

  /// Formats the validated diagram for [format]; [allowSvg] gates the
  /// svg wrapper to [export] ([render] rejects it).
  String _format(String validated, String format, {required bool allowSvg}) {
    final out = format.toLowerCase();
    if (out == 'svg') {
      if (!allowSvg) throw ArgumentError('Unsupported format: $out');
      return _svgDocument(validated);
    }
    switch (out) {
      case 'markdown':
        return '```mermaid\n$validated\n```';
      case 'raw':
        return validated;
      default:
        throw ArgumentError('Unsupported format: $out');
    }
  }

  /// Wraps [diagram] in a standalone SVG document carrying the source lines
  /// as monospaced text.
  String _svgDocument(String diagram) {
    final lines = diagram.split('\n');
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="800" '
        'height="${16 * lines.length + 24}">',
      );
    for (var i = 0; i < lines.length; i++) {
      buffer.writeln(
        '<text x="10" y="${16 * (i + 1)}" font-family="monospace" '
        'font-size="14">${_escapeXml(lines[i])}</text>',
      );
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  /// Escapes [text] for use as XML character data.
  String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Extracts the lowercase diagram-type keyword that leads [trimmed].
  String _diagramType(String trimmed) =>
      trimmed.split(RegExp(r'[\s;]')).first.toLowerCase();

  /// Checks that [diagram] starts with a recognized diagram-type keyword.
  ///
  /// Returns the trimmed diagram source on success.
  String _validateSyntax(String diagram) {
    final trimmed = diagram.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Diagram must not be empty');
    }
    final keyword = _diagramType(trimmed);
    if (!mermaidDiagramKeywords.contains(keyword)) {
      throw ArgumentError('Unknown diagram type: $keyword');
    }
    return trimmed;
  }
}
