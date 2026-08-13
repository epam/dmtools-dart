/// MCP tool definitions and executor for file-system operations.
///
/// Ports the `file_*` tools from the Java DMTools `@MCPTool` catalog.
/// All operations use `dart:io` directly.
library;

import 'dart:io';

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';

/// Returns all file MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> fileTools() => [
      _readTool(),
      _writeTool(),
      _listTool(),
      _existsTool(),
      _deleteTool(),
    ];

/// `file_read` — read the contents of a text file.
ToolDefinition _readTool() => ToolDefinition(
      name: 'file_read',
      description: 'Read the contents of a text file',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to read'),
      ],
    );

/// `file_write` — write content to a file, creating or overwriting it.
ToolDefinition _writeTool() => ToolDefinition(
      name: 'file_write',
      description: 'Write content to a file, creating or overwriting it',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to write'),
        ToolParam(name: 'content', description: 'The text content to write'),
      ],
    );

/// `file_list` — list entries in a directory.
ToolDefinition _listTool() => ToolDefinition(
      name: 'file_list',
      description: 'List entries in a directory',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'Directory path to list'),
      ],
    );

/// `file_exists` — check whether a file or directory exists.
ToolDefinition _existsTool() => ToolDefinition(
      name: 'file_exists',
      description: 'Check whether a file or directory exists',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'Path to check'),
      ],
    );

/// `file_delete` — delete a file.
ToolDefinition _deleteTool() => ToolDefinition(
      name: 'file_delete',
      description: 'Delete a file',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'Path of the file to delete'),
      ],
    );

/// Executes file MCP tools using `dart:io`.
///
/// Each method performs a single file-system operation; [execute] dispatches
/// by tool name, mirroring the Java method-routing pattern.
class FileToolExecutor {
  /// Creates a file tool executor.
  FileToolExecutor();

  /// Dispatches [toolName] with [args] to the matching file operation.
  ///
  /// Throws [ArgumentError] for an unknown file tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown file tool: $toolName');
    }
    return handler(args);
  }

  /// Reads and returns the entire contents of the file at [path].
  Future<String> read(String path) => File(path).readAsString();

  /// Writes [content] to the file at [path], creating or overwriting it.
  Future<void> write(String path, String content) =>
      File(path).writeAsString(content);

  /// Lists the entry paths inside the directory at [path].
  Future<List<String>> list(String path) =>
      Directory(path).list().map((e) => e.path).toList();

  /// Returns `true` if a file or directory exists at [path].
  Future<bool> exists(String path) async =>
      File(path).existsSync() || Directory(path).existsSync();

  /// Deletes the file at [path]; returns `true` if it existed.
  Future<bool> delete(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'file_read': (a) => read(a['path'] as String),
    'file_write': (a) => write(a['path'] as String, a['content'] as String),
    'file_list': (a) => list(a['path'] as String),
    'file_exists': (a) => exists(a['path'] as String),
    'file_delete': (a) => delete(a['path'] as String),
  };
}
