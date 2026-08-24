/// Markdown-table converters for TestRail text fields.
///
/// Ports the static converters of the Java `TestRailClient`:
/// - [convertMarkdownTablesToTestRailFormat] targets the plain-text fields of
///   the default template (`custom_preconds`, `custom_steps`,
///   `custom_expected`), where TestRail expects its `|||:Col|Col` table
///   syntax instead of Markdown pipes.
/// - [convertMarkdownTablesToHtml] targets the 'Test Case (Steps)' template
///   (template_id=2), whose fields are HTML: plain text is wrapped in `<p>`
///   tags and tables become `<table>` markup.
///
/// Text without Markdown tables is returned unchanged (text already in
/// TestRail `|||` format is never modified).
library;

/// Converts standard Markdown tables to TestRail's custom table format.
///
/// Markdown `| Col | Col |` tables become `|||:Col|:Col` header rows followed
/// by `||val|val` data rows; separator rows (`|---|---|`) are dropped. Lines
/// outside tables are preserved as-is.
String convertMarkdownTablesToTestRailFormat(String text) {
  if (text.isEmpty || text.contains('|||')) return text;
  final lines = _javaSplitLines(text);
  final result = StringBuffer();
  var i = 0;
  while (i < lines.length) {
    final taken = _takeTableRows(lines, i);
    if (taken.rows.isNotEmpty) {
      result.write(_convertSingleTable(taken.rows));
      i = taken.next;
    } else {
      result.write(lines[i]);
      if (i < lines.length - 1) result.write('\n');
      i++;
    }
  }
  return result.toString();
}

/// Converts Markdown text to the HTML shape the Steps template expects.
///
/// Plain lines are flushed as `<p>…</p>` paragraphs, Markdown tables become
/// `<table><thead>…</thead><tbody>…</tbody></table>`, and blank lines are
/// dropped.
String convertMarkdownTablesToHtml(String text) {
  if (text.isEmpty) return text;
  final lines = _javaSplitLines(text);
  final result = StringBuffer();
  final pendingTextLines = <String>[];
  var i = 0;
  while (i < lines.length) {
    final taken = _takeTableRows(lines, i);
    if (taken.rows.isNotEmpty) {
      _flushParagraphs(result, pendingTextLines);
      result.write(_convertSingleTableToHtml(taken.rows));
      i = taken.next;
    } else {
      pendingTextLines.add(lines[i].trim());
      i++;
    }
  }
  _flushParagraphs(result, pendingTextLines);
  return result.toString();
}

/// Collects the contiguous table-row lines starting at index [i] in [lines],
/// returning the trimmed rows and the index of the first line after the
/// table. [rows] is empty when [lines[i]] does not start a table.
({List<String> rows, int next}) _takeTableRows(List<String> lines, int i) {
  final rows = <String>[];
  while (i < lines.length && _isMarkdownTableRow(lines[i].trim())) {
    rows.add(lines[i].trim());
    i++;
  }
  return (rows: rows, next: i);
}

/// Writes each non-empty pending line to [out] as a `<p>` paragraph.
void _flushParagraphs(StringBuffer out, List<String> pending) {
  for (final line in pending) {
    if (line.isNotEmpty) out.write('<p>$line</p>');
  }
  pending.clear();
}

/// Returns `true` when [line] is a Markdown table row (`|…|`, length > 2).
bool _isMarkdownTableRow(String line) =>
    line.startsWith('|') && line.endsWith('|') && line.length > 2;

/// Splits [text] on newlines, dropping trailing empty strings like Java's
/// `String.split`.
List<String> _javaSplitLines(String text) {
  final lines = text.split('\n');
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Converts one Markdown table to TestRail `|||:header` / `||data` rows.
String _convertSingleTable(List<String> tableLines) {
  final result = StringBuffer();
  var isFirstDataRow = true;
  for (final cells in _parseTableRows(tableLines)) {
    if (isFirstDataRow) {
      result.write('||');
      for (final cell in cells) {
        result.write('|:$cell');
      }
      result.write('\n');
      isFirstDataRow = false;
    } else {
      result.write('||${cells.join('|')}\n');
    }
  }
  return result.toString();
}

/// Converts one Markdown table to HTML `<table>` markup.
String _convertSingleTableToHtml(List<String> tableLines) {
  final parsedRows = _parseTableRows(tableLines);
  if (parsedRows.isEmpty) return '';
  final result = StringBuffer('<table><thead><tr>');
  for (final cell in parsedRows.first) {
    result.write('<th>$cell</th>');
  }
  result.write('</tr></thead><tbody>');
  for (final row in parsedRows.skip(1)) {
    result.write('<tr>');
    for (final cell in row) {
      result.write('<td>$cell</td>');
    }
    result.write('</tr>');
  }
  return '$result</tbody></table>';
}

/// Splits table rows into trimmed cell lists, skipping separator rows and
/// rows that parse to no cells.
List<List<String>> _parseTableRows(List<String> tableLines) {
  final rows = <List<String>>[];
  for (final line in tableLines) {
    if (_isSeparatorRow(line)) continue;
    final cells = _splitCells(line);
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows;
}

/// Splits a table row into trimmed, non-empty cells.
List<String> _splitCells(String line) => line
    .split('|')
    .map((cell) => cell.trim())
    .where((cell) => cell.isNotEmpty)
    .toList();

/// Matches a Markdown separator row such as `|---|---|`.
bool _isSeparatorRow(String line) => RegExp(r'^\|[\s\-:|]+\|$').hasMatch(line);
