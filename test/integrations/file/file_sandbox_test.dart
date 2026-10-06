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
