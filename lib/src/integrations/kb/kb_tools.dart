/// MCP tool definitions and executor for knowledge-base operations.
///
/// Ports the `kb_*` tools from the Java DMTools `@MCPTool` catalog. All
/// operations run against the local KB directory via [KbClient].
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'kb_client.dart';

/// Returns all knowledge-base MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> kbTools() => [
      _searchTool(),
      _getDocTool(),
      _indexTool(),
      _createDocTool(),
      _deleteDocTool(),
      _updateDocTool(),
    ];

/// `kb_search_docs` — full-text search across knowledge-base documents.
ToolDefinition _searchTool() => ToolDefinition(
      name: 'kb_search_docs',
      description: 'Search knowledge-base Markdown documents for a query',
      integration: 'kb',
      category: 'docs',
      params: [
        ToolParam(name: 'query', description: 'The text to search for'),
      ],
    );

/// `kb_get_doc` — read a single knowledge-base document.
ToolDefinition _getDocTool() => ToolDefinition(
      name: 'kb_get_doc',
      description: 'Read a knowledge-base Markdown document by path',
      integration: 'kb',
      category: 'docs',
      params: [
        ToolParam(name: 'path', description: 'Path of the document to read'),
      ],
    );

/// `kb_index_docs` — list every document under a KB directory.
ToolDefinition _indexTool() => ToolDefinition(
      name: 'kb_index_docs',
      description: 'List all Markdown files in the knowledge base recursively',
      integration: 'kb',
      category: 'docs',
      params: [
        ToolParam(
          name: 'dir',
          description: 'Directory to index (defaults to the KB root)',
          required: false,
        ),
      ],
    );

/// `kb_create_doc` — write a new knowledge-base document.
ToolDefinition _createDocTool() => ToolDefinition(
      name: 'kb_create_doc',
      description: 'Create a knowledge-base Markdown document with content',
      integration: 'kb',
      category: 'docs',
      params: [
        ToolParam(name: 'path', description: 'Path of the document to create'),
        ToolParam(
          name: 'content',
          description: 'Markdown content of the new document',
        ),
      ],
    );

/// `kb_delete_doc` — delete a knowledge-base document.
ToolDefinition _deleteDocTool() => ToolDefinition(
      name: 'kb_delete_doc',
      description: 'Delete a knowledge-base Markdown document by path',
      integration: 'kb',
      category: 'docs',
      params: [
        ToolParam(name: 'path', description: 'Path of the document to delete'),
      ],
    );

/// `kb_update_doc` — replace one section of a knowledge-base document.
ToolDefinition _updateDocTool() => ToolDefinition(
      name: 'kb_update_doc',
      description:
          'Replace the body of a section in a knowledge-base Markdown document',
      integration: 'kb',
      category: 'docs',
      params: [
        ToolParam(name: 'path', description: 'Path of the document to update'),
        ToolParam(
          name: 'section',
          description: 'Heading title of the section to replace',
        ),
        ToolParam(
          name: 'content',
          description: 'New Markdown body for the section',
        ),
      ],
    );

/// Executes knowledge-base MCP tools by dispatching to [KbClient].
class KbToolExecutor {
  final KbClient _client;

  /// Creates an executor bound to [_client].
  KbToolExecutor(this._client);

  /// Dispatches [toolName] with [args] to the matching KB operation.
  ///
  /// Throws [ArgumentError] for an unknown KB tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown KB tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'kb_search_docs': (a) => _client.searchDocs(a['query'] as String),
    'kb_get_doc': (a) => _client.getDoc(a['path'] as String),
    'kb_index_docs': (a) => _client.indexDocs((a['dir'] as String?) ?? '.'),
    'kb_create_doc': (a) =>
        _client.createDoc(a['path'] as String, a['content'] as String),
    'kb_delete_doc': (a) => _client.deleteDoc(a['path'] as String),
    'kb_update_doc': (a) => _client.updateDoc(
        a['path'] as String, a['section'] as String, a['content'] as String),
  };
}
