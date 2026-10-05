/// JS-bridge `file_list`/`file_exists`/`file_write` parity with Java
/// `FileTools`
/// (epam/dm.ai 3fa210e6, #635): the tools the agents suite relies on,
/// exposed through the same `executeToolViaJava` path the JS side uses.
///
/// Java `FileTools.listFiles` returns `{"entries": [absolute paths,
/// sorted]}`; `fileExists` returns a boolean (false for paths outside the
/// sandbox). The Dart bridge answers both as JSON strings. Note: Java
/// `listFiles` returns `null` for unlistable dirs; the Dart bridge returns
/// the `{"error": …}` envelope instead — a deliberate Dart convention.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/tool_bridge.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory dir;

void main() {
  setUp(() => dir = Directory.systemTemp.createTempSync('dmtools_fbridge'));
  tearDown(() => dir.deleteSync(recursive: true));
  fileListTests();
  fileExistsTests();
  fileWriteTests();
}

void fileListTests() {
  group('JS-bridge file_list (Java FileTools parity, dm.ai#635)', () {
    test('returns absolute, sorted entries as {"entries": [...]}', () {
      File('${dir.path}/b.txt').writeAsStringSync('b');
      File('${dir.path}/a.txt').writeAsStringSync('a');
      Directory('${dir.path}/sub').createSync();

      final result = jsonDecode(
        ToolBridge(registry: createDefaultToolRegistry())
            .execute('file_list', {'path': dir.path}),
      ) as Map<String, dynamic>;

      final entries = (result['entries'] as List).cast<String>();
      expect(entries, hasLength(3));
      // Pin the exact expected order — sorting a copy of the
      // implementation's own output would not catch a wrong comparator.
      expect(entries.map(p.basename), orderedEquals(['a.txt', 'b.txt', 'sub']));
      for (final entry in entries) {
        expect(p.isAbsolute(entry), isTrue, reason: entry);
        // Java parity (dm.ai#635): toAbsolutePath().normalize() per entry.
        expect(p.normalize(entry), entry, reason: entry);
      }
    });

    test(
        'entries are normalized (no . or .. segments), like Java '
        'toAbsolutePath().normalize()', () {
      File('${dir.path}/b.txt').writeAsStringSync('b');
      Directory('${dir.path}/sub').createSync();

      // The redundant "/." segment must not leak into the reported entries.
      final result = jsonDecode(
        ToolBridge(registry: createDefaultToolRegistry())
            .execute('file_list', {'path': '${dir.path}/.'}),
      ) as Map<String, dynamic>;

      final entries = (result['entries'] as List).cast<String>();
      expect(
        entries,
        orderedEquals([
          p.normalize('${dir.path}/b.txt'),
          p.normalize('${dir.path}/sub'),
        ]),
      );
    });

    test('unlistable path yields the error envelope, not a crash', () {
      final result = jsonDecode(
        ToolBridge(registry: createDefaultToolRegistry())
            .execute('file_list', {'path': '${dir.path}/missing'}),
      ) as Map<String, dynamic>;
      expect(result['error'], isA<String>());
    });
  });
}

void fileExistsTests() {
  group('JS-bridge file_exists (Java FileTools parity, dm.ai#635)', () {
    test('reports true for an existing file and false for a missing one', () {
      final file = File('${dir.path}/a.txt')..writeAsStringSync('a');
      final bridge = ToolBridge(registry: createDefaultToolRegistry());

      expect(
        jsonDecode(bridge.execute('file_exists', {'path': file.path})),
        {'exists': true},
      );
      expect(
        jsonDecode(bridge.execute('file_exists', {'path': '${dir.path}/nope'})),
        {'exists': false},
      );
    });
  });
}

void fileWriteTests() {
  group(
      'JS-bridge file_write (gh-361: parent-dir behavior of Java '
      'FileTools.writeFile)', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());

    test('creates missing parent directories before writing (gh-361)', () {
      // Java writeFile: Files.createDirectories(parentDir) before
      // Files.writeString — a write to a nested non-existent path succeeds
      // (the token-usage reporter depends on this for its cache file).
      // Parent creation only: Java's traversal sandbox is out of scope
      // here (pre-existing bridge family gap, see follow-up issue).
      final nested = '${dir.path}/outputs/token_usage/cache.json';

      expect(
        jsonDecode(bridge.execute('file_write', {
          'path': nested,
          'content': '{"tokens": 42}',
        })),
        {'success': true},
      );
      expect(File(nested).readAsStringSync(), '{"tokens": 42}');
    });

    test('creates multi-level parents in one call', () {
      final nested = '${dir.path}/a/b/c/d/e.txt';

      expect(
        jsonDecode(bridge.execute('file_write', {
          'path': nested,
          'content': 'deep',
        })),
        {'success': true},
      );
      expect(File(nested).readAsStringSync(), 'deep');
    });

    test('overwrites an existing file without touching the parent', () {
      Directory('${dir.path}/sub').createSync();
      final existing = '${dir.path}/sub/a.txt';
      File(existing).writeAsStringSync('old');

      expect(
        jsonDecode(bridge.execute('file_write', {
          'path': existing,
          'content': 'new',
        })),
        {'success': true},
      );
      expect(File(existing).readAsStringSync(), 'new');
    });

    test('rejects an empty path with the error envelope', () {
      final result = jsonDecode(
        bridge.execute('file_write', {'path': '', 'content': 'x'}),
      ) as Map<String, dynamic>;
      expect(result['error'], isA<String>());
    });
  });
}
