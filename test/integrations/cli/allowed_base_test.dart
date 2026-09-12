import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// The allowed-base sandbox helpers (`validateWithinAllowedBase` and its
/// containment check): the same check both surfaces of
/// `cli_execute_command` apply to a caller-supplied `workingDirectory`.
void main() {
  pathIsWithinTests();
  validateTests();
}

/// `pathIsWithin` — the path-prefix containment check. Java
/// `Path.startsWith` parity: separator-aware, so Windows backslash paths
/// behave exactly like POSIX ones (a hard-coded `/` separator would
/// false-reject legitimate nested directories on Windows, where
/// `Directory.resolveSymbolicLinksSync` returns backslash-separated
/// paths).
void pathIsWithinTests() {
  group('pathIsWithin', () {
    test('accepts the base itself', () {
      expect(pathIsWithin('/repo', '/repo'), isTrue);
    });

    test('accepts a nested directory (posix separator)', () {
      expect(pathIsWithin('/repo/sub/pkg', '/repo'), isTrue);
    });

    test('rejects a sibling with a shared name prefix', () {
      expect(pathIsWithin('/repo-other', '/repo'), isFalse);
    });

    test('rejects a path outside the base', () {
      expect(pathIsWithin('/etc/passwd', '/repo'), isFalse);
    });

    test('accepts a nested windows directory (backslash separator)', () {
      expect(
        pathIsWithin(r'C:\src\repo\sub', r'C:\src\repo', separator: r'\'),
        isTrue,
      );
    });

    test('rejects a windows sibling with a shared name prefix', () {
      expect(
        pathIsWithin(r'C:\src\repo-other', r'C:\src\repo', separator: r'\'),
        isFalse,
      );
    });

    test('defaults to the platform separator', () {
      expect(
          pathIsWithin('/repo/sub', '/repo', separator: Platform.pathSeparator),
          isTrue);
    });

    test('an empty base only matches itself', () {
      expect(pathIsWithin('', ''), isTrue);
      expect(pathIsWithin('/repo', ''), isFalse);
    });
  });
}

/// `validateWithinAllowedBase` end-to-end: inside the base (or its git
/// root, or the system temp dir) is allowed, everything else throws.
void validateTests() {
  group('validateWithinAllowedBase', () {
    test('accepts a directory inside the base', () {
      final base = Directory.current.path;
      expect(
        () => validateWithinAllowedBase('$base/test', base),
        returnsNormally,
      );
    });

    test('accepts a directory inside the system temp dir', () {
      expect(
        () => validateWithinAllowedBase(
          '${Directory.systemTemp.path}/some-job-run',
          Directory.current.path,
        ),
        returnsNormally,
      );
    });

    test('rejects a directory outside the allowed bases', () {
      expect(
        () => validateWithinAllowedBase('/etc', Directory.current.path),
        throwsException,
      );
    });
  });
}
