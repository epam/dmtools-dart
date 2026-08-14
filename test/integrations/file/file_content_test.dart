import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the content-oriented file tools (`file_read_lines`,
/// `file_write_lines`, `file_append`, `file_info`) in [FileToolExecutor] and
/// [fileTools].
void main() {
  catalogTests();
  readLinesTests();
  writeLinesTests();
  appendTests();
  fileInfoTests();
  dispatchContentTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    fileTools().firstWhere((t) => t.name == name);

/// Creates a temp directory for file-operation tests.
Directory _tempDir() =>
    Directory.systemTemp.createTempSync('dmtools_file_content_');

/// Catalog checks for the content-oriented file tools.
void catalogTests() {
  group('fileTools catalog: content tools', () {
    final tools = fileTools();

    test('includes the content tool names', () {
      final names = tools.map((t) => t.name).toSet();
      for (final name in [
        'file_read_lines',
        'file_write_lines',
        'file_append',
        'file_info',
      ]) {
        expect(names, contains(name), reason: name);
      }
    });

    test('write_lines lines param is an array type', () {
      final param = toolNamed('file_write_lines')
          .params
          .firstWhere((p) => p.name == 'lines');
      expect(param.type, 'array');
    });

    test('every content tool belongs to the file integration', () {
      for (final name in [
        'file_read_lines',
        'file_write_lines',
        'file_append',
        'file_info',
      ]) {
        expect(toolNamed(name).integration, 'file', reason: name);
      }
    });
  });
}

/// [FileToolExecutor.readLines] tests.
void readLinesTests() {
  group('FileToolExecutor.readLines', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns each line as a list element', () async {
      final file = File('${tempDir.path}/lines.txt')
        ..writeAsStringSync('a\nb\nc');
      expect(await executor.readLines(file.path), ['a', 'b', 'c']);
    });

    test('returns an empty list for an empty file', () async {
      final file = File('${tempDir.path}/empty.txt')..writeAsStringSync('');
      expect(await executor.readLines(file.path), isEmpty);
    });
  });
}

/// [FileToolExecutor.writeLines] tests.
void writeLinesTests() {
  group('FileToolExecutor.writeLines', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('joins lines with newlines and writes them', () async {
      final path = '${tempDir.path}/wl.txt';
      await executor.writeLines(path, ['x', 'y', 'z']);
      expect(File(path).readAsStringSync(), 'x\ny\nz');
    });
  });
}

/// [FileToolExecutor.append] tests.
void appendTests() {
  group('FileToolExecutor.append', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('appends to existing content', () async {
      final path = '${tempDir.path}/app.txt';
      await executor.append(path, 'hello');
      await executor.append(path, ' world');
      expect(File(path).readAsStringSync(), 'hello world');
    });

    test('creates the file when it does not exist', () async {
      final path = '${tempDir.path}/newapp.txt';
      await executor.append(path, 'first');
      expect(File(path).readAsStringSync(), 'first');
    });
  });
}

/// [FileToolExecutor.getFileInfo] tests.
void fileInfoTests() {
  group('FileToolExecutor.getFileInfo', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns metadata for a file', () async {
      final file = File('${tempDir.path}/f.txt')..writeAsStringSync('content');
      final info = await executor.getFileInfo(file.path);
      expect(info['exists'], isTrue);
      expect(info['isDirectory'], isFalse);
      expect(info['size'], greaterThan(0));
      expect(info['modified'], isA<DateTime>());
    });

    test('returns metadata for a directory', () async {
      final info = await executor.getFileInfo(tempDir.path);
      expect(info['exists'], isTrue);
      expect(info['isDirectory'], isTrue);
    });

    test('reports exists=false for a missing path', () async {
      final info = await executor.getFileInfo('${tempDir.path}/nope');
      expect(info['exists'], isFalse);
      expect(info['isDirectory'], isFalse);
    });
  });
}

/// Dispatch tests for content-oriented ops (read_lines, write_lines, append, info).
void dispatchContentTests() {
  group('execute dispatch: content ops', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('routes file_read_lines', () async {
      final file = File('${tempDir.path}/rl.txt')..writeAsStringSync('1\n2');
      final result = await executor
          .execute('file_read_lines', {'path': file.path}) as List<String>;
      expect(result, ['1', '2']);
    });

    test('routes file_write_lines', () async {
      await executor.execute('file_write_lines', {
        'path': '${tempDir.path}/wl.txt',
        'lines': ['p', 'q'],
      });
      expect(File('${tempDir.path}/wl.txt').readAsStringSync(), 'p\nq');
    });

    test('routes file_append', () async {
      final path = '${tempDir.path}/ap.txt';
      File(path).writeAsStringSync('base');
      await executor.execute('file_append', {'path': path, 'content': '!'});
      expect(File(path).readAsStringSync(), 'base!');
    });

    test('routes file_info', () async {
      final file = File('${tempDir.path}/i.txt')..writeAsStringSync('x');
      final info = await executor.execute('file_info', {'path': file.path})
          as Map<String, dynamic>;
      expect(info['exists'], isTrue);
    });
  });
}
