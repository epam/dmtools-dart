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

/// Canonicalizes [dirPath] and validates that it lies within the job
/// [base] directory, its git repository root, or the system temp
/// directory; otherwise throws (Java `SecurityException` parity, rethrown
/// as a JS `Error` on the bridge path).
void validateWithinAllowedBase(String dirPath, String base) {
  String canonical(String p) {
    try {
      return Directory(p).resolveSymbolicLinksSync();
    } catch (_) {
      return p;
    }
  }

  final dir = canonical(dirPath);
  bool within(String? candidate) {
    if (candidate == null) return false;
    final c = canonical(candidate);
    return dir == c || dir.startsWith('$c/');
  }

  if (within(base) || within(gitRepositoryRoot(base))) return;
  if (within(Directory.systemTemp.path)) return;
  throw Exception('Working directory is outside allowed base paths '
      '(user.dir, git root, tmpdir): $dirPath');
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
