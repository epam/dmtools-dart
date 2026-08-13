import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the [mermaidTools] catalog and [MermaidToolExecutor.render].
void main() {
  toolCatalogTests();
  renderTests();
  validationTests();
  unknownToolTests();
}

/// A minimal valid flowchart used across render tests.
const String _flowchart = 'graph TD; A-->B';

/// Catalog shape: name, integration, params, category.
void toolCatalogTests() {
  group('mermaidTools catalog', () {
    final tools = mermaidTools();

    test('registers a single mermaid_render tool', () {
      expect(tools.map((t) => t.name), ['mermaid_render']);
    });

    test('the tool belongs to the mermaid integration and diagrams category',
        () {
      final tool = tools.single;
      expect(tool.integration, 'mermaid');
      expect(tool.category, 'diagrams');
    });

    test('requires a diagram param and offers an optional format param', () {
      final tool = tools.single;
      final diagram = tool.params.singleWhere((p) => p.name == 'diagram');
      final format = tool.params.singleWhere((p) => p.name == 'format');
      expect(diagram.required, isTrue);
      expect(format.required, isFalse);
    });
  });
}

/// [MermaidToolExecutor.render] format wrapping.
void renderTests() {
  final executor = MermaidToolExecutor();

  group('MermaidToolExecutor.render', () {
    test('wraps a valid diagram in a mermaid code block', () async {
      expect(
        await executor.render(_flowchart),
        '```mermaid\n$_flowchart\n```',
      );
    });

    test('trims surrounding whitespace before wrapping', () async {
      expect(
        await executor.render('  $_flowchart\n\n'),
        '```mermaid\n$_flowchart\n```',
      );
    });

    test('returns the raw diagram for the raw format', () async {
      expect(
        await executor.render('  $_flowchart\n', 'raw'),
        _flowchart,
      );
    });

    test('defaults the unspecified format to markdown', () async {
      expect(
        await executor.render(_flowchart, null),
        '```mermaid\n$_flowchart\n```',
      );
    });

    test('accepts mixed-case format names', () async {
      expect(await executor.render(_flowchart, 'RAW'), _flowchart);
    });

    test('throws ArgumentError for an unsupported format', () {
      expect(() => executor.render(_flowchart, 'svg'), throwsArgumentError);
    });
  });
}

/// Diagram syntax validation performed inside [MermaidToolExecutor.render].
void validationTests() {
  final executor = MermaidToolExecutor();

  group('syntax validation', () {
    test('accepts every documented diagram keyword', () async {
      for (final keyword in mermaidDiagramKeywords) {
        final result = await executor.render('$keyword x', 'raw');
        expect(result, '$keyword x', reason: keyword);
      }
    });

    test('accepts keywords regardless of case', () async {
      expect(await executor.render('SequenceDiagram x', 'raw'),
          'SequenceDiagram x');
    });

    test('throws ArgumentError on an empty diagram', () {
      expect(() => executor.render('   '), throwsArgumentError);
    });

    test('throws ArgumentError on an unknown diagram type', () {
      expect(() => executor.render('notadiagram A-->B'), throwsArgumentError);
    });
  });
}

/// Unknown-tool rejection and execute dispatch.
void unknownToolTests() {
  final executor = MermaidToolExecutor();

  test('execute throws ArgumentError for an unknown tool', () {
    expect(
      () => executor.execute('mermaid_unknown', {'diagram': 'x'}),
      throwsArgumentError,
    );
  });

  test('execute routes mermaid_render to render', () async {
    final result = await executor.execute(
      'mermaid_render',
      {'diagram': _flowchart, 'format': 'raw'},
    ) as String;
    expect(result, _flowchart);
  });
}
