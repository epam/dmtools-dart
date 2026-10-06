import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The allowed-base sandbox helpers (`validateWithinAllowedBase` and its
/// containment check): the same check both surfaces of
/// `cli_execute_command` apply to a caller-supplied `workingDirectory`;
/// `resolveWithinAllowedBase` extends the same sandbox to the `file_*`
/// family (gh-365) on both its surfaces.
void main() {
  pathIsWithinTests();
  validateTests();
  resolveTests();
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

/// `resolveWithinAllowedBase` — the file-path sandbox shared by both
/// surfaces of the `file_*` family (gh-365, Java `FileTools` parity):
/// relative paths resolve against the base, `.`/`..` segments are
/// normalized lexically BEFORE the containment check (Java
/// `Path.normalize()` parity — a not-yet-existing escape target has no
/// filesystem entry to canonicalize, so skipping normalization would let
/// `base/sub/../outside` pass a raw prefix match), and the validated
/// absolute path is returned so callers act on exactly what was checked.
void resolveTests() {
  resolveAllowedTests();
  resolveBlockedTests();
}

/// The allowed side of the file-path sandbox.
void resolveAllowedTests() {
  group('resolveWithinAllowedBase — allowed paths', () {
    late Directory base;

    setUp(() => base = Directory.systemTemp.createTempSync('dmtools_rbase'));
    tearDown(() => base.deleteSync(recursive: true));

    test('resolves a relative path against the base, absolute and normalized',
        () {
      final resolved =
          resolveWithinAllowedBase('sub/../nested/f.txt', base.path);
      expect(resolved, p.normalize('${base.path}/nested/f.txt'));
    });

    test('accepts a nested in-base path (no false rejection)', () {
      final nested = Directory('${base.path}/a/b')..createSync(recursive: true);
      final file = File('${nested.path}/f.txt')..writeAsStringSync('x');
      expect(
        resolveWithinAllowedBase(file.path, base.path),
        file.resolveSymbolicLinksSync(),
      );
    });

    test('accepts a path in the system temp dir outside the base', () {
      final resolved = resolveWithinAllowedBase(
        '${Directory.systemTemp.path}/dmtools-other-run/f.txt',
        base.path,
      );
      expect(
        resolved,
        p.normalize('${Directory.systemTemp.path}/dmtools-other-run/f.txt'),
      );
    });
  });
}

/// The blocked side of the file-path sandbox — every rejection carries the
/// Java `FileTools` spec wording ("Path traversal attempt blocked").
void resolveBlockedTests() {
  group('resolveWithinAllowedBase — blocked paths', () {
    late Directory base;

    setUp(() => base = Directory.systemTemp.createTempSync('dmtools_rbase'));
    tearDown(() => base.deleteSync(recursive: true));

    test('blocks a .. escape whose target does not exist yet', () {
      // Two levels up from a one-level-deep temp base lands at the
      // filesystem root — outside the base and outside the tmpdir.
      expect(
        () => resolveWithinAllowedBase('../../dmtools-blocked.txt', base.path),
        _throwsTraversalBlocked(),
      );
    });

    test('blocks an absolute .. escape even when the base is nested deeper',
        () {
      expect(
        () => resolveWithinAllowedBase(
          '${base.path}/sub/../../../etc/dmtools-blocked.txt',
          base.path,
        ),
        _throwsTraversalBlocked(),
      );
    });

    test('blocks an absolute path outside every allowed base', () {
      expect(
        () => resolveWithinAllowedBase('/etc/hosts', base.path),
        _throwsTraversalBlocked(),
      );
    });

    test('blocks an in-base symlink pointing outside the allowed bases', () {
      Link('${base.path}/escape').createSync('/etc/hosts');
      expect(
        () => resolveWithinAllowedBase('escape', base.path),
        _throwsTraversalBlocked(),
      );
    });
  });
}

/// Matcher for the Java-spec traversal rejection wording.
Matcher _throwsTraversalBlocked() => throwsA(
      isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('Path traversal attempt blocked'),
      ),
    );
