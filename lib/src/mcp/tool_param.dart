/// A single parameter for an MCP tool.
///
/// Mirrors the per-property entry that the Java `MCPSchemaGenerator` emits
/// inside a tool's `inputSchema.properties` object.
class ToolParam {
  /// The parameter name, as it appears in the tool's JSON Schema.
  final String name;

  /// Human-readable description surfaced to the MCP client.
  final String description;

  /// Whether the caller must supply this parameter.
  final bool required;

  /// JSON Schema type: `"string"`, `"number"`, `"boolean"`, or `"array"`.
  final String type;

  /// Alternate invocation names for the same parameter.
  final List<String> aliases;

  /// Creates a tool parameter.
  const ToolParam({
    required this.name,
    required this.description,
    this.required = true,
    this.type = 'string',
    this.aliases = const [],
  });

  /// Converts to a JSON Schema property object.
  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
      };
}
