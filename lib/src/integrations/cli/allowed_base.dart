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
  final dir = _canonicalizePath(dirPath);
  bool within(String? candidate) {
    if (candidate == null) return false;
    return pathIsWithin(dir, _canonicalizePath(candidate));
  }

  if (within(base) || within(gitRepositoryRoot(base))) return;
  if (within(Directory.systemTemp.path)) return;
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
/// Shared by both surfaces of the `file_*` family — the synchronous
/// JS-bridge path (ToolBridge) and the async executor (FileToolExecutor) —
/// so the two cannot drift apart on a security-flavored behavior again,
/// the same contract [validateWithinAllowedBase] gives `cli_execute_command`.
///
/// The normalization happens BEFORE the containment check: a not-yet-
/// existing escape target has no filesystem entry to canonicalize, so
/// skipping it would let `base/sub/../outside` pass a raw prefix match
/// and materialize outside the base on write. Existing paths are
/// canonicalized through symlinks first, so an in-base link pointing
/// outside is rejected too.
String resolveWithinAllowedBase(String path, String base) {
  final resolved =
      _canonicalizePath(p.normalize(p.isAbsolute(path) ? path : '$base/$path'));
  bool within(String? candidate) {
    if (candidate == null) return false;
    return pathIsWithin(resolved, _canonicalizePath(candidate));
  }

  if (within(base) || within(gitRepositoryRoot(base))) return resolved;
  if (within(Directory.systemTemp.path)) return resolved;
  throw Exception('Path traversal attempt blocked: $path '
      '(resolved: $resolved, working dir: $base)');
}

/// Symlink-resolving canonical form of [path], falling back to the
/// lexical path when it has no filesystem entry yet (planned writes).
String _canonicalizePath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } catch (_) {
    return path;
  }
}

/// TEMP STUB (old behavior) for RED proof.
String canonicalizePath(String path) => path;

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
