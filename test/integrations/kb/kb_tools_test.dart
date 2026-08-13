import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the [kbTools] catalog and [KbToolExecutor] dispatch.
void main() {
  toolCatalogTests();
  executorDispatchTests();
  unknownToolTests();
}

/// Creates a temp knowledge base with one Markdown document.
Directory _tempKb() {
  final dir = Directory.systemTemp.createTempSync('dmtools_kb_tools_test_');
  File('${dir.path}/doc.md').writeAsStringSync('dark factory notes\n');
  return dir;
}

/// Catalog shape: names, integration, params, category.
void toolCatalogTests() {
  group('kbTools catalog', () {
    final tools = kbTools();

    test('registers three tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'kb_search_docs',
        'kb_get_doc',
        'kb_index_docs',
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

/// Executor dispatch through [KbToolExecutor.execute].
void executorDispatchTests() {
  late KbToolExecutor executor;
  late Directory kb;

  setUp(() {
    kb = _tempKb();
    executor = KbToolExecutor(KbClient(kb.path));
  });

  tearDown(() => kb.deleteSync(recursive: true));

  group('KbToolExecutor.execute', () {
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
