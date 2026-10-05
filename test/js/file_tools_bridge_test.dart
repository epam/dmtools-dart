/// JS-bridge `file_list`/`file_exists` parity with Java `FileTools`
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

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dmtools_fbridge'));
  tearDown(() => dir.deleteSync(recursive: true));

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
