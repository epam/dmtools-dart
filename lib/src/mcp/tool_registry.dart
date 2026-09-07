import 'tool_definition.dart';

/// Registry of all MCP tools, keyed by tool name.
///
/// Mirrors the Java generated `MCPToolRegistry`: tools are registered at
/// startup, filtered by the configured integrations for `dmtools list`,
/// and dispatched by name (or alias) for `dmtools <tool_name>`.
class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};
  final Map<String, String> _aliasToName = {};

  /// Registers a tool definition.
  ///
  /// If a tool with the same name is already registered, it is replaced.
  /// Each alias in [ToolDefinition.aliases] is mapped to the tool name,
  /// overwriting any earlier alias binding.
  void register(ToolDefinition tool) {
    _tools[tool.name] = tool;
    for (final alias in tool.aliases) {
      _aliasToName[alias] = tool.name;
    }
  }

  /// Registers multiple tool definitions.
  void registerAll(Iterable<ToolDefinition> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// Returns `true` if [name] is a known tool name or alias.
  bool hasTool(String name) =>
      _tools.containsKey(name) || _aliasToName.containsKey(name);

  /// Returns every tool carrying [alias], in registration order.
  ///
  /// Unlike the single-binding [_aliasToName] map this keeps all
  /// candidates, mirroring the Java generated registry's
  /// `ALIAS_TO_TOOL_NAMES` multimap (one alias may be carried by several
  /// integrations, e.g. `tracker_get_ticket` on jira and ado).
  List<ToolDefinition> toolsByAlias(String alias) =>
      _tools.values.where((t) => t.aliases.contains(alias)).toList();

  /// Resolves a tool name or alias to the canonical tool name.
  ///
  /// Returns `null` when [name] is neither a registered tool nor an alias.
  String? resolveName(String name) {
    if (_tools.containsKey(name)) return name;
    return _aliasToName[name];
  }

  /// Resolves [name] following the Java `McpCliHandler.resolveToolAlias`
  /// contract.
  ///
  /// A registered canonical name resolves to itself. An alias with exactly
  /// one carrier resolves to that carrier. An alias carried by several
  /// integrations picks the carrier matching the configured default
  /// integration: [defaultTracker] for `tracker_*` aliases and
  /// [defaultSourceCode] for `source_code_*` aliases (values are trimmed
  /// and lowercased like Java's env reads; other aliases ignore both).
  /// Anything unresolved falls back to the first candidate. Returns `null`
  /// when [name] is unknown.
  String? resolveToolAlias(
    String name, {
    String? defaultTracker,
    String? defaultSourceCode,
  }) {
    if (_tools.containsKey(name)) return name;
    final candidates = toolsByAlias(name);
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.name;
    final wanted = _defaultIntegrationFor(
      name,
      defaultTracker: defaultTracker,
      defaultSourceCode: defaultSourceCode,
    );
    if (wanted != null) {
      for (final candidate in candidates) {
        if (candidate.integration == wanted) return candidate.name;
      }
    }
    return candidates.first.name;
  }

  /// The integration name configured for [alias]'s prefix, if any.
  ///
  /// Java `McpCliHandler.resolveDefaultIntegrationForAlias` reads
  /// `DEFAULT_TRACKER` for `tracker_*` and `DEFAULT_SOURCE_CODE` for
  /// `source_code_*`; both are trimmed and lowercased before matching.
  String? _defaultIntegrationFor(
    String alias, {
    String? defaultTracker,
    String? defaultSourceCode,
  }) {
    final raw = alias.startsWith('tracker_')
        ? defaultTracker
        : alias.startsWith('source_code_')
            ? defaultSourceCode
            : null;
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }

  /// Returns the tool definition for [name], resolving aliases.
  ToolDefinition? getTool(String name) {
    final resolved = resolveName(name);
    return resolved != null ? _tools[resolved] : null;
  }

  /// Returns all registered tools, sorted alphabetically by name.
  List<ToolDefinition> get allTools =>
      _tools.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Returns tools for the given integrations, or all when [integrations]
  /// is `null`. Results are sorted alphabetically by name.
  List<ToolDefinition> toolsForIntegrations([Set<String>? integrations]) {
    if (integrations == null) return allTools;
    return _tools.values
        .where((t) => integrations.contains(t.integration))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Returns the set of integrations that have at least one tool.
  Set<String> get availableIntegrations =>
      _tools.values.map((t) => t.integration).toSet();

  /// Generates the `dmtools list` response in MCP protocol format.
  ///
  /// When [integrations] is given, only tools from those integrations are
  /// included; otherwise every registered tool is returned.
  Map<String, dynamic> generateToolsListResponse([Set<String>? integrations]) {
    final tools = toolsForIntegrations(integrations);
    return {
      'tools': tools.map((t) => t.toJson()).toList(),
    };
  }

  /// Filters a tools list response by a case-insensitive substring match on
  /// the tool name or description.
  Map<String, dynamic> filterToolsList(
    Map<String, dynamic> toolsList,
    String filter,
  ) {
    final lowerFilter = filter.toLowerCase();
    final tools = toolsList['tools'] as List;
    final filtered = tools.where((t) {
      final map = t as Map<String, dynamic>;
      return (map['name'] as String).toLowerCase().contains(lowerFilter) ||
          (map['description'] as String).toLowerCase().contains(lowerFilter);
    }).toList();
    return {'tools': filtered};
  }

  /// Clears all registered tools and aliases (for testing).
  void clear() {
    _tools.clear();
    _aliasToName.clear();
  }
}
