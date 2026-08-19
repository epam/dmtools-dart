import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the structural file tools (`file_copy`, `file_move`,
/// `file_mkdir`) in [FileToolExecutor] and [fileTools].
void main() {
  catalogTests();
  copyTests();
  moveTests();
  mkdirTests();
  dispatchFsOpTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    fileTools().firstWhere((t) => t.name == name);

/// Creates a temp directory for file-operation tests.
Directory _tempDir() =>
    Directory.systemTemp.createTempSync('dmtools_file_copy_move_');

/// Catalog checks for the structural file tools.
void catalogTests() {
  final tools = fileTools();

  group('fileTools catalog: copy/move/mkdir', () {
    test('registers nineteen tools total', () {
      expect(tools, hasLength(19));
    });

    test('includes the copy/move/mkdir tool names', () {
      final names = tools.map((t) => t.name).toSet();
      for (final name in ['file_copy', 'file_move', 'file_mkdir']) {
        expect(names, contains(name), reason: name);
      }
    });

    test('copy and move expose source/dest params', () {
      expect(
        toolNamed('file_copy').params.map((p) => p.name),
        ['source', 'dest'],
      );
      expect(
        toolNamed('file_move').params.map((p) => p.name),
        ['source', 'dest'],
      );
    });

    test('every copy/move/mkdir tool belongs to the file integration', () {
      for (final name in ['file_copy', 'file_move', 'file_mkdir']) {
        expect(toolNamed(name).integration, 'file', reason: name);
      }
    });
  });
}

/// [FileToolExecutor.copy] tests.
void copyTests() {
  group('FileToolExecutor.copy', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('copies file content and keeps the source', () async {
      final src = File('${tempDir.path}/src.txt')..writeAsStringSync('data');
      final dest = '${tempDir.path}/dest.txt';
      await executor.copy(src.path, dest);
      expect(File(dest).readAsStringSync(), 'data');
      expect(src.existsSync(), isTrue);
    });
  });
}

/// [FileToolExecutor.move] tests.
void moveTests() {
  group('FileToolExecutor.move', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('moves a file and removes the source', () async {
      final src = File('${tempDir.path}/old.txt')..writeAsStringSync('moved');
      final dest = '${tempDir.path}/new.txt';
      await executor.move(src.path, dest);
      expect(src.existsSync(), isFalse);
      expect(File(dest).readAsStringSync(), 'moved');
    });
  });
}

/// [FileToolExecutor.mkdir] tests.
void mkdirTests() {
  group('FileToolExecutor.mkdir', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('creates a nested directory structure', () async {
      final path = '${tempDir.path}/a/b/c';
      await executor.mkdir(path);
      expect(Directory(path).existsSync(), isTrue);
    });
  });
}

/// Dispatch tests for structural file ops (copy, move, mkdir).
void dispatchFsOpTests() {
  group('execute dispatch: fs ops', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('routes file_copy', () async {
      final src = File('${tempDir.path}/s.txt')..writeAsStringSync('c');
      await executor.execute('file_copy', {
        'source': src.path,
        'dest': '${tempDir.path}/d.txt',
      });
      expect(File('${tempDir.path}/d.txt').readAsStringSync(), 'c');
    });

    test('routes file_move', () async {
      final src = File('${tempDir.path}/m.txt')..writeAsStringSync('mv');
      await executor.execute('file_move', {
        'source': src.path,
        'dest': '${tempDir.path}/m2.txt',
      });
      expect(src.existsSync(), isFalse);
    });

    test('routes file_mkdir', () async {
      await executor.execute('file_mkdir', {'path': '${tempDir.path}/nd'});
      expect(Directory('${tempDir.path}/nd').existsSync(), isTrue);
    });
  });
}
