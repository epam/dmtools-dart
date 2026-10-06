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
  canonicalizePathTests();
  matchesPatternWildcardTests();
  matchesPatternPrefixTests();
  configuredAllowlistAdmitsTests();
  configuredAllowlistAdmitScopeTests();
  configuredAllowlistBlocksTests();
}

/// A writable directory outside the base, the system temp dir, and any git
/// repository root — the shape of the dmtools home (`~/.dmtools`) on the
/// fa machine (gh-367). Null when the platform exposes no such directory
/// (HOME under the temp dir, e.g. some Windows runners) — the groups that
/// need it skip instead of passing for a wrong reason.
final String? fakeHome = () {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return null;
  if (pathIsWithin(home, Directory.systemTemp.path)) return null;
  return home;
}();

/// Path of a pack-internal module inside [fakeHome], the gh-367 failure
/// shape: `~/.dmtools/packs/<agent>-<version>/js/configLoader.js`.
String packModuleIn(String home, {String agent = 'sm_github-0.1.36'}) =>
    '$home/.dmtools-gh367-test/packs/$agent/js/configLoader.js';

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

/// `matchesPattern` — a single `DMTOOLS_FILE_READ_ALLOWED_PATHS` glob
/// pattern against an already-resolved path (gh-367, Java
/// `FileTools.matchesPattern` parity, package-private static there /
/// public here for the same testability reason). Pattern rules (Java
/// `PathMatcher` glob + `Path.resolve` prefix semantics):
///
/// - no wildcard at all → exact match of `workingDir.resolve(pattern)`;
/// - the literal prefix before the first wildcard resolves against
///   `workingDir` (so `../.dmtools/**` names the sibling `.dmtools` of
///   the working directory regardless of where the process started, and
///   an absolute prefix passes through — `Path.resolve` semantics);
/// - the glob suffix matches the path relative to that base: `**` crosses
///   directory boundaries, `*`/`?` stay inside one segment, `[...]` and
///   `{...}` per Java glob.
void matchesPatternWildcardTests() {
  const base = '/repo/work';

  group('matchesPattern — wildcard suffix semantics', () {
    test('** crosses directory boundaries', () {
      expect(
        matchesPattern(
            '/repo/work/.dmtools/packs/p-1/js/loader.js', base, '.dmtools/**'),
        isTrue,
      );
      expect(matchesPattern('$base/.dmtools', base, '.dmtools/**'), isTrue);
    });

    test('* stays inside one segment', () {
      expect(matchesPattern('$base/.dmtools/f.js', base, '.dmtools/*'), isTrue);
      expect(
        matchesPattern('$base/.dmtools/js/f.js', base, '.dmtools/*'),
        isFalse,
        reason: '* must not cross the / boundary',
      );
    });

    test('*.js matches a flat module only', () {
      expect(matchesPattern('$base/configLoader.js', base, '*.js'), isTrue);
      expect(matchesPattern('$base/js/configLoader.js', base, '*.js'), isFalse);
    });

    test('literal segments before the suffix bind exactly', () {
      expect(
          matchesPattern('$base/js/configLoader.js', base, 'js/*.js'), isTrue);
      expect(matchesPattern('$base/lib/configLoader.js', base, 'js/*.js'),
          isFalse);
    });

    test('? matches exactly one character, never a separator', () {
      expect(matchesPattern('$base/pack-a.js', base, 'pack-?.js'), isTrue);
      expect(matchesPattern('$base/pack-ab.js', base, 'pack-?.js'), isFalse);
      expect(matchesPattern('$base/pack-.js', base, 'pack-?.js'), isFalse);
    });

    test('[...] character classes with ranges and ! negation', () {
      expect(matchesPattern('$base/pack-1.js', base, 'pack-[0-9].js'), isTrue);
      expect(matchesPattern('$base/pack-x.js', base, 'pack-[0-9].js'), isFalse);
      expect(matchesPattern('$base/pack-x.js', base, 'pack-[!0-9].js'), isTrue);
    });

    test('{...} alternatives, nested content included', () {
      expect(matchesPattern('$base/js/loader.js', base, '{js,ts}/loader.js'),
          isTrue);
      expect(matchesPattern('$base/ts/loader.js', base, '{js,ts}/loader.js'),
          isTrue);
      expect(matchesPattern('$base/py/loader.js', base, '{js,ts}/loader.js'),
          isFalse);
    });
  });
}

/// The prefix-resolution half of `matchesPattern`: how a pattern's
/// literal prefix resolves against the working dir before matching.
void matchesPatternPrefixTests() {
  const base = '/repo/work';

  group('matchesPattern — prefix resolution against the working dir', () {
    test('a relative prefix expands to the sibling of the working dir', () {
      // The exact gh-367 shape: `../.dmtools/**` names the `.dmtools`
      // directory NEXT TO the repo checkout, wherever the process runs.
      expect(
        matchesPattern(
            '/repo/.dmtools/packs/p-1/js/c.js', base, '../.dmtools/**'),
        isTrue,
      );
      expect(
        matchesPattern('/repo/other/packs/p-1/js/c.js', base, '../.dmtools/**'),
        isFalse,
      );
    });

    test('a deeper relative prefix keeps resolving lexically', () {
      expect(
        matchesPattern('/home/r/.dmtools/packs/p/js/c.js', base,
            '../../../home/r/.dmtools/**'),
        isTrue,
        reason: '3 up from /repo/work lands at /',
      );
    });

    test('an absolute prefix passes through (Path.resolve semantics)', () {
      expect(
        matchesPattern(
            '/home/r/.dmtools/packs/p/js/c.js', base, '/home/r/.dmtools/**'),
        isTrue,
      );
    });

    test('no wildcard means exact-path equality', () {
      expect(
        matchesPattern(
            '/repo/.dmtools/loader.js', base, '../.dmtools/loader.js'),
        isTrue,
      );
      expect(
        matchesPattern(
            '/repo/.dmtools/other.js', base, '../.dmtools/loader.js'),
        isFalse,
      );
    });

    test('a sibling with a shared name prefix is not swallowed', () {
      expect(
        matchesPattern('$base/.dmtools-x/f.js', base, '.dmtools/**'),
        isFalse,
      );
    });
  });
}

/// `resolveWithinAllowedBase` with `configuredAllowedPaths` — the
/// `DMTOOLS_FILE_READ_ALLOWED_PATHS` escape hatch (gh-367, Java
/// `FileTools.isAllowedByConfig` parity): after the base / tmpdir /
/// git-root containment fails, a path matching one of the configured
/// comma-separated globs is accepted. Read tools only — Java's write
/// path (`writeFile`/`deleteFile`) keeps its plain startsWith guard and
/// never consults the config.
///
/// The fixture mirrors the failure shape: a pack cache under `$HOME`
/// (the dmtools home), a temp job base, no git root — every group skips
/// when the platform offers no usable HOME outside the tmpdir.
void _seedGh367PackModule() {
  final js = Directory(p.dirname(packModuleIn(fakeHome!)))
    ..createSync(recursive: true);
  File('${js.path}/configLoader.js').writeAsStringSync('module.exports={};');
}

String? get _homeSkip =>
    fakeHome == null ? 'no HOME outside the tmpdir to test against' : null;

void configuredAllowlistAdmitsTests() {
  group('resolveWithinAllowedBase — configured globs admit (gh-367)',
      skip: _homeSkip, () {
    late Directory base;

    setUp(() => base = Directory.systemTemp.createTempSync('dmtools_allow'));
    tearDown(() => base.deleteSync(recursive: true));

    test('an absolute-prefix glob admits the pack module', () {
      _seedGh367PackModule();
      final module = packModuleIn(fakeHome!);

      expect(
        resolveWithinAllowedBase(
          module,
          base.path,
          configuredAllowedPaths: '$fakeHome/.dmtools-gh367-test/**',
        ),
        canonicalizePath(module),
      );
    });

    test('a relative ..-prefix glob (the Java ../.dmtools shape) admits it',
        () {
      _seedGh367PackModule();
      final module = packModuleIn(fakeHome!);
      final prefix =
          p.relative(p.dirname(p.dirname(p.dirname(module))), from: base.path);

      expect(
        resolveWithinAllowedBase(
          module,
          base.path,
          configuredAllowedPaths: '$prefix/**',
        ),
        canonicalizePath(module),
      );
    });
  });
}

/// The config grants exactly its pattern's scope: an exact match only
/// for no-wildcard patterns, every comma entry gets its chance, and one
/// pattern covers all modules under it (multi-item).
void configuredAllowlistAdmitScopeTests() {
  group('resolveWithinAllowedBase — configured glob scope (gh-367)',
      skip: _homeSkip, () {
    late Directory base;

    setUp(() => base = Directory.systemTemp.createTempSync('dmtools_allow'));
    tearDown(() => base.deleteSync(recursive: true));

    test('an exact no-wildcard pattern admits exactly that file', () {
      _seedGh367PackModule();
      final module = packModuleIn(fakeHome!);

      expect(
        resolveWithinAllowedBase(
          module,
          base.path,
          configuredAllowedPaths: module,
        ),
        canonicalizePath(module),
      );
      expect(
        () => resolveWithinAllowedBase(
          '$fakeHome/.dmtools-gh367-test/packs/sm_github-0.1.36/js/other.js',
          base.path,
          configuredAllowedPaths: module,
        ),
        _throwsTraversalBlocked(),
      );
    });

    test('a comma list tries every pattern, blanks skipped', () {
      _seedGh367PackModule();
      final module = packModuleIn(fakeHome!);

      final resolved = resolveWithinAllowedBase(
        module,
        base.path,
        configuredAllowedPaths:
            ' /nonexistent-gh367/** , , $fakeHome/.dmtools-gh367-test/** ',
      );

      expect(resolved, canonicalizePath(module));
    });

    test('two modules under one pattern both pass (multi-item)', () {
      _seedGh367PackModule();
      final js = Directory(p.dirname(packModuleIn(fakeHome!)));
      File('${js.path}/second.js').writeAsStringSync('// 2');

      for (final name in ['configLoader.js', 'second.js']) {
        expect(
          resolveWithinAllowedBase(
            '${js.path}/$name',
            base.path,
            configuredAllowedPaths: '$fakeHome/.dmtools-gh367-test/**',
          ),
          canonicalizePath('${js.path}/$name'),
        );
      }
    });
  });
}

/// The blocked half: a blank/mismatched config grants nothing, `*` never
/// reaches across segments, and `..` inside the path cannot smuggle past
/// a matching prefix. No seeding — the canonicalizer resolves planned
/// paths, so the rejections are about the pattern, not the file.
void configuredAllowlistBlocksTests() {
  group('resolveWithinAllowedBase — configured globs still block (gh-367)',
      skip: _homeSkip, () {
    late Directory base;

    setUp(() => base = Directory.systemTemp.createTempSync('dmtools_allow'));
    tearDown(() => base.deleteSync(recursive: true));

    test('a blank config value behaves like an unset one', () {
      expect(
        () => resolveWithinAllowedBase(
          packModuleIn(fakeHome!),
          base.path,
          configuredAllowedPaths: '   ',
        ),
        _throwsTraversalBlocked(),
      );
    });

    test('* patterns do not admit nested pack modules', () {
      expect(
        () => resolveWithinAllowedBase(
          packModuleIn(fakeHome!),
          base.path,
          configuredAllowedPaths: '$fakeHome/.dmtools-gh367-test/*',
        ),
        _throwsTraversalBlocked(),
      );
    });

    test('an unmatching prefix keeps the traversal blocked', () {
      expect(
        () => resolveWithinAllowedBase(
          packModuleIn(fakeHome!),
          base.path,
          configuredAllowedPaths: '$fakeHome/.other-tools/**',
        ),
        _throwsTraversalBlocked(),
      );
    });

    test('.. segments inside the path cannot smuggle past the pattern', () {
      expect(
        () => resolveWithinAllowedBase(
          '$fakeHome/.dmtools-gh367-test/../elsewhere/f.js',
          base.path,
          configuredAllowedPaths: '$fakeHome/.dmtools-gh367-test/**',
        ),
        _throwsTraversalBlocked(),
      );
    });
  });
}
