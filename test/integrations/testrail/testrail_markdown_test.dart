import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the TestRail Markdown-table converters ported from the Java
/// `TestRailClient` statics.
void main() {
  testRailFormatTests();
  testRailHtmlTests();
}

/// [convertMarkdownTablesToTestRailFormat] behavior.
void testRailFormatTests() {
  group('convertMarkdownTablesToTestRailFormat', () {
    test('converts a Markdown table with a separator row', () {
      const input = '| Col 1 | Col 2 |\n|---|---|\n| val1 | val2 |';
      expect(
        convertMarkdownTablesToTestRailFormat(input),
        '|||:Col 1|:Col 2\n||val1|val2\n',
      );
    });

    test('passes text already in TestRail format through unchanged', () {
      const input = '|||:Col 1|:Col 2\n||val1|val2\n';
      expect(convertMarkdownTablesToTestRailFormat(input), input);
    });

    test('returns table-free text unchanged', () {
      const input = 'plain text\nsecond line';
      expect(convertMarkdownTablesToTestRailFormat(input), input);
    });

    test('keeps surrounding text and drops trailing blank lines', () {
      const input = 'before\n| A | B |\n|---|---|\n| 1 | 2 |\nafter\n';
      expect(
        convertMarkdownTablesToTestRailFormat(input),
        'before\n|||:A|:B\n||1|2\nafter',
      );
    });

    test('handles multiple data rows', () {
      const input = '| H |\n|---|\n| a |\n| b |';
      expect(
        convertMarkdownTablesToTestRailFormat(input),
        '|||:H\n||a\n||b\n',
      );
    });

    test('treats an empty string as empty', () {
      expect(convertMarkdownTablesToTestRailFormat(''), '');
    });
  });
}

/// [convertMarkdownTablesToHtml] behavior.
void testRailHtmlTests() {
  group('convertMarkdownTablesToHtml', () {
    test('wraps plain text in paragraphs', () {
      expect(
        convertMarkdownTablesToHtml('Some text'),
        '<p>Some text</p>',
      );
    });

    test('converts a table with thead and tbody', () {
      const input = '| Col 1 | Col 2 |\n|---|---|\n| val1 | val2 |';
      expect(
        convertMarkdownTablesToHtml(input),
        '<table><thead><tr><th>Col 1</th><th>Col 2</th></tr></thead>'
        '<tbody><tr><td>val1</td><td>val2</td></tr></tbody></table>',
      );
    });

    test('flushes pending text before a table and skips blank lines', () {
      const input = 'Some text\n\n| A |\n|---|\n| 1 |\n\nafter';
      expect(
        convertMarkdownTablesToHtml(input),
        '<p>Some text</p><table><thead><tr><th>A</th></tr></thead>'
        '<tbody><tr><td>1</td></tr></tbody></table><p>after</p>',
      );
    });

    test('collects contiguous rows into a single table', () {
      const input = '| A |\n|---|\n| 1 |\n| B |\n|---|\n| 2 |';
      expect(
        convertMarkdownTablesToHtml(input),
        '<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td>'
        '</tr><tr><td>B</td></tr><tr><td>2</td></tr></tbody></table>',
      );
    });

    test('splits tables separated by a blank line', () {
      const input = '| A |\n|---|\n| 1 |\n\n| B |\n|---|\n| 2 |';
      expect(
        convertMarkdownTablesToHtml(input),
        '<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td>'
        '</tr></tbody></table><table><thead><tr><th>B</th></tr></thead>'
        '<tbody><tr><td>2</td></tr></tbody></table>',
      );
    });

    test('treats an empty string as empty', () {
      expect(convertMarkdownTablesToHtml(''), '');
    });
  });
}
