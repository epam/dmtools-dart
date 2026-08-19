import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the [kbTools] catalog and [KbToolExecutor] dispatch.
void main() {
  readCatalogTests();
  searchAndListCatalogParamTests();
  mutationCatalogTests();
  readDispatchTests();
  searchAndListDispatchTests();
  writeDispatchTests();
  unknownToolTests();
}

/// Creates a temp knowledge base with one Markdown document.
Directory _tempKb() {
  final dir = Directory.systemTemp.createTempSync('dmtools_kb_tools_test_');
  File('${dir.path}/doc.md').writeAsStringSync('dark factory notes\n');
  return dir;
}

/// Read-side catalog shape: names, integration, params, category.
void readCatalogTests() {
  group('kbTools read catalog', () {
    final tools = kbTools();

    test('registers eight tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'kb_search_docs',
        'kb_search_docs_full',
        'kb_get_doc',
        'kb_index_docs',
        'kb_list_dirs',
        'kb_create_doc',
        'kb_delete_doc',
        'kb_update_doc',
      ]);
    });

    test('every tool belongs to the kb integration', () {
      expect(tools.every((t) => t.integration == 'kb'), isTrue);
    });

    test('every tool is in the docs category', () {
      expect(tools.every((t) => t.category == 'docs'), isTrue);
    });

    test('kb_search_docs requires a query param', () {
      final tool = kbTools().firstWhere((t) => t.name == 'kb_search_docs');
      final query = tool.params.singleWhere((p) => p.name == 'query');
      expect(query.required, isTrue);
    });

    test('kb_get_doc requires a path param', () {
      final tool = kbTools().firstWhere((t) => t.name == 'kb_get_doc');
      final path = tool.params.singleWhere((p) => p.name == 'path');
      expect(path.required, isTrue);
    });

    test('kb_index_docs has an optional dir param', () {
      final tool = kbTools().firstWhere((t) => t.name == 'kb_index_docs');
      final dir = tool.params.singleWhere((p) => p.name == 'dir');
      expect(dir.required, isFalse);
    });
  });
}

/// Catalog param shape for the full-search and directory-listing tools.
void searchAndListCatalogParamTests() {
  group('kb_search_docs_full', () {
    final tool = kbTools().firstWhere((t) => t.name == 'kb_search_docs_full');

    test('requires query and max_results params', () {
      final query = tool.params.singleWhere((p) => p.name == 'query');
      final max = tool.params.singleWhere((p) => p.name == 'max_results');
      expect(query.required, isTrue);
      expect(max.required, isTrue);
      expect(max.type, 'number');
    });
  });

  group('kb_list_dirs', () {
    final tool = kbTools().firstWhere((t) => t.name == 'kb_list_dirs');

    test('has an optional base_path param', () {
      final base = tool.params.singleWhere((p) => p.name == 'base_path');
      expect(base.required, isFalse);
    });
  });
}

/// Mutation catalog shape: create/delete/update params.
void mutationCatalogTests() {
  group('kbTools mutation catalog', () {
    test('kb_create_doc requires path and content params', () {
      final tool = kbTools().firstWhere((t) => t.name == 'kb_create_doc');
      final path = tool.params.singleWhere((p) => p.name == 'path');
      final content = tool.params.singleWhere((p) => p.name == 'content');
      expect(path.required, isTrue);
      expect(content.required, isTrue);
    });

    test('kb_delete_doc requires a path param', () {
      final tool = kbTools().firstWhere((t) => t.name == 'kb_delete_doc');
      final path = tool.params.singleWhere((p) => p.name == 'path');
      expect(path.required, isTrue);
    });

    test('kb_update_doc requires path, section, and content params', () {
      final tool = kbTools().firstWhere((t) => t.name == 'kb_update_doc');
      expect(tool.params.map((p) => p.name), ['path', 'section', 'content']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Read-side executor dispatch through [KbToolExecutor.execute].
void readDispatchTests() {
  late KbToolExecutor executor;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    executor = KbToolExecutor(KbClient(kb.path));
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbToolExecutor.execute (read)', () {
    test('routes kb_search_docs to a full-text search', () async {
      final results =
          await executor.execute('kb_search_docs', {'query': 'factory'})
              as List<KbSearchResult>;
      expect(results, hasLength(1));
      expect(results.single.snippet, contains('dark factory'));
    });

    test('routes kb_get_doc to a document read', () async {
      final content =
          await executor.execute('kb_get_doc', {'path': 'doc.md'}) as String;
      expect(content, 'dark factory notes\n');
    });

    test('routes kb_index_docs to the KB root by default', () async {
      final files = await executor.execute('kb_index_docs', {}) as List<String>;
      expect(files, hasLength(1));
      expect(files.single, endsWith('doc.md'));
    });

    test('routes kb_index_docs to a given dir when supplied', () async {
      Directory('${kb.path}/nested').createSync();
      File('${kb.path}/nested/deep.md').writeAsStringSync('deep');
      final files = await executor.execute('kb_index_docs', {'dir': 'nested'})
          as List<String>;
      expect(files, hasLength(1));
      expect(files.single, endsWith('nested/deep.md'));
    });
  });
}

/// Executor dispatch for the full-search and directory-listing tools.
void searchAndListDispatchTests() {
  late KbToolExecutor executor;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    executor = KbToolExecutor(KbClient(kb.path));
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbToolExecutor.execute (full search and listing)', () {
    test('routes kb_search_docs_full and caps the result count', () async {
      final results = await executor.execute(
        'kb_search_docs_full',
        {'query': 'factory', 'max_results': 5},
      ) as List<KbSearchResult>;
      expect(results, hasLength(1));
      expect(results.single.snippet, contains('dark factory'));
    });

    test('kb_search_docs_full caps to zero when max_results is 0', () async {
      final results = await executor.execute(
        'kb_search_docs_full',
        {'query': 'factory', 'max_results': 0},
      ) as List<KbSearchResult>;
      expect(results, isEmpty);
    });

    test('routes kb_list_dirs to immediate subdirectories only', () async {
      Directory('${kb.path}/notes').createSync();
      File('${kb.path}/notes/x.md').writeAsStringSync('x');
      final dirs = await executor.execute('kb_list_dirs', {}) as List<String>;
      expect(dirs, hasLength(1));
      expect(dirs.single, endsWith('notes'));
    });

    test('kb_list_dirs returns empty for a missing directory', () async {
      final dirs = await executor.execute(
        'kb_list_dirs',
        {'base_path': 'no_such'},
      ) as List<String>;
      expect(dirs, isEmpty);
    });
  });
}

/// Mutation executor dispatch through [KbToolExecutor.execute].
void writeDispatchTests() {
  late KbToolExecutor executor;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    executor = KbToolExecutor(KbClient(kb.path));
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbToolExecutor.execute (mutation)', () {
    test('routes kb_create_doc to a document write', () async {
      final path = await executor.execute(
          'kb_create_doc', {'path': 'new.md', 'content': '# New\n'}) as String;
      expect(path, endsWith('new.md'));
      expect(File('${kb.path}/new.md').readAsStringSync(), '# New\n');
    });

    test('routes kb_delete_doc to a document delete', () async {
      final path =
          await executor.execute('kb_delete_doc', {'path': 'doc.md'}) as String;
      expect(path, endsWith('doc.md'));
      expect(File('${kb.path}/doc.md').existsSync(), isFalse);
    });

    test('routes kb_update_doc to a section replace', () async {
      File('${kb.path}/guide.md')
          .writeAsStringSync('# Guide\n\nold body\n\n## Next\nmore\n');
      final updated = await executor.execute('kb_update_doc', {
        'path': 'guide.md',
        'section': 'Next',
        'content': 'fresh next',
      }) as String;
      expect(updated, contains('fresh next'));
      expect(updated, isNot(contains('more')));
      expect(updated, contains('old body'));
    });
  });
}

/// Unknown-tool rejection.
void unknownToolTests() {
  final executor = KbToolExecutor(KbClient('.'));

  test('execute throws ArgumentError for an unknown tool', () {
    expect(
      () => executor.execute('kb_unknown', {'query': 'x'}),
      throwsArgumentError,
    );
  });
}
