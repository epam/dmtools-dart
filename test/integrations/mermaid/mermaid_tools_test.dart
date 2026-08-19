import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the [mermaidTools] catalog and [MermaidToolExecutor].
void main() {
  toolCatalogTests();
  renderTests();
  exportTests();
  validateTests();
  validationTests();
  listTypesTests();
  unknownToolTests();
}

/// A minimal valid flowchart used across render/export tests.
const String _flowchart = 'graph TD; A-->B';

/// Catalog shape: names, integration, params, category.
void toolCatalogTests() {
  group('mermaidTools catalog', () {
    final tools = mermaidTools();

    test('registers render, validate, export, and list_types tools', () {
      expect(tools.map((t) => t.name), [
        'mermaid_render',
        'mermaid_validate',
        'mermaid_export',
        'mermaid_list_types',
      ]);
    });

    test('every tool belongs to the mermaid integration and diagrams category',
        () {
      expect(tools.every((t) => t.integration == 'mermaid'), isTrue);
      expect(tools.every((t) => t.category == 'diagrams'), isTrue);
    });

    test('render requires diagram and offers an optional format', () {
      final tool = tools.firstWhere((t) => t.name == 'mermaid_render');
      expect(
        tool.params.singleWhere((p) => p.name == 'diagram').required,
        isTrue,
      );
      expect(
        tool.params.singleWhere((p) => p.name == 'format').required,
        isFalse,
      );
    });

    test('validate requires only a diagram param', () {
      final tool = tools.firstWhere((t) => t.name == 'mermaid_validate');
      expect(tool.params.map((p) => p.name), ['diagram']);
    });

    test('export requires diagram and offers an optional format', () {
      final tool = tools.firstWhere((t) => t.name == 'mermaid_export');
      expect(
        tool.params.singleWhere((p) => p.name == 'diagram').required,
        isTrue,
      );
      expect(
        tool.params.singleWhere((p) => p.name == 'format').required,
        isFalse,
      );
    });

    test('list_types takes no parameters', () {
      final tool = tools.firstWhere((t) => t.name == 'mermaid_list_types');
      expect(tool.params, isEmpty);
    });
  });
}

/// [MermaidToolExecutor.render] format wrapping.
void renderTests() {
  final executor = MermaidToolExecutor();

  group('MermaidToolExecutor.render', () {
    test('wraps a valid diagram in a mermaid code block', () async {
      expect(await executor.render(_flowchart), '```mermaid\n$_flowchart\n```');
    });

    test('trims surrounding whitespace before wrapping', () async {
      expect(
        await executor.render('  $_flowchart\n\n'),
        '```mermaid\n$_flowchart\n```',
      );
    });

    test('returns the raw diagram for the raw format', () async {
      expect(await executor.render('  $_flowchart\n', 'raw'), _flowchart);
    });

    test('defaults the unspecified format to markdown', () async {
      expect(
        await executor.render(_flowchart, null),
        '```mermaid\n$_flowchart\n```',
      );
    });

    test('throws ArgumentError for an unsupported format', () {
      expect(() => executor.render(_flowchart, 'svg'), throwsArgumentError);
    });
  });
}

/// [MermaidToolExecutor.export] format outputs.
void exportTests() {
  final executor = MermaidToolExecutor();

  group('MermaidToolExecutor.export', () {
    test('wraps a valid diagram in a markdown block by default', () async {
      expect(await executor.export(_flowchart), '```mermaid\n$_flowchart\n```');
    });

    test('returns the raw diagram for the raw format', () async {
      expect(await executor.export(_flowchart, 'raw'), _flowchart);
    });

    test('returns a standalone svg document for the svg format', () async {
      final svg = await executor.export(_flowchart, 'svg');
      expect(svg, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(svg, contains('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('A--&gt;B'));
    });

    test('accepts mixed-case format names', () async {
      expect(await executor.export(_flowchart, 'RAW'), _flowchart);
    });

    test('trims the diagram before exporting', () async {
      expect(await executor.export('  $_flowchart\n', 'raw'), _flowchart);
    });

    test('throws ArgumentError for an invalid diagram', () {
      expect(
        () => executor.export('notadiagram A-->B', 'svg'),
        throwsArgumentError,
      );
    });

    test('rejects the png format without a renderer', () {
      expect(() => executor.export(_flowchart, 'png'), throwsArgumentError);
    });
  });
}

/// [MermaidToolExecutor.validate] reporting.
void validateTests() {
  final executor = MermaidToolExecutor();

  group('MermaidToolExecutor.validate', () {
    test('reports valid with the detected diagram type', () async {
      expect(await executor.validate(_flowchart), {
        'valid': true,
        'diagram_type': 'graph',
      });
    });

    test('reports the diagram type in lowercase', () async {
      expect(await executor.validate('SequenceDiagram x'), {
        'valid': true,
        'diagram_type': 'sequencediagram',
      });
    });

    test('reports invalid for an unknown diagram type', () async {
      final result = await executor.validate('notadiagram A-->B');
      expect(result['valid'], isFalse);
      expect(result['error'] as String, contains('Unknown diagram type'));
    });

    test('reports invalid for an empty diagram', () async {
      expect(
        await executor.validate('   '),
        {'valid': false, 'error': 'Diagram must not be empty'},
      );
    });

    test('does not throw on invalid syntax', () async {
      expect(() => executor.validate('notadiagram A'), returnsNormally);
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
      expect(
        await executor.render('SequenceDiagram x', 'raw'),
        'SequenceDiagram x',
      );
    });

    test('throws ArgumentError on an empty diagram', () {
      expect(() => executor.render('   '), throwsArgumentError);
    });

    test('throws ArgumentError on an unknown diagram type', () {
      expect(() => executor.render('notadiagram A-->B'), throwsArgumentError);
    });
  });
}

/// [MermaidToolExecutor.listTypes] diagram-type enumeration.
void listTypesTests() {
  final executor = MermaidToolExecutor();

  group('MermaidToolExecutor.listTypes', () {
    test('returns every supported diagram keyword', () async {
      final types = await executor.listTypes();
      expect(types, containsAll(mermaidDiagramKeywords));
      expect(types.length, mermaidDiagramKeywords.length);
    });

    test('includes flowchart and sequencediagram', () async {
      final types = await executor.listTypes();
      expect(types, containsAll(['flowchart', 'sequencediagram']));
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

  test('execute routes mermaid_validate to validate', () async {
    final result = await executor.execute(
      'mermaid_validate',
      {'diagram': _flowchart},
    ) as Map<String, dynamic>;
    expect(result, {'valid': true, 'diagram_type': 'graph'});
  });

  test('execute routes mermaid_export to export', () async {
    final result = await executor.execute(
      'mermaid_export',
      {'diagram': _flowchart, 'format': 'svg'},
    ) as String;
    expect(result, contains('<svg'));
  });

  test('execute routes mermaid_list_types to listTypes', () async {
    final result = await executor.execute('mermaid_list_types', {}) as List;
    expect(result, containsAll(['flowchart', 'gantt']));
  });
}
