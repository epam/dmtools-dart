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
  resolveTests();
  // canonicalizePathTests(); // RED: pending canonicalizePath
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
      // Compared in canonical form: on macOS the temp base sits behind a
      // symlink (/var/folders/... → /private/var/...), so the resolved
      // planned path carries the canonical prefix (gh-365 rework).
      expect(
        resolved,
        canonicalizePath(p.normalize('${base.path}/nested/f.txt')),
      );
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
      final planned = p.normalize(
        '${Directory.systemTemp.path}/dmtools-other-run/f.txt',
      );
      final resolved = resolveWithinAllowedBase(planned, base.path);
      // Canonical comparison — portable across symlink-flavored tmpdirs
      // (gh-365 rework): a first write to a temp path must not be
      // rejected for a /var vs /private/var prefix mismatch on macOS.
      expect(resolved, canonicalizePath(planned));
    });

    test('accepts a planned path through an in-base symlinked directory', () {
      Directory('${base.path}/real').createSync();
      Link('${base.path}/link').createSync('${base.path}/real');

      final resolved =
          resolveWithinAllowedBase('${base.path}/link/new.txt', base.path);

      // The checked (and returned) path is the canonical through-link
      // form, not the lexical one — planned writes see through symlinked
      // parents, so the containment decision is made on the real target.
      expect(resolved, '${canonicalizePath(base.path)}/real/new.txt');
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
    test(
        'blocks a planned write through an in-base symlinked parent '
        '(gh-365 rework)', () {
      // The symlinked parent exists and points outside every allowed
      // base; only the final component is missing — the shape of every
      // first write through a link. The lexical fallback left the
      // symlinked ancestor unresolved and let the write materialize
      // outside the base (the blocking review finding).
      Link('${base.path}/sub').createSync('/etc');
      expect(
        () => resolveWithinAllowedBase(
          '${base.path}/sub/escape.txt',
          base.path,
        ),
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

/// `canonicalizePath` — the planned-path symlink semantics the sandbox
/// candidates rely on (gh-365 rework): a not-yet-existing target
/// resolves through its deepest existing ancestor, so a symlink-flavored
/// prefix (macOS TMPDIR=/var/folders/... → /private/var/...) compares
/// equal to its canonical candidate instead of false-rejecting the first
/// write, and a planned write sees through in-base symlinked parents.
void canonicalizePathTests() {
  group('canonicalizePath — planned paths resolve through symlinked ancestors',
      () {
    late Directory home;
    late Directory real;
    late Link flavor;

    setUp(() {
      home = Directory.systemTemp.createTempSync('dmtools_canon');
      real = Directory.systemTemp.createTempSync('dmtools_canon_real');
      flavor = Link('${home.path}/flavor')..createSync(real.path);
    });
    tearDown(() {
      flavor.deleteSync();
      real.deleteSync(recursive: true);
      home.deleteSync(recursive: true);
    });

    test('a not-yet-existing target resolves through a symlinked parent', () {
      final planned = '${flavor.path}/planned/f.txt';

      expect(
        canonicalizePath(planned),
        '${real.resolveSymbolicLinksSync()}/planned/f.txt',
      );
    });

    test('the resolved form is contained by the canonical candidate', () {
      final planned = '${flavor.path}/planned/f.txt';

      // Exactly the containment comparison `within()` makes for every
      // allowed base: with the lexical fallback the flavor prefix
      // (/var/...) fails the canonical candidate (/private/var/...), which
      // blocked every first temp write on macOS.
      expect(
        pathIsWithin(
          canonicalizePath(planned),
          canonicalizePath(flavor.path),
        ),
        isTrue,
      );
    });

    test('an existing path still resolves fully', () {
      final file = File('${real.path}/exists.txt')..writeAsStringSync('x');

      expect(canonicalizePath(file.path), file.resolveSymbolicLinksSync());
    });
  });
}
