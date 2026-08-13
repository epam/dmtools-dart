import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for [KbClient] Markdown operations (search/get/index/write/delete/update).
void main() {
  searchDocsTests();
  getDocTests();
  indexDocsTests();
  createDocTests();
  deleteDocTests();
  updateDocTests();
}

/// Creates a temp knowledge base seeded with a small document tree.
Directory _tempKb() {
  final dir = Directory.systemTemp.createTempSync('dmtools_kb_test_');
  File('${dir.path}/intro.md')
      .writeAsStringSync('# Intro\n\nWelcome to the knowledge base.\n');
  Directory('${dir.path}/guides').createSync();
  File('${dir.path}/guides/setup.md')
      .writeAsStringSync('# Setup\n\nInstall the dark factory tooling.\n');
  File('${dir.path}/guides/notes.txt')
      .writeAsStringSync('Plain text is not indexed.\n');
  return dir;
}

/// [KbClient.searchDocs] full-text matching.
void searchDocsTests() {
  late KbClient client;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    client = KbClient(kb.path);
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbClient.searchDocs', () {
    test('finds matches across .md files with line numbers', () async {
      final results = await client.searchDocs('knowledge');
      expect(results, hasLength(1));
      expect(results.single.path, endsWith('intro.md'));
      expect(results.single.lineNumber, 3);
      expect(results.single.snippet, contains('knowledge base'));
    });

    test('matches case-insensitively', () async {
      final results = await client.searchDocs('WELCOME');
      expect(results, hasLength(1));
      expect(results.single.path, endsWith('intro.md'));
    });

    test('returns a match for every matching line across files', () async {
      final results = await client.searchDocs('the');
      expect(results, hasLength(2));
      expect(
        results.map((r) => r.path.split('/').last).toSet(),
        {'intro.md', 'setup.md'},
      );
    });

    test('ignores non-markdown files', () async {
      final results = await client.searchDocs('indexed');
      expect(results, isEmpty);
    });

    test('serializes results to MCP JSON', () async {
      final results = await client.searchDocs('knowledge');
      expect(results.single.toJson(), {
        'path': results.single.path,
        'line': 3,
        'snippet': 'Welcome to the knowledge base.',
      });
    });

    test('throws ArgumentError on empty query', () {
      expect(() => client.searchDocs(''), throwsArgumentError);
    });
  });
}

/// [KbClient.getDoc] document reads.
void getDocTests() {
  late KbClient client;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    client = KbClient(kb.path);
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbClient.getDoc', () {
    test('reads a document relative to the KB root', () async {
      final content = await client.getDoc('guides/setup.md');
      expect(content, contains('dark factory'));
    });

    test('reads a document via an absolute path', () async {
      final content = await client.getDoc('${kb.path}/intro.md');
      expect(content, startsWith('# Intro'));
    });

    test('throws FileSystemException for a missing document', () {
      expect(
        client.getDoc('no_such.md'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

/// [KbClient.indexDocs] recursive listing.
void indexDocsTests() {
  late KbClient client;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    client = KbClient(kb.path);
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbClient.indexDocs', () {
    test('lists all .md files recursively and sorted', () async {
      final files = await client.indexDocs('.');
      expect(
        files.map((f) => f.substring(kb.path.length + 1)).toList(),
        ['guides/setup.md', 'intro.md'],
      );
    });

    test('scopes indexing to a subdirectory', () async {
      final files = await client.indexDocs('guides');
      expect(files, hasLength(1));
      expect(files.single, endsWith('guides/setup.md'));
    });

    test('returns an empty list for a missing directory', () async {
      expect(await client.indexDocs('no_such_dir'), isEmpty);
    });
  });
}

/// A multi-section Markdown document used by the write/update tests.
const String _seedGuide = '# Guide\n'
    '\n'
    'first\n'
    '\n'
    '## Alpha\n'
    'old alpha\n'
    '\n'
    '### Sub\n'
    'sub body\n'
    '\n'
    '## Beta\n'
    'old beta\n';

/// [KbClient.createDoc] writes and overwrites.
void createDocTests() {
  late KbClient client;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    client = KbClient(kb.path);
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbClient.createDoc', () {
    test('creates a document and missing parent directories', () async {
      final path = await client.createDoc('notes/todo.md', 'hello');
      expect(path, endsWith('notes/todo.md'));
      expect(File('${kb.path}/notes/todo.md').readAsStringSync(), 'hello');
    });

    test('overwrites an existing document', () async {
      await client.createDoc('intro.md', 'replaced');
      expect(await client.getDoc('intro.md'), 'replaced');
    });

    test('throws ArgumentError for an empty path', () {
      expect(() => client.createDoc('', 'x'), throwsArgumentError);
    });
  });
}

/// [KbClient.deleteDoc] removal.
void deleteDocTests() {
  late KbClient client;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    client = KbClient(kb.path);
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbClient.deleteDoc', () {
    test('deletes a document and returns its path', () async {
      final path = await client.deleteDoc('guides/setup.md');
      expect(path, endsWith('guides/setup.md'));
      expect(File('${kb.path}/guides/setup.md').existsSync(), isFalse);
    });

    test('throws FileSystemException for a missing document', () {
      expect(
        client.deleteDoc('no_such.md'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

/// [KbClient.updateDoc] section replacement.
void updateDocTests() {
  late KbClient client;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    client = KbClient(kb.path);
    File('${kb.path}/guide.md').writeAsStringSync(_seedGuide);
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbClient.updateDoc', () {
    test('replaces a section body and writes the result back', () async {
      final updated = await client.updateDoc('guide.md', 'Alpha', 'new alpha');
      expect(updated, contains('## Alpha'));
      expect(updated, contains('new alpha'));
      expect(updated, isNot(contains('old alpha')));
      expect(updated, contains('## Beta'));
      expect(updated, contains('old beta'));
      expect(File('${kb.path}/guide.md').readAsStringSync(), updated);
    });

    test('a section includes its subsections', () async {
      final updated = await client.updateDoc('guide.md', 'Alpha', 'clean');
      expect(updated, isNot(contains('### Sub')));
      expect(updated, isNot(contains('sub body')));
    });

    test('a subsection ends at the next higher-level heading', () async {
      final updated = await client.updateDoc('guide.md', 'Sub', 'fresh sub');
      expect(updated, contains('fresh sub'));
      expect(updated, contains('## Alpha'));
      expect(updated, contains('old alpha'));
      expect(updated, contains('## Beta'));
    });

    test('replacing the last section keeps the rest intact', () async {
      final updated = await client.updateDoc('guide.md', 'Beta', 'beta two');
      expect(updated, contains('## Alpha'));
      expect(updated, contains('old alpha'));
      expect(updated, isNot(contains('old beta')));
    });

    test('throws ArgumentError when the section is missing', () {
      expect(
        () => client.updateDoc('guide.md', 'Nope', 'x'),
        throwsArgumentError,
      );
    });

    test('throws FileSystemException for a missing document', () {
      expect(
        client.updateDoc('no_such.md', 'Alpha', 'x'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
