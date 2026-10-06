/// gh-365 sandbox on the async `file_*` executor surface: every
/// [FileToolExecutor] operation rejects paths outside the job base, its
/// git repository root, and the system temp directory — the same
/// `resolveWithinAllowedBase` check the synchronous JS-bridge path
/// applies, so the two surfaces cannot drift apart on a security-flavored
/// behavior.
///
/// Java spec: `FileTools.java` in epam/dm.ai normalizes each path and
/// rejects anything outside the working directory ("Path traversal
/// attempt blocked") before acting; here the executor surfaces the
/// rejection as a failed Future, its uniform async error channel.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Base + executor fixture shared by the sections below.
class _SandboxFixture {
  late Directory base;
  late FileToolExecutor executor;
  late String insideSource;

  void setUp(String prefix) {
    base = Directory.systemTemp.createTempSync(prefix);
    executor = FileToolExecutor(base: base.path);
    insideSource = '${base.path}/src.txt';
    File(insideSource).writeAsStringSync('payload');
  }

  void tearDown() => base.deleteSync(recursive: true);
}

void main() {
  escapeSegmentTests();
  absoluteEscapeTests();
  noFalseRejectionTests();
  copyEndpointTests();
  moveEndpointTests();
  recursiveSymlinkTests();
  configuredReadAllowlistTests();
}

/// The ops table: every path-taking executor operation, keyed by name.
Map<String, Future<dynamic> Function(FileToolExecutor, String)> _ops() => {
      'read': (e, p) => e.read(p),
      'list': (e, p) => e.list(p),
      'exists': (e, p) => e.exists(p),
      'delete': (e, p) => e.delete(p),
      'mkdir': (e, p) => e.mkdir(p),
      'readLines': (e, p) => e.readLines(p),
      'writeLines': (e, p) => e.writeLines(p, const ['x']),
      'append': (e, p) => e.append(p, 'x'),
      'getFileInfo': (e, p) => e.getFileInfo(p),
      'readJson': (e, p) => e.readJson(p),
      'getSize': (e, p) => e.getSize(p),
      'watch': (e, p) => e.watch(p),
      'existsInPath': (e, p) => e.existsInPath(p, 'f.txt'),
      'search': (e, p) => e.search(p, '*.txt'),
      'write': (e, p) => e.write(p, 'x'),
    };

/// Escaping `..` segments land outside every allowed base (a
/// one-level-deep system-temp base escaped twice reaches the filesystem
/// root) — every operation must throw before touching the filesystem.
void escapeSegmentTests() {
  group('FileToolExecutor rejects escaping .. segments (gh-365)', () {
    final f = _SandboxFixture();

    setUp(() => f.setUp('dmtools_fsandbox'));
    tearDown(f.tearDown);

    test('every path-taking operation rejects the same segment', () async {
      final escape = '../../dmtools-should-not-exist';
      for (final entry in _ops().entries) {
        await expectLater(
          entry.value(f.executor, escape),
          throwsA(isA<Exception>()),
          reason: '${entry.key} must reject $escape',
        );
      }
      expect(
        File('/dmtools-should-not-exist').existsSync(),
        isFalse,
        reason: 'the escape must not materialize on disk',
      );
    });
  });
}

/// Absolute paths outside every allowed base are rejected the same way,
/// and write-side side effects must not materialize.
void absoluteEscapeTests() {
  group('FileToolExecutor rejects absolute outside paths (gh-365)', () {
    final f = _SandboxFixture();

    setUp(() => f.setUp('dmtools_fsandbox_abs'));
    tearDown(f.tearDown);

    test('write throws for a path outside every allowed base', () async {
      await expectLater(
        f.executor.write('/etc/dmtools-should-not-exist.txt', 'x'),
        throwsA(isA<Exception>()),
      );
      expect(File('/etc/dmtools-should-not-exist.txt').existsSync(), isFalse);
    });

    test('mkdir throws for a path outside every allowed base', () async {
      await expectLater(
        f.executor.mkdir('/etc/dmtools-should-not-exist-dir'),
        throwsA(isA<Exception>()),
      );
      expect(
          Directory('/etc/dmtools-should-not-exist-dir').existsSync(), isFalse);
    });

    test('delete throws for a path outside every allowed base', () async {
      await expectLater(
        f.executor.delete('/etc/hosts'),
        throwsA(isA<Exception>()),
      );
    });
  });
}

/// The sandbox must not reject legitimate work: nested in-base paths and
/// foreign system-temp directories both stay writable.
void noFalseRejectionTests() {
  group('FileToolExecutor allows in-base and tmpdir paths (gh-365)', () {
    final f = _SandboxFixture();

    setUp(() => f.setUp('dmtools_fsandbox_ok'));
    tearDown(f.tearDown);

    test('a nested in-base path round-trips through parent creation', () async {
      final nested = '${f.base.path}/outputs/token_usage/cache.json';

      await f.executor.write(nested, '{"tokens": 42}');

      expect(await f.executor.read(nested), '{"tokens": 42}');
      expect(await f.executor.readLines(nested), ['{"tokens": 42}']);
      expect((await f.executor.list('${f.base.path}/outputs')).length, 1);
      expect(await f.executor.exists(nested), isTrue);
    });

    test('a system-temp path outside the base is still allowed', () async {
      final other = Directory.systemTemp.createTempSync('dmtools_fsandbox_tm');
      try {
        final target = '${other.path}/shared.txt';

        await f.executor.write(target, 'tmp');

        expect(await f.executor.read(target), 'tmp');
        expect(await f.executor.delete(target), isTrue);
      } finally {
        other.deleteSync(recursive: true);
      }
    });
  });
}

/// Copy validates BOTH endpoints: an outside source would leak content
/// into the base, an outside destination would smuggle it out.
void copyEndpointTests() {
  group('FileToolExecutor copy endpoints (gh-365)', () {
    final f = _SandboxFixture();

    setUp(() => f.setUp('dmtools_fsandbox_cp'));
    tearDown(f.tearDown);

    test('copy from outside into the base throws', () async {
      await expectLater(
        f.executor.copy('/etc/hosts', '${f.base.path}/leak.txt'),
        throwsA(isA<Exception>()),
      );
      expect(File('${f.base.path}/leak.txt').existsSync(), isFalse);
    });

    test('copy from the base to outside throws', () async {
      await expectLater(
        f.executor.copy(f.insideSource, '/etc/dmtools-leak.txt'),
        throwsA(isA<Exception>()),
      );
      expect(File('/etc/dmtools-leak.txt').existsSync(), isFalse);
    });

    test('an in-base copy still works', () async {
      Directory('${f.base.path}/nested').createSync();
      final dest = '${f.base.path}/nested/copy.txt';

      await f.executor.copy(f.insideSource, dest);

      expect(File(dest).readAsStringSync(), 'payload');
    });
  });
}

/// Move/rename validate both endpoints too; a rejected move keeps the
/// source in place.
void moveEndpointTests() {
  group('FileToolExecutor move/rename endpoints (gh-365)', () {
    final f = _SandboxFixture();

    setUp(() => f.setUp('dmtools_fsandbox_mv'));
    tearDown(f.tearDown);

    test('move to outside throws', () async {
      await expectLater(
        f.executor.move(f.insideSource, '/etc/dmtools-leak.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('move from outside throws', () async {
      await expectLater(
        f.executor.move('/etc/hosts', '${f.base.path}/leak.txt'),
        throwsA(isA<Exception>()),
      );
      expect(File('${f.base.path}/leak.txt').existsSync(), isFalse);
    });

    test('rename to outside throws and keeps the source', () async {
      await expectLater(
        f.executor.rename(f.insideSource, '/etc/dmtools-leak.txt'),
        throwsA(isA<Exception>()),
      );
      expect(
        File(f.insideSource).existsSync(),
        isTrue,
        reason: 'the source must survive a rejected move',
      );
    });
  });
}

/// Recursive traversals report links without following them — Java
/// `Files.walk` parity (AGENTS.md rule 2): an in-base directory symlink
/// pointing outside must not leak outside entry names during listing
/// (gh-365 rework review thread 2). The sandbox check on the listed root
/// covers only the path argument; traversal must not walk through links.
void recursiveSymlinkTests() {
  group('FileToolExecutor recursive listings do not follow links (gh-365)', () {
    final f = _SandboxFixture();

    setUp(() => f.setUp('dmtools_fsandbox_lnk'));
    tearDown(f.tearDown);

    Directory outsideTarget() {
      final outside =
          Directory.systemTemp.createTempSync('dmtools_fsandbox_out');
      File('${outside.path}/needle.txt').writeAsStringSync('secret');
      Link('${f.base.path}/link').createSync(outside.path);
      return outside;
    }

    test('search does not descend through an in-base directory symlink',
        () async {
      final outside = outsideTarget();
      try {
        expect(await f.executor.search(f.base.path, 'needle.txt'), isEmpty);
      } finally {
        outside.deleteSync(recursive: true);
      }
    });

    test('existsInPath does not descend through an in-base directory symlink',
        () async {
      final outside = outsideTarget();
      try {
        expect(
          await f.executor.existsInPath(f.base.path, 'needle.txt'),
          isFalse,
        );
      } finally {
        outside.deleteSync(recursive: true);
      }
    });

    test('in-base real files are still found (no over-blocking)', () async {
      Directory('${f.base.path}/pkg').createSync();
      File('${f.base.path}/pkg/needle.txt').writeAsStringSync('mine');

      expect(await f.executor.search(f.base.path, 'needle.txt'), isNotEmpty);
      expect(await f.executor.existsInPath(f.base.path, 'needle.txt'), isTrue);
    });
  });
}

/// gh-367: the `DMTOOLS_FILE_READ_ALLOWED_PATHS` escape hatch reaches the
/// executor surface too — read-flavored operations accept a path that only
/// the configured globs admit (the pack-internal `file_read` shape from
/// `~/.dmtools/packs/...`), while write-flavored operations keep Java's
/// strict no-config guard (`writeFile`/`deleteFile` never consult the
/// allow-list in `FileTools.java`).
///
/// The config value flows through [PropertyReader] exactly as in
/// production: `setOverrides` stands in for the OS env tier the fa
/// machine sets (`DMTOOLS_FILE_READ_ALLOWED_PATHS=...`).
void configuredReadAllowlistTests() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final homeUsable = home != null &&
      home.isNotEmpty &&
      !pathIsWithin(home, Directory.systemTemp.path);

  group('FileToolExecutor read ops honor configured allowed paths (gh-367)',
      skip: homeUsable ? null : 'no HOME outside the tmpdir to test against',
      () {
    final f = _SandboxFixture();
    late Directory packJs;
    late String module;

    setUp(() {
      f.setUp('dmtools_fsandbox_cfg');
      final packDir = '$home/.dmtools-gh367-test/packs/sm_github-0.1.36/js';
      packJs = Directory(packDir)..createSync(recursive: true);
      module = '$packDir/configLoader.js';
      File(module).writeAsStringSync('module.exports={};');
      PropertyReader.setOverrides({
        'DMTOOLS_FILE_READ_ALLOWED_PATHS': '$home/.dmtools-gh367-test/**',
      });
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      Directory('$home/.dmtools-gh367-test').deleteSync(recursive: true);
      f.tearDown();
    });

    test('read ops admit the pack module through the config', () async {
      File('${packJs.path}/../cfg.json').writeAsStringSync('{"a": 1}');
      final jsonPath =
          '$home/.dmtools-gh367-test/packs/sm_github-0.1.36/cfg.json';
      final ops = <String, Future<dynamic> Function()>{
        'read': () => f.executor.read(module),
        'readLines': () => f.executor.readLines(module),
        'readJson': () => f.executor.readJson(jsonPath),
        'exists': () => f.executor.exists(module),
        'getFileInfo': () => f.executor.getFileInfo(module),
        'getSize': () => f.executor.getSize(module),
        'watch': () => f.executor.watch(module),
      };
      for (final entry in ops.entries) {
        await expectLater(entry.value(), completes,
            reason: '${entry.key} must admit its path via the config');
      }
      expect(await f.executor.read(module), 'module.exports={};');
      expect(await f.executor.exists(module), isTrue);
      expect((await f.executor.getFileInfo(module))['exists'], isTrue);
    });

    test('list/search over the admitted pack dir work', () async {
      File('${packJs.path}/second.js').writeAsStringSync('// 2');
      expect((await f.executor.list(packJs.path)), hasLength(2));
      expect(await f.executor.search(packJs.path, '*.js'), hasLength(2));
    });

    test('write ops still reject the same configured path', () async {
      await expectLater(
        f.executor.write(module, 'overwritten'),
        throwsA(isA<Exception>()),
      );
      expect(File(module).readAsStringSync(), 'module.exports={};',
          reason: 'the write must not land');

      await expectLater(
        f.executor.delete(module),
        throwsA(isA<Exception>()),
      );
      expect(File(module).existsSync(), isTrue,
          reason: 'the delete must not happen');

      await expectLater(
        f.executor.mkdir('$home/.dmtools-gh367-test/extra'),
        throwsA(isA<Exception>()),
      );
      expect(
        Directory('$home/.dmtools-gh367-test/extra').existsSync(),
        isFalse,
      );

      await expectLater(
        f.executor.append(module, 'tail'),
        throwsA(isA<Exception>()),
      );
    });

    test('copy/move endpoints stay strict both ways', () async {
      await expectLater(
        f.executor.copy(module, '${f.base.path}/leak.txt'),
        throwsA(isA<Exception>()),
      );
      expect(File('${f.base.path}/leak.txt').existsSync(), isFalse);

      await expectLater(
        f.executor.copy(f.insideSource, module),
        throwsA(isA<Exception>()),
      );
    });

    test('without the override the same path stays blocked', () async {
      PropertyReader.clearOverrides();

      await expectLater(
        f.executor.read(module),
        throwsA(isA<Exception>()),
      );
    });
  });
}
