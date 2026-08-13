import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the batch-3 file tools (read_json, write_json, exists_in_path,
/// get_size) added to [FileToolExecutor] and [fileTools].
void main() {
  catalogTests();
  readJsonTests();
  writeJsonTests();
  existsInPathTests();
  getSizeTests();
  dispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    fileTools().firstWhere((t) => t.name == name);

/// Creates a temp directory for file-operation tests.
Directory _tempDir() =>
    Directory.systemTemp.createTempSync('dmtools_file_batch3_');

/// Catalog checks for the four new tools.
void catalogTests() {
  final tools = fileTools();

  group('fileTools catalog (batch 3)', () {
    test('registers nineteen tools total', () {
      expect(tools, hasLength(19));
    });

    test('includes the four new tool names', () {
      final names = tools.map((t) => t.name).toSet();
      for (final name in [
        'file_read_json',
        'file_write_json',
        'file_exists_in_path',
        'file_get_size',
      ]) {
        expect(names, contains(name), reason: name);
      }
    });

    test('write_json exposes path and data params', () {
      final params = toolNamed('file_write_json').params;
      expect(params.map((p) => p.name), ['path', 'data']);
      final dataParam = params.firstWhere((p) => p.name == 'data');
      expect(dataParam.type, 'object');
      expect(dataParam.required, isTrue);
    });

    test('exists_in_path exposes path and filename params', () {
      expect(
        toolNamed('file_exists_in_path').params.map((p) => p.name),
        ['path', 'filename'],
      );
    });

    test('every new tool belongs to the file integration', () {
      for (final name in [
        'file_read_json',
        'file_write_json',
        'file_exists_in_path',
        'file_get_size',
      ]) {
        expect(toolNamed(name).integration, 'file', reason: name);
      }
    });
  });
}

/// [FileToolExecutor.readJson] tests.
void readJsonTests() {
  group('FileToolExecutor.readJson', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('parses JSON object into a map', () async {
      final file = File('${tempDir.path}/a.json')
        ..writeAsStringSync('{"k": "v", "n": 3}');
      expect(await executor.readJson(file.path), {'k': 'v', 'n': 3});
    });

    test('throws on invalid JSON', () async {
      final file = File('${tempDir.path}/bad.json')..writeAsStringSync('{bad');
      expect(
        executor.readJson(file.path),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

/// [FileToolExecutor.writeJson] tests.
void writeJsonTests() {
  group('FileToolExecutor.writeJson', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('serializes a map and writes valid JSON', () async {
      final path = '${tempDir.path}/out.json';
      await executor.writeJson(path, {'name': 'x', 'count': 2});
      expect(File(path).readAsStringSync(), '{"name":"x","count":2}');
    });

    test('overwrites existing JSON content', () async {
      final path = '${tempDir.path}/ow.json';
      File(path).writeAsStringSync('{"old": true}');
      await executor.writeJson(path, {'old': false});
      expect(File(path).readAsStringSync(), '{"old":false}');
    });
  });
}

/// [FileToolExecutor.existsInPath] tests.
void existsInPathTests() {
  group('FileToolExecutor.existsInPath', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('finds a file nested in the directory tree', () async {
      Directory('${tempDir.path}/a/b').createSync(recursive: true);
      File('${tempDir.path}/a/b/needle.txt').writeAsStringSync('x');
      expect(
        await executor.existsInPath(tempDir.path, 'needle.txt'),
        isTrue,
      );
    });

    test('returns false when the file is absent', () async {
      File('${tempDir.path}/other.txt').writeAsStringSync('y');
      expect(
        await executor.existsInPath(tempDir.path, 'missing.txt'),
        isFalse,
      );
    });

    test('returns false for a missing root directory', () async {
      expect(
        await executor.existsInPath('${tempDir.path}/nope', 'x.txt'),
        isFalse,
      );
    });

    test('ignores directories matching the file name', () async {
      Directory('${tempDir.path}/dir.txt').createSync();
      expect(
        await executor.existsInPath(tempDir.path, 'dir.txt'),
        isFalse,
      );
    });
  });
}

/// [FileToolExecutor.getSize] tests.
void getSizeTests() {
  group('FileToolExecutor.getSize', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns the byte length of the file content', () async {
      final file = File('${tempDir.path}/s.txt')..writeAsStringSync('hello');
      expect(await executor.getSize(file.path), 5);
    });

    test('returns zero for an empty file', () async {
      final file = File('${tempDir.path}/empty.txt')..writeAsStringSync('');
      expect(await executor.getSize(file.path), 0);
    });
  });
}

/// Dispatch tests for the four new tools.
void dispatchTests() {
  group('execute dispatch (batch 3)', () {
    late FileToolExecutor executor;
    late Directory tempDir;

    setUp(() {
      executor = FileToolExecutor();
      tempDir = _tempDir();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('routes file_read_json', () async {
      final file = File('${tempDir.path}/rj.json')
        ..writeAsStringSync('{"a": 1}');
      final result =
          await executor.execute('file_read_json', {'path': file.path})
              as Map<String, dynamic>;
      expect(result, {'a': 1});
    });

    test('routes file_write_json', () async {
      final path = '${tempDir.path}/wj.json';
      await executor.execute('file_write_json', {
        'path': path,
        'data': {'b': 2},
      });
      expect(File(path).readAsStringSync(), '{"b":2}');
    });

    test('routes file_exists_in_path', () async {
      File('${tempDir.path}/f.txt').writeAsStringSync('x');
      final result = await executor.execute(
        'file_exists_in_path',
        {'path': tempDir.path, 'filename': 'f.txt'},
      ) as bool;
      expect(result, isTrue);
    });

    test('routes file_get_size', () async {
      final file = File('${tempDir.path}/gs.txt')..writeAsStringSync('abc');
      final result =
          await executor.execute('file_get_size', {'path': file.path}) as int;
      expect(result, 3);
    });
  });
}
