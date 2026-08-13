/// Knowledge-base client for local Markdown operations.
///
/// Ports the `kb_*` tool surface from the Java DMTools catalog using
/// `dart:io` only — no HTTP transport is involved. Documents live as
/// `.md` files beneath the knowledge-base [KbClient.root] directory.
library;

import 'dart:io';

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
