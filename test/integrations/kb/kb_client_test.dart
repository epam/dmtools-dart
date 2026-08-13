import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for [KbClient] Markdown operations (search/get/index).
void main() {
  searchDocsTests();
  getDocTests();
  indexDocsTests();
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
