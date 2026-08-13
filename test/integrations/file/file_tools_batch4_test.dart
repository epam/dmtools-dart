import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the batch-4 file tools (`file_watch`, `file_rename`,
/// `file_search`) added to [FileToolExecutor] and [fileTools].
void main() {
  catalogTests();
  watchTests();
  renameTests();
  searchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    fileTools().firstWhere((t) => t.name == name);

/// Creates a temp directory for file-operation tests.
Directory _tempDir() =>
    Directory.systemTemp.createTempSync('dmtools_file_batch4_');

/// Catalog checks for the three new tools.
void catalogTests() {
  group('fileTools catalog (batch 4)', () {
    final tools = fileTools();

    test('registers nineteen tools total', () {
      expect(tools, hasLength(19));
    });

    test('includes the three new tool names', () {
      final names = tools.map((t) => t.name).toSet();
      for (final name in [
        'file_watch',
        'file_rename',
        'file_search',
      ]) {
        expect(names, contains(name), reason: name);
      }
    });

    test('file_rename exposes source and dest params', () {
      expect(
        toolNamed('file_rename').params.map((p) => p.name),
        ['source', 'dest'],
      );
    });

    test('file_search exposes dir and pattern params', () {
      expect(
        toolNamed('file_search').params.map((p) => p.name),
        ['dir', 'pattern'],
      );
    });

    test('every new tool belongs to the file integration', () {
      for (final name in ['file_watch', 'file_rename', 'file_search']) {
        expect(toolNamed(name).integration, 'file', reason: name);
      }
    });
  });
}

/// [FileToolExecutor.watch] tests.
void watchTests() {
  group('FileToolExecutor.watch', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns size and modified time for a file', () async {
      final file = File('${tempDir.path}/w.txt')..writeAsStringSync('hello');
      final result = await executor.watch(file.path);
      expect(result['size'], 5);
      expect(result['modified'], isA<DateTime>());
    });

    test('routes file_watch through execute dispatch', () async {
      final file = File('${tempDir.path}/d.txt')..writeAsStringSync('data');
      final result = await executor.execute('file_watch', {'path': file.path})
          as Map<String, dynamic>;
      expect(result['size'], 4);
      expect(result['modified'], isA<DateTime>());
    });
  });
}

/// [FileToolExecutor.rename] tests.
void renameTests() {
  group('FileToolExecutor.rename', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('moves a file to a new name', () async {
      final source = File('${tempDir.path}/old.txt')..writeAsStringSync('x');
      await executor.rename(source.path, '${tempDir.path}/new.txt');
      expect(source.existsSync(), isFalse);
      expect(File('${tempDir.path}/new.txt').readAsStringSync(), 'x');
    });

    test('routes file_rename through execute dispatch', () async {
      final source = File('${tempDir.path}/src.txt')..writeAsStringSync('y');
      await executor.execute('file_rename', {
        'source': source.path,
        'dest': '${tempDir.path}/dst.txt',
      });
      expect(source.existsSync(), isFalse);
      expect(File('${tempDir.path}/dst.txt').readAsStringSync(), 'y');
    });
  });
}

/// [FileToolExecutor.search] tests.
void searchTests() {
  group('FileToolExecutor.search', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('finds files matching a glob pattern recursively', () async {
      Directory('${tempDir.path}/sub').createSync();
      File('${tempDir.path}/a.dart').writeAsStringSync('');
      File('${tempDir.path}/sub/b.dart').writeAsStringSync('');
      File('${tempDir.path}/c.txt').writeAsStringSync('');
      final result = await executor.search(tempDir.path, '*.dart');
      final names = result.map((p) => p.split('/').last).toSet();
      expect(names, {'a.dart', 'b.dart'});
      expect(result.every((p) => !p.endsWith('.txt')), isTrue);
    });

    test('returns empty list for a missing directory', () async {
      final result = await executor.search('${tempDir.path}/nope', '*.dart');
      expect(result, isEmpty);
    });

    test('routes file_search through execute dispatch', () async {
      File('${tempDir.path}/x.txt').writeAsStringSync('');
      final result = await executor.execute('file_search', {
        'dir': tempDir.path,
        'pattern': '*.txt',
      }) as List<dynamic>;
      expect(result, hasLength(1));
    });
  });
}
