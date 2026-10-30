/// MCP tool definitions and dispatcher for the Atlassian Rovo integration.
///
/// The tool list ports the Rovo subset of the Java `@MCPTool` catalog
/// (`rovo_search`, `rovo_summarize`, `rovo_context`, `rovo_ask`); the executor
/// routes a tool name + arguments to the matching [RovoClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'rovo_client.dart';

const _cloudIdParam = ToolParam(
  name: 'cloudId',
  description: 'Optional Atlassian Cloud ID (falls back to ROVO_CLOUD_ID)',
  required: false,
);

/// Returns all Atlassian Rovo MCP tool definitions (`rovo_*`).
List<ToolDefinition> rovoTools() => [
      _searchTool(),
      _summarizeTool(),
      _contextTool(),
      _askTool(),
    ];

ToolDefinition _searchTool() => const ToolDefinition(
      name: 'rovo_search',
      description:
          'Semantic natural-language search across Confluence, Jira, and connected third-party sources via Atlassian Rovo MCP (STANDARD mode). Returns ranked hits with snippets.',
      integration: 'rovo',
      category: 'search',
      params: [
        ToolParam(
          name: 'query',
          description: 'Natural-language search query',
          required: true,
        ),
        _cloudIdParam,
        ToolParam(
          name: 'targetApp',
          description:
              "Optional target application filter (e.g., 'confluence', 'jira')",
          required: false,
        ),
        ToolParam(
          name: 'limit',
          description: 'Optional maximum number of search results to return',
          type: 'number',
          required: false,
        ),
      ],
    );

ToolDefinition _summarizeTool() => const ToolDefinition(
      name: 'rovo_summarize',
      description:
          'Get an AI-generated summary of a Confluence page via Atlassian Rovo MCP (getConfluenceContent with detail=ai_summary) without downloading the full page body.',
      integration: 'rovo',
      category: 'content',
      params: [
        ToolParam(
          name: 'contentId',
          description: 'Confluence page or content ID to summarize',
          required: true,
        ),
        _cloudIdParam,
      ],
    );

ToolDefinition _contextTool() => const ToolDefinition(
      name: 'rovo_context',
      description:
          'Fetch cross-product graph context and linked relationships (issues, pages, PRs, repositories, goals, people) for an Atlassian object via Rovo MCP getGraphContext.',
      integration: 'rovo',
      category: 'graph',
      params: [
        ToolParam(
          name: 'objectType',
          description:
              "Type of the object to inspect (e.g., 'jira:issue', 'confluence:page', 'ari')",
          required: true,
        ),
        ToolParam(
          name: 'identifier',
          description:
              "Object identifier (e.g., issue key 'PROJ-123', page ID, or full ARI)",
          required: true,
        ),
        _cloudIdParam,
      ],
    );

ToolDefinition _askTool() => const ToolDefinition(
      name: 'rovo_ask',
      description:
          'Ask a natural-language question via Atlassian Rovo MCP AGENTIC search mode for a cited answer. Automatically falls back to STANDARD semantic search if Agentic search returns 403 or is not enabled on the site.',
      integration: 'rovo',
      category: 'qa',
      params: [
        ToolParam(
          name: 'question',
          description: 'Natural-language question to ask Rovo',
          required: true,
        ),
        _cloudIdParam,
      ],
    );

/// Executes Rovo MCP tools by dispatching to [RovoClient].
class RovoToolExecutor {
  final RovoClient _client;

  /// Creates an executor bound to [_client].
  RovoToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Rovo tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Rovo tool: $toolName');
    }
    return handler(args);
  }

  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'rovo_search': (a) => _client.rovoSearch(
          query: _reqStr(a, 'query'),
          cloudId: _optStr(a, 'cloudId'),
          targetApp: _optStr(a, 'targetApp'),
          limit: _optInt(a, 'limit'),
        ),
    'rovo_summarize': (a) => _client.rovoSummarize(
          contentId: _reqStr(a, 'contentId'),
          cloudId: _optStr(a, 'cloudId'),
        ),
    'rovo_context': (a) => _client.rovoContext(
          objectType: _reqStr(a, 'objectType'),
          identifier: _reqStr(a, 'identifier'),
          cloudId: _optStr(a, 'cloudId'),
        ),
    'rovo_ask': (a) => _client.rovoAsk(
          question: _reqStr(a, 'question'),
          cloudId: _optStr(a, 'cloudId'),
        ),
  };

  static String _reqStr(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) throw ArgumentError('Missing required parameter: $key');
    return v.toString();
  }

  static String? _optStr(Map<String, dynamic> args, String key) {
    final v = args[key];
    return v?.toString();
  }

  static int? _optInt(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String && v.trim().isNotEmpty) return int.tryParse(v.trim());
    return null;
  }
}
