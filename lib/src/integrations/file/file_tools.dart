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
      _copyTool(),
      _moveTool(),
      _mkdirTool(),
      _readLinesTool(),
      _writeLinesTool(),
      _appendTool(),
      _infoTool(),
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

/// `file_copy` — copy a file from source to destination.
ToolDefinition _copyTool() => ToolDefinition(
      name: 'file_copy',
      description: 'Copy a file from source to destination',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'source', description: 'Source file path'),
        ToolParam(name: 'dest', description: 'Destination file path'),
      ],
    );

/// `file_move` — move or rename a file.
ToolDefinition _moveTool() => ToolDefinition(
      name: 'file_move',
      description: 'Move or rename a file',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'source', description: 'Source file path'),
        ToolParam(name: 'dest', description: 'Destination file path'),
      ],
    );

/// `file_mkdir` — create a directory (including parents).
ToolDefinition _mkdirTool() => ToolDefinition(
      name: 'file_mkdir',
      description: 'Create a directory, including parents',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'Directory path to create'),
      ],
    );

/// `file_read_lines` — read a file and return its lines.
ToolDefinition _readLinesTool() => ToolDefinition(
      name: 'file_read_lines',
      description: 'Read a file and return its lines as a list',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to read'),
      ],
    );

/// `file_write_lines` — write a list of lines to a file.
ToolDefinition _writeLinesTool() => ToolDefinition(
      name: 'file_write_lines',
      description: 'Write a list of lines to a file, joined by newlines',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to write'),
        ToolParam(name: 'lines', description: 'Lines to write', type: 'array'),
      ],
    );

/// `file_append` — append content to a file.
ToolDefinition _appendTool() => ToolDefinition(
      name: 'file_append',
      description: 'Append content to the end of a file',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to append to'),
        ToolParam(name: 'content', description: 'The text content to append'),
      ],
    );

/// `file_info` — return metadata about a file or directory.
ToolDefinition _infoTool() => ToolDefinition(
      name: 'file_info',
      description: 'Return file metadata: size, modified, isDirectory, exists',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'Path to inspect'),
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

  /// Copies the file at [source] to [dest].
  Future<void> copy(String source, String dest) => File(source).copy(dest);

  /// Moves (renames) the file at [source] to [dest].
  Future<void> move(String source, String dest) => File(source).rename(dest);

  /// Creates the directory at [path], including parents.
  Future<void> mkdir(String path) => Directory(path).create(recursive: true);

  /// Reads the file at [path] and returns its lines.
  Future<List<String>> readLines(String path) => File(path).readAsLines();

  /// Writes [lines] to the file at [path], joined by newlines.
  Future<void> writeLines(String path, List<String> lines) =>
      File(path).writeAsString(lines.join('\n'));

  /// Appends [content] to the file at [path], creating it if needed.
  Future<void> append(String path, String content) =>
      File(path).writeAsString(content, mode: FileMode.append);

  /// Returns metadata about the file or directory at [path].
  ///
  /// The map contains `exists`, `isDirectory`, `size`, and `modified`.
  Future<Map<String, dynamic>> getFileInfo(String path) async {
    final type = FileSystemEntity.typeSync(path);
    final exists = type != FileSystemEntityType.notFound;
    if (!exists) {
      return const {
        'exists': false,
        'isDirectory': false,
        'size': 0,
        'modified': null,
      };
    }
    final stat = FileStat.statSync(path);
    return {
      'exists': true,
      'isDirectory': type == FileSystemEntityType.directory,
      'size': stat.size,
      'modified': stat.modified,
    };
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'file_read': (a) => read(a['path'] as String),
    'file_write': (a) => write(a['path'] as String, a['content'] as String),
    'file_list': (a) => list(a['path'] as String),
    'file_exists': (a) => exists(a['path'] as String),
    'file_delete': (a) => delete(a['path'] as String),
    'file_copy': (a) => copy(a['source'] as String, a['dest'] as String),
    'file_move': (a) => move(a['source'] as String, a['dest'] as String),
    'file_mkdir': (a) => mkdir(a['path'] as String),
    'file_read_lines': (a) => readLines(a['path'] as String),
    'file_write_lines': (a) => writeLines(
          a['path'] as String,
          (a['lines'] as List).cast<String>(),
        ),
    'file_append': (a) => append(a['path'] as String, a['content'] as String),
    'file_info': (a) => getFileInfo(a['path'] as String),
  };
}
