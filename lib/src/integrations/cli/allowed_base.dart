/// Java `validateWithinAllowedBase` parity for CLI tool working
/// directories: a caller-supplied directory may only be used when it sits
/// inside one of the allowed base directories (the job base — Java's
/// `user.dir` stand-in, its git repository root, or the system temp dir).
///
/// Shared by both surfaces of `cli_execute_command` — the synchronous
/// JS-bridge path (ToolBridge) and the async executor (CliToolExecutor) —
/// so the two cannot drift apart on a security-flavored behavior again.
library;

import 'dart:io';
import 'package:path/path.dart' as p;

/// Canonicalizes [dirPath] and validates that it lies within the job
/// [base] directory, its git repository root, or the system temp
/// directory; otherwise throws (Java `SecurityException` parity, rethrown
/// as a JS `Error` on the bridge path).
void validateWithinAllowedBase(String dirPath, String base) {
  final dir = canonicalizePath(dirPath);
  bool within(String? candidate) {
    if (candidate == null) return false;
    return pathIsWithin(dir, canonicalizePath(candidate));
  }

  // The tmpdir candidate is checked before the git root: it answers for
  // the common temp-fixture traffic without spawning a `git rev-parse`
  // subprocess on the synchronous bridge path (gh-365 rework review
  // thread 3); the boolean outcome is unchanged (pure OR).
  if (within(base) || within(Directory.systemTemp.path)) return;
  if (within(gitRepositoryRoot(base))) return;
  throw Exception('Working directory is outside allowed base paths '
      '(user.dir, git root, tmpdir): $dirPath');
}

/// Resolves a `file_*` tool [path] the way Java `FileTools` does —
/// relative paths against the job [base], lexical `.`/`..` normalization
/// (Java `Path.normalize()` parity) — and validates that the result lies
/// within [base], its git repository root, or the system temp directory;
/// returns the validated absolute path, or throws (Java `FileTools`
/// `"Path traversal attempt blocked"` parity, surfaced as the standard
/// error envelope on the bridge path).
///
/// When the containment checks fail, [configuredAllowedPaths] — the raw
/// `DMTOOLS_FILE_READ_ALLOWED_PATHS` value (Java
/// `PropertyReader.getFileReadAllowedPaths` parity) — is consulted as a
/// last escape hatch (gh-367): a comma-separated glob list whose matches
/// are accepted, exactly what Java `FileTools.isAllowedByConfig` grants
/// its read-flavored tools (`file_read`, `file_exists`, `file_list`).
/// Callers pick the flavor: Java's write path (`writeFile`/`deleteFile`)
/// never consults the config, so write operations pass null here.
///
/// Shared by both surfaces of the `file_*` family — the synchronous
/// JS-bridge path (ToolBridge) and the async executor (FileToolExecutor) —
/// so the two cannot drift apart on a security-flavored behavior again,
/// the same contract [validateWithinAllowedBase] gives `cli_execute_command`.
///
/// The normalization happens BEFORE the containment check: a not-yet-
/// existing escape target has no filesystem entry to canonicalize, so
/// skipping it would let `base/sub/../outside` pass a raw prefix match
/// and materialize outside the base on write. [canonicalizePath] also
/// resolves planned paths through their deepest existing ancestor, so
/// the symlink guarantee covers the whole resolved path — an in-base
/// link (as the target or as a parent of a planned write) pointing
/// outside is rejected, and symlink-flavored tmpdir prefixes (macOS
/// `/var/folders/...` → `/private/var/...`) compare equal to their
/// canonical candidates instead of false-rejecting. It scopes to the
/// resolved path argument: the executor's recursive traversals pass
/// `followLinks: false` (Java `Files.walk` parity), so traversal cannot
/// leak outside entries either.
String resolveWithinAllowedBase(
  String path,
  String base, {
  String? configuredAllowedPaths,
}) {
  final resolved =
      canonicalizePath(p.normalize(p.isAbsolute(path) ? path : '$base/$path'));
  bool within(String? candidate) {
    if (candidate == null) return false;
    return pathIsWithin(resolved, canonicalizePath(candidate));
  }

  // Tmpdir before git root: no `git rev-parse` spawn for temp-fixture
  // traffic on the synchronous bridge path (gh-365 rework review
  // thread 3); boolean outcome unchanged (pure OR).
  if (within(base) || within(Directory.systemTemp.path)) return resolved;
  if (within(gitRepositoryRoot(base))) return resolved;
  if (isAllowedByConfig(resolved, base, configuredAllowedPaths)) {
    return resolved;
  }
  throw Exception('Path traversal attempt blocked: $path '
      '(resolved: $resolved, working dir: $base)');
}

/// Canonical form of [path]: resolves symlinks for the deepest existing
/// ancestor and appends the non-existent remainder lexically, so planned
/// writes (final component not on disk yet) still see through symlinked
/// parents — the symlink-escape hole and the macOS `/var` → `/private/var`
/// first-write false rejections share this root cause (gh-365 rework:
/// a fully lexical fallback left symlinked ancestors unresolved while
/// every allowed-base candidate was canonicalized).
///
/// Falls back to the fully lexical [path] when nothing up to the
/// filesystem root can be resolved (e.g. a symlink loop — `realpath(3)`
/// fails the same way). Public so the planned-path/symlink semantics are
/// testable portably, the same way [pathIsWithin] exposes the
/// separator-sensitive containment for Windows tests.
String canonicalizePath(String path) {
  final trail = <String>[];
  var current = path;
  while (true) {
    try {
      final head = Directory(current).resolveSymbolicLinksSync();
      return trail.isEmpty
          ? head
          : p.normalize(p.joinAll([head, ...trail.reversed]));
    } catch (_) {
      final parent = p.dirname(current);
      if (parent == current) return path;
      trail.add(p.basename(current));
      current = parent;
    }
  }
}

/// Returns `true` when the canonical [dir] equals [base] or lies inside
/// it, comparing path prefixes with [separator] (null — the default —
/// means [Platform.pathSeparator]).
///
/// Java `Path.startsWith` parity: separator-aware, so Windows
/// backslash-separated paths (`Directory.resolveSymbolicLinksSync`
/// returns those there) behave exactly like POSIX ones — a hard-coded
/// `/` separator would false-reject legitimate nested directories on
/// Windows (`C:\src\repo\sub` within `C:\src\repo`) on the allow-list
/// side of the sandbox check.
bool pathIsWithin(String dir, String base, {String? separator}) {
  final sep = separator ?? Platform.pathSeparator;
  if (dir == base) return true;
  if (base.isEmpty) return false;
  return dir.startsWith('$base$sep');
}

/// Detects the git repository root containing [base], or `null` when
/// [base] is not inside a repository (Java `resolveWorkingDirectory`
/// git-root detection parity).
String? gitRepositoryRoot(String base) {
  try {
    final result = Process.runSync(
        'git', const ['rev-parse', '--show-toplevel'],
        workingDirectory: base);
    final root = result.stdout.toString().trim();
    if (result.exitCode == 0 &&
        root.isNotEmpty &&
        Directory(root).existsSync()) {
      return root;
    }
  } catch (_) {}
  return null;
}

/// Returns `true` when the resolved [path] matches at least one of the
/// comma-separated glob patterns in [raw] — the `DMTOOLS_FILE_READ_ALLOWED_PATHS`
/// value — after each pattern's literal prefix is resolved against
/// [workingDir] (Java `FileTools.isAllowedByConfig` parity, gh-367).
///
/// A null/blank [raw] allows nothing (Java returns false the same way), a
/// pattern that fails to parse is skipped so the remaining patterns still
/// get their chance (Java logs a warning and continues), and matching is
/// case-sensitive with `/` as the glob separator on every platform.
bool isAllowedByConfig(String path, String workingDir, String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  for (final rawPattern in raw.split(',')) {
    final pattern = rawPattern.trim();
    if (pattern.isEmpty) continue;
    try {
      if (matchesPattern(path, workingDir, pattern)) return true;
    } catch (_) {
      // Malformed pattern: Java warns and keeps evaluating the rest.
    }
  }
  return false;
}

/// Tests whether the resolved [path] matches a single [rawPattern] from
/// the allow-list (Java `FileTools.matchesPattern` parity — package
/// private there, public here for the same testability reason).
///
/// - No wildcard at all → exact match of `workingDir` + pattern (Java
///   `Path.resolve` + `normalize` parity, so a relative pattern lands on
///   the sibling-of-workdir shape).
/// - Otherwise the literal prefix before the first wildcard (`*`, `?`,
///   `{`, `[`) resolves against `workingDir` — `../.dmtools/**` names the
///   `.dmtools` directory NEXT TO the working dir — the resolved path
///   must sit under it, and the glob suffix matches the path relative to
///   that base (Java `PathMatcher` glob semantics: `**` crosses directory
///   boundaries, `*`/`?` stay inside one segment, `[...]` classes and
///   `{...}` alternatives per the Java glob grammar).
///
/// Both sides are compared in canonical form ([canonicalizePath]), so a
/// symlinked `~/.dmtools` prefix still matches its configured pattern —
/// the same candidate canonicalization every allowed base gets (gh-365
/// rework semantics).
bool matchesPattern(String path, String workingDir, String rawPattern) {
  final wildcardIdx = indexOfWildcard(rawPattern);
  if (wildcardIdx < 0) {
    final exact = canonicalizePath(p.normalize(p.join(workingDir, rawPattern)));
    return path == exact;
  }
  final slashBefore =
      wildcardIdx == 0 ? -1 : rawPattern.lastIndexOf('/', wildcardIdx - 1);
  final literalPrefix =
      slashBefore >= 0 ? rawPattern.substring(0, slashBefore) : '';
  final globSuffix =
      slashBefore >= 0 ? rawPattern.substring(slashBefore + 1) : rawPattern;
  final absBase = literalPrefix.isEmpty
      ? workingDir
      : p.normalize(p.join(workingDir, literalPrefix));
  final canonicalBase = canonicalizePath(absBase);
  if (!pathIsWithin(path, canonicalBase)) return false;
  final relative = p.relative(path, from: canonicalBase);
  final pattern = RegExp('^${_globToRegexSource(globSuffix)}\$');
  return pattern.hasMatch(_toSlashSegments(relative));
}

/// Returns the index of the first glob wildcard in [s] (`*`, `?`, `{`,
/// `[`) or -1 when there is none (Java `FileTools.indexOfWildcard` parity).
int indexOfWildcard(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '*' || c == '?' || c == '{' || c == '[') return i;
  }
  return -1;
}

/// Translates a Java glob [glob] suffix into a regex source: `**` → `.*`,
/// `*` → `[^/]*`, `?` → `[^/]`, `[...]` and `{...}` per the Java glob
/// grammar (`sun.nio.fs.Globs` semantics), everything else literal.
/// Throws on a malformed class/group so [isAllowedByConfig] can skip the
/// pattern the way Java skips a failing `getPathMatcher` evaluation.
String _globToRegexSource(String glob) {
  final out = StringBuffer();
  var i = 0;
  while (i < glob.length) {
    switch (glob[i]) {
      case '*':
        final doubleStar = i + 1 < glob.length && glob[i + 1] == '*';
        out.write(doubleStar ? '.*' : '[^/]*');
        i += doubleStar ? 2 : 1;
      case '?':
        out.write('[^/]');
        i++;
      case '[':
        i = _writeCharClass(glob, i, out);
      case '{':
        i = _writeAlternatives(glob, i, out);
      default:
        out.write(RegExp.escape(glob[i]));
        i++;
    }
  }
  return out.toString();
}

/// Writes the regex translation of the `[...]` class starting at [start]
/// and returns the index just past its closing `]`. A leading `!`
/// negates (Java glob parity); ranges keep their raw `-` because
/// [RegExp.escape] leaves it untouched.
int _writeCharClass(String glob, int start, StringBuffer out) {
  var i = start + 1;
  if (i < glob.length && glob[i] == '!') {
    out.write('[^');
    i++;
  } else {
    out.write('[');
  }
  while (i < glob.length && glob[i] != ']') {
    out.write(glob[i] == r'\' ? r'\\' : RegExp.escape(glob[i]));
    i++;
  }
  if (i >= glob.length) {
    throw FormatException('Unterminated [class] in pattern: $glob');
  }
  out.write(']');
  return i + 1;
}

/// Writes the regex translation of the `{a,b}` group starting at [start]
/// and returns the index just past its matching `}`. Top-level commas
/// split alternatives (nesting-aware, Java glob parity); each
/// alternative is translated recursively.
int _writeAlternatives(String glob, int start, StringBuffer out) {
  final alternatives = <String>[];
  var depth = 0;
  var i = start;
  var altStart = start + 1;
  while (i < glob.length) {
    final c = glob[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) break;
    }
    if (c == ',' && depth == 1) {
      alternatives.add(glob.substring(altStart, i));
      altStart = i + 1;
    }
    i++;
  }
  if (i >= glob.length) {
    throw FormatException('Unterminated {group} in pattern: $glob');
  }
  alternatives.add(glob.substring(altStart, i));
  out
    ..write('(?:')
    ..write(alternatives.map(_globToRegexSource).join('|'))
    ..write(')');
  return i + 1;
}

/// Converts the platform separators of [relative] to `/` so the glob
/// classes (`[^/]*`) segment on every OS — the Java `PathMatcher` glob
/// separator is `/` regardless of platform.
String _toSlashSegments(String relative) =>
    p.separator == '/' ? relative : relative.replaceAll(p.separator, '/');
