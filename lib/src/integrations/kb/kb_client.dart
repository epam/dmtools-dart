/// Knowledge-base client for local Markdown operations.
///
/// Ports the `kb_*` tool surface from the Java DMTools catalog using
/// `dart:io` only — no HTTP transport is involved. Documents live as
/// `.md` files beneath the knowledge-base [KbClient.root] directory.
library;

import 'dart:io';

/// Matches a Markdown ATX heading line: 1–6 `#` and an optional title.
final RegExp _markdownHeading = RegExp(r'^(#{1,6})(?:\s+(.*?))?\s*$');

/// A single full-text match inside a knowledge-base document.
class KbSearchResult {
  /// Absolute path of the matching Markdown file.
  final String path;

  /// 1-based line number of the match.
  final int lineNumber;

  /// The matched line, trimmed of surrounding whitespace.
  final String snippet;

  /// Creates a search result.
  const KbSearchResult({
    required this.path,
    required this.lineNumber,
    required this.snippet,
  });

  /// Converts to MCP protocol JSON.
  Map<String, dynamic> toJson() => {
        'path': path,
        'line': lineNumber,
        'snippet': snippet,
      };
}

/// Filesystem-backed client for knowledge-base Markdown operations.
///
/// Every [path]/[dir] argument is resolved against [root] when it is not
/// absolute, so callers may pass either KB-relative or absolute paths.
class KbClient {
  /// Root directory of the knowledge base.
  final String root;

  /// Creates a client rooted at [root].
  KbClient(this.root);

  /// Resolves [path] against [root], returning [root] for `.`/empty.
  String _resolve(String path) {
    if (path.isEmpty || path == '.') return root;
    if (File(path).isAbsolute) return path;
    return root.endsWith('/') ? '$root$path' : '$root/$path';
  }

  /// Full-text searches the `.md` files under [root] for [query].
  ///
  /// Matching is case-insensitive and substring-based. Throws
  /// [ArgumentError] when [query] is empty.
  Future<List<KbSearchResult>> searchDocs(String query) async {
    if (query.isEmpty) {
      throw ArgumentError('Query must not be empty');
    }
    final needle = query.toLowerCase();
    final results = <KbSearchResult>[];
    for (final file in await indexDocs('.')) {
      results.addAll(_searchFile(file, needle));
    }
    return results;
  }

  /// Full-text searches like [searchDocs], capped at [maxResults] matches.
  ///
  /// Throws [ArgumentError] when [query] is empty or [maxResults] is
  /// negative.
  Future<List<KbSearchResult>> searchDocsFull(
    String query,
    int maxResults,
  ) async {
    if (maxResults < 0) {
      throw ArgumentError('maxResults must not be negative');
    }
    final results = await searchDocs(query);
    return results.take(maxResults).toList();
  }

  /// Reads and returns the Markdown content of the document at [path].
  ///
  /// Throws [FileSystemException] when the document does not exist.
  Future<String> getDoc(String path) => File(_resolve(path)).readAsString();

  /// Recursively lists every `.md` file under [dir], sorted by path.
  ///
  /// Returns an empty list when [dir] does not exist.
  Future<List<String>> indexDocs(String dir) async {
    final directory = Directory(_resolve(dir));
    if (!await directory.exists()) return const [];
    final files = <String>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.md')) {
        files.add(entity.path);
      }
    }
    files.sort();
    return files;
  }

  /// Lists the immediate subdirectories of [basePath], sorted by path.
  ///
  /// Only direct children are returned (non-recursive). Returns an empty
  /// list when [basePath] does not exist.
  Future<List<String>> listDirs(String basePath) async {
    final directory = Directory(_resolve(basePath));
    if (!await directory.exists()) return const [];
    final dirs = <String>[];
    await for (final entity in directory.list()) {
      if (entity is Directory) dirs.add(entity.path);
    }
    dirs.sort();
    return dirs;
  }

  /// Writes [content] to the document at [path], creating any missing parent
  /// directories, and returns the resolved path.
  ///
  /// Existing documents are overwritten. Throws [ArgumentError] when [path]
  /// does not name a file inside the knowledge base.
  Future<String> createDoc(String path, String content) async {
    if (path.isEmpty || path == '.') {
      throw ArgumentError('Path must not be empty');
    }
    final file = File(_resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file.path;
  }

  /// Deletes the document at [path] and returns the resolved path.
  ///
  /// Throws [FileSystemException] when the document does not exist.
  Future<String> deleteDoc(String path) async {
    final file = File(_resolve(path));
    await file.delete();
    return file.path;
  }

  /// Replaces the body of [section] in the document at [path] with [content].
  ///
  /// A section runs from its heading line until the next heading of the same
  /// or higher level. Throws [FileSystemException] when the document is
  /// missing and [ArgumentError] when no heading matches [section]. Returns
  /// the updated document content.
  Future<String> updateDoc(String path, String section, String content) async {
    final file = File(_resolve(path));
    final updated =
        _replaceSection(await file.readAsString(), section, content);
    await file.writeAsString(updated);
    return updated;
  }

  /// Rebuilds [source] with the body of [section] swapped for [replacement].
  String _replaceSection(String source, String section, String replacement) {
    final lines = source.split('\n');
    final start = _findHeading(lines, section);
    if (start < 0) {
      throw ArgumentError('Section not found: $section');
    }
    final level = _headingLevel(lines[start]);
    final end = _findSectionEnd(lines, start + 1, level);
    final body = replacement.trim().split('\n');
    return [...lines.sublist(0, start + 1), '', ...body, ..._tail(lines, end)]
        .join('\n');
  }

  /// Index of the heading whose title equals [section], or `-1`.
  int _findHeading(List<String> lines, String section) {
    for (var i = 0; i < lines.length; i++) {
      final match = _markdownHeading.firstMatch(lines[i]);
      if (match != null && (match.group(2) ?? '') == section) return i;
    }
    return -1;
  }

  /// Index of the first heading at or above [level] after [from].
  int _findSectionEnd(List<String> lines, int from, int level) {
    for (var i = from; i < lines.length; i++) {
      final current = _headingLevel(lines[i]);
      if (current > 0 && current <= level) return i;
    }
    return lines.length;
  }

  /// Heading level (1–6) of [line], or `0` when it is not a heading.
  int _headingLevel(String line) =>
      _markdownHeading.firstMatch(line)?.group(1)?.length ?? 0;

  /// A blank-line separator plus the remainder, or nothing at end of file.
  List<String> _tail(List<String> lines, int end) =>
      end >= lines.length ? const [] : ['', ...lines.sublist(end)];

  /// Collects case-insensitive [needle] matches from [file]'s lines.
  List<KbSearchResult> _searchFile(String file, String needle) {
    final results = <KbSearchResult>[];
    final lines = File(file).readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(needle)) {
        results.add(
          KbSearchResult(
            path: file,
            lineNumber: i + 1,
            snippet: lines[i].trim(),
          ),
        );
      }
    }
    return results;
  }
}
