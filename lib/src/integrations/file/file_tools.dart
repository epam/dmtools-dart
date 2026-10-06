/// MCP tool definitions and executor for file-system operations.
///
/// Ports the `file_*` tools from the Java DMTools `@MCPTool` catalog.
/// All operations use `dart:io` directly.
library;

import 'dart:convert';
import 'dart:io';

import '../../integrations/cli/allowed_base.dart';
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
      _readJsonTool(),
      _writeJsonTool(),
      _existsInPathTool(),
      _getSizeTool(),
      _watchTool(),
      _renameTool(),
      _searchTool(),
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

/// `file_read_json` — read a file and parse it as JSON.
ToolDefinition _readJsonTool() => ToolDefinition(
      name: 'file_read_json',
      description: 'Read a file and parse it as JSON',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to read'),
      ],
    );

/// `file_write_json` — serialize a map to a file as JSON.
ToolDefinition _writeJsonTool() => ToolDefinition(
      name: 'file_write_json',
      description: 'Write a map to a file as JSON',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to write'),
        ToolParam(
          name: 'data',
          description: 'The map to serialize',
          type: 'object',
        ),
      ],
    );

/// `file_exists_in_path` — search for a file by name within a directory tree.
ToolDefinition _existsInPathTool() => ToolDefinition(
      name: 'file_exists_in_path',
      description: 'Search for a file by name within a directory tree',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'Root directory to search'),
        ToolParam(name: 'filename', description: 'File name to find'),
      ],
    );

/// `file_get_size` — return the size of a file in bytes.
ToolDefinition _getSizeTool() => ToolDefinition(
      name: 'file_get_size',
      description: 'Return the size of a file in bytes',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to measure'),
      ],
    );

/// `file_watch` — return a file's last-modified time and size.
ToolDefinition _watchTool() => ToolDefinition(
      name: 'file_watch',
      description: 'Return a file\'s last-modified time and size as a map',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'path', description: 'File path to watch'),
      ],
    );

/// `file_rename` — rename a file (alias of move).
ToolDefinition _renameTool() => ToolDefinition(
      name: 'file_rename',
      description: 'Rename (move) a file from source to destination',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'source', description: 'Source file path'),
        ToolParam(name: 'dest', description: 'Destination file path'),
      ],
    );

/// `file_search` — recursively search for files matching a glob pattern.
ToolDefinition _searchTool() => ToolDefinition(
      name: 'file_search',
      description: 'Recursively search a directory for files matching a glob '
          'pattern (supports * and ?)',
      integration: 'file',
      category: 'filesystem',
      params: [
        ToolParam(name: 'dir', description: 'Root directory to search'),
        ToolParam(name: 'pattern', description: 'Glob pattern, e.g. *.dart'),
      ],
    );

/// Executes file MCP tools using `dart:io`.
///
/// Each method performs a single file-system operation; [execute] dispatches
/// by tool name, mirroring the Java method-routing pattern.
///
/// gh-365: every operation sandboxes its paths through
/// [resolveWithinAllowedBase] — the same shared check the synchronous
/// JS-bridge path applies — so paths outside the job base, its git
/// repository root, or the system temp dir throw before any filesystem
/// access (Java `FileTools` "Path traversal attempt blocked" parity).
///
/// Every operation reports failures through its returned Future —
/// sandbox rejections included — so callers get one uniform async error
/// channel; no method throws synchronously.
class FileToolExecutor {
  /// The job base directory: relative paths resolve against it and it is
  /// the first allowed base of the sandbox check (the Java `user.dir`
  /// stand-in).
  final String _base;

  /// Creates a file tool executor.
  ///
  /// [base] overrides the job base directory (defaults to the process
  /// CWD).
  FileToolExecutor({String? base}) : _base = base ?? Directory.current.path;

  /// Sandboxes [path] per the shared `file_*` containment check (gh-365).
  String _check(String path) => resolveWithinAllowedBase(path, _base);

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
  Future<String> read(String path) async => File(_check(path)).readAsString();

  /// Writes [content] to the file at [path], creating or overwriting it.
  ///
  /// Creates any missing parent directories first, matching the Java
  /// DMTools `FileUtils.writeStringToFile` behavior. The path is
  /// sandbox-checked first (gh-365), so the parent creation cannot reach
  /// outside the allowed bases.
  Future<void> write(String path, String content) async {
    final checked = _check(path);
    final parent = File(checked).parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    await File(checked).writeAsString(content);
  }

  /// Lists the entry paths inside the directory at [path].
  Future<List<String>> list(String path) async =>
      Directory(_check(path)).list().map((e) => e.path).toList();

  /// Returns `true` if a file or directory exists at [path].
  Future<bool> exists(String path) async {
    final checked = _check(path);
    return File(checked).existsSync() || Directory(checked).existsSync();
  }

  /// Deletes the file at [path]; returns `true` if it existed.
  Future<bool> delete(String path) async {
    final file = File(_check(path));
    if (file.existsSync()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Copies the file at [source] to [dest].
  Future<void> copy(String source, String dest) async =>
      File(_check(source)).copy(_check(dest));

  /// Moves (renames) the file at [source] to [dest].
  Future<void> move(String source, String dest) async =>
      File(_check(source)).rename(_check(dest));

  /// Creates the directory at [path], including parents.
  Future<void> mkdir(String path) async =>
      Directory(_check(path)).create(recursive: true);

  /// Reads the file at [path] and returns its lines.
  Future<List<String>> readLines(String path) async =>
      File(_check(path)).readAsLines();

  /// Writes [lines] to the file at [path], joined by newlines.
  Future<void> writeLines(String path, List<String> lines) async =>
      File(_check(path)).writeAsString(lines.join('\n'));

  /// Appends [content] to the file at [path], creating it if needed.
  Future<void> append(String path, String content) async =>
      File(_check(path)).writeAsString(content, mode: FileMode.append);

  /// Returns metadata about the file or directory at [path].
  ///
  /// The map contains `exists`, `isDirectory`, `size`, and `modified`.
  Future<Map<String, dynamic>> getFileInfo(String path) async {
    final checked = _check(path);
    final type = FileSystemEntity.typeSync(checked);
    final exists = type != FileSystemEntityType.notFound;
    if (!exists) {
      return const {
        'exists': false,
        'isDirectory': false,
        'size': 0,
        'modified': null,
      };
    }
    final stat = FileStat.statSync(checked);
    return {
      'exists': true,
      'isDirectory': type == FileSystemEntityType.directory,
      'size': stat.size,
      'modified': stat.modified,
    };
  }

  /// Reads the file at [path] and returns its decoded JSON value.
  Future<dynamic> readJson(String path) async {
    final content = await File(_check(path)).readAsString();
    return jsonDecode(content);
  }

  /// Encodes [data] as JSON and writes it to the file at [path].
  Future<void> writeJson(String path, Map<String, dynamic> data) async =>
      File(_check(path)).writeAsString(jsonEncode(data));

  /// Returns `true` if a file named [filename] exists under [path].
  Future<bool> existsInPath(String path, String filename) async {
    final dir = Directory(_check(path));
    if (!dir.existsSync()) return false;
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File && entry.uri.pathSegments.last == filename) {
        return true;
      }
    }
    return false;
  }

  /// Returns the size of the file at [path] in bytes.
  Future<int> getSize(String path) async => File(_check(path)).length();

  /// Returns the last-modified time and size of [path] as a map.
  Future<Map<String, dynamic>> watch(String path) async {
    final stat = await File(_check(path)).stat();
    return {'size': stat.size, 'modified': stat.modified};
  }

  /// Renames (moves) the file at [source] to [dest].
  ///
  /// Equivalent to [move]; provided as an explicit rename entry point.
  Future<void> rename(String source, String dest) => move(source, dest);

  /// Recursively searches [dir] for files whose name matches glob [pattern].
  Future<List<String>> search(String dir, String pattern) async {
    final matcher = _globToRegex(pattern);
    final result = <String>[];
    final root = Directory(_check(dir));
    if (!root.existsSync()) return result;
    await for (final entry in root.list(recursive: true)) {
      if (entry is File && matcher.hasMatch(entry.uri.pathSegments.last)) {
        result.add(entry.path);
      }
    }
    return result;
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
    'file_read_json': (a) => readJson(a['path'] as String),
    'file_write_json': (a) => writeJson(
          a['path'] as String,
          (a['data'] as Map).cast<String, dynamic>(),
        ),
    'file_exists_in_path': (a) => existsInPath(
          a['path'] as String,
          a['filename'] as String,
        ),
    'file_get_size': (a) => getSize(a['path'] as String),
    'file_watch': (a) => watch(a['path'] as String),
    'file_rename': (a) => rename(a['source'] as String, a['dest'] as String),
    'file_search': (a) => search(a['dir'] as String, a['pattern'] as String),
  };
}

/// Converts a glob [pattern] (`*` and `?`) into a matching [RegExp].
RegExp _globToRegex(String pattern) {
  final escaped = RegExp.escape(pattern);
  final star = escaped.replaceAll('\\*', '.*');
  final question = star.replaceAll('\\?', '.');
  return RegExp('^$question\$');
}
