/// Markdown / HTML → Jira wiki markup conversion for comment bodies posted
/// through the Jira sync path (gh-191, P6-JSY-09).
///
/// Dart port of the Java `MarkdownToJiraConverter.convertToJiraMarkdown`
/// (`dmtools-core/.../common/utils/MarkdownToJiraConverter.java`) — the
/// exact converter Java `JiraClient.postComment` runs when
/// `TrackerClient.TextType == MARKDOWN` (which `BasicJiraClient` always
/// returns for Jira), so agent-authored Markdown comments render with Jira
/// wiki formatting instead of raw Markdown.
///
/// The Java converter has three input branches, all ported here:
/// - **pure Markdown** (no HTML tags outside code spans/fences):
///   ``` fences → `{code:lang}…{code}`, `#`-headings → `hN.`, `**bold**` →
///   `*bold*`, `` `code` `` → `{{code}}`, `[t](u)` → `[t|u]`,
///   `![name|attrs]` → `!name|attrs!`;
/// - **pure HTML**: walked with an HTML DOM (package:html — the Jsoup
///   equivalent), block elements → Jira constructs (`<ul>` → `* item`,
///   `<table>` → `|cell|`/`||header||`, `<pre><code>` → `{code:lang}`);
/// - **mixed**: split on blank lines, each chunk routed to the branch that
///   matches it, ```` ``` ```` and `<code>` spans preserved verbatim across
///   the round trip via [HtmlCodeBlockPreserver].
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

/// Converts [input] (Markdown, HTML, or a mix) to Jira wiki markup.
///
/// Empty/whitespace-only input yields `""`; a body consisting solely of HTML
/// entities is decoded as-is; otherwise the Markdown/HTML branches above
/// apply. Mirrors `MarkdownToJiraConverter.convertToJiraMarkdown`.
String markdownToJiraMarkup(String? input) {
  if (input == null || input.trim().isEmpty) return '';
  if (_containsOnlyHtmlEntities(input)) return decodeHtmlEntities(input);
  final hasMarkdown =
      input.contains('#') || input.contains('```') || input.contains('* ');
  final hasHtml = containsHtmlTags(input);
  if (hasMarkdown && hasHtml) return _convertMixedContent(input);
  if (hasHtml) return _convertHtmlToJiraMarkup(input);
  return _convertMarkdownToJiraMarkup(input);
}

/// Marker a `<code>` span is swapped for while the surrounding body is
/// converted; [HtmlCodeBlockPreserver.restoreCodeBlocks] swaps the Jira
/// `{code}` construct back in.
const codeBlockPlaceholder = '___CODE_BLOCK_PLACEHOLDER___';

/// Decodes the five basic HTML entities (`&lt; &gt; &amp; &quot; &apos;`).
///
/// Java parity: `MarkdownToJiraConverter.unescapeHtml` performs exactly these
/// replacements (its post-pass `-%gt;` rewrite is dead code — `&gt;` is
/// already gone) plus newline normalization.
String decodeHtmlEntities(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll(RegExp(r'\r\n?|\u2028|\u2029'), '\n');

/// Whether [input] consists solely of HTML entity references.
bool _containsOnlyHtmlEntities(String input) {
  if (!input.contains('&')) return false;
  return input.replaceAll(RegExp(r'&[a-zA-Z]+;'), '').trim().isEmpty;
}

/// Whether [s] contains HTML tags outside code fences and inline code spans.
///
/// Java parity: `containsHtml` strips ```-fenced blocks and `` ` `` spans
/// before testing `<[^>]+>`.
bool containsHtmlTags(String s) {
  final noFences = s.replaceAll(
      RegExp(r'```(\w*)\n([\s\S]*?)```'), '');
  final noCode = noFences.replaceAll(RegExp(r'`[^`]*`'), '');
  return RegExp(r'<[^>]+>').hasMatch(noCode);
}

/// Mixed branch: split on blank lines and route each chunk to the Markdown
/// or HTML converter (Java `convertMixedContent`).
String _convertMixedContent(String input) {
  final preserver = HtmlCodeBlockPreserver();
  final preserved = preserver.preserveCodeBlocks(input);
  final parts = <String>[];
  for (final chunk in preserved.split('\n')) {
    final trimmed = chunk.trim();
    if (trimmed.isEmpty) continue;
    parts.add(containsHtmlTags(trimmed)
        ? _convertHtmlToJiraMarkup(trimmed)
        : _convertMarkdownToJiraMarkup(trimmed));
  }
  final joined = preserver.restoreCodeBlocks(parts.join('\n'));
  return joined.trim();
}

/// Markdown branch: line walk with code-fence tracking and paragraph
/// accumulation (Java `convertMarkdownToJiraMarkdown`).
String _convertMarkdownToJiraMarkup(String markdown) {
  final blocks = <String>[];
  var inCodeBlock = false;
  final codeBuf = StringBuffer();
  var codeLang = '';
  final paragraph = StringBuffer();

  void flushParagraph() {
    if (paragraph.isNotEmpty) {
      blocks.add(_processTextParagraph(paragraph.toString()));
      paragraph.clear();
    }
  }

  for (final line in markdown.split('\n')) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith('```')) {
      if (!inCodeBlock) {
        flushParagraph();
        inCodeBlock = true;
        codeLang = trimmedLine.substring(3).trim();
      } else {
        final code = codeBuf
            .toString()
            .replaceAll(RegExp(r'^\r?\n+'), '')
            .replaceAll(RegExp(r'\r?\n+$'), '');
        blocks.add('{code:${codeLang.isEmpty ? 'java' : codeLang}}$code{code}');
        inCodeBlock = false;
        codeBuf.clear();
        codeLang = '';
      }
      continue;
    }
    if (inCodeBlock) {
      codeBuf.writeln(line);
      continue;
    }
    final processed = _processImages(line);
    if (trimmedLine.isEmpty) {
      flushParagraph();
    } else {
      if (paragraph.isNotEmpty) paragraph.writeln();
      paragraph.write(processed);
    }
  }
  flushParagraph();
  return blocks.join('\n\n').trim();
}

/// `![name|attrs]` → `!name|attrs!` (Java `processImages`).
String _processImages(String text) => text.replaceAll(
      RegExp(r'!\[(.*?)\|([^\]]+)\]'),
      '!\$1|\$2!',
    );

/// Per-paragraph Markdown inline conversion (Java `processTextParagraph`):
/// `1. **bold opener**` → `*bold opener*` bullets, `#`-headings, inline code,
/// bold, and links.
String _processTextParagraph(String text) {
  final output = <String>[];
  for (final line in _processImages(text).split('\n')) {
    var trimmed = line.trim();
    trimmed = trimmed.replaceAll(
        RegExp(r'^1\. \*\*(.*?)\*\*'), '*\$1*');
    final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
    if (heading != null) {
      output.add('h${heading.group(1)!.length}. ${heading.group(2)}');
      continue;
    }
    trimmed = trimmed
        .replaceAll(RegExp(r'`\s*([^`]+)\s*`'), '{{\$1}}')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), '*\$1*')
        .replaceAll(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), '[\$1|\$2]');
    output.add(trimmed);
  }
  return output.join('\n');
}

/// Whether [tag] starts a new block in the HTML walker (Java `isBlockLevel`).
bool _isBlockLevel(String tag) => switch (tag) {
      'ac:structured-macro' ||
      'p' ||
      'pre' ||
      'ul' ||
      'ol' ||
      'table' ||
      'h1' ||
      'h2' ||
      'h3' ||
      'h4' ||
      'h5' ||
      'h6' ||
      'code' ||
      'strong' ||
      'em' ||
      'b' ||
      'i' ||
      'a' =>
        true,
      _ => false,
    };

/// HTML branch: enumerates the body's top-level nodes, accumulating inline
/// runs and flushing them as paragraphs between blocks (Java
/// `convertHtmlToJiraMarkdown`).
String _convertHtmlToJiraMarkup(String html) {
  final preserver = HtmlCodeBlockPreserver();
  final preserved = preserver.preserveCodeBlocks(html);
  final body = parse(preserved).body!;
  final nodes = body.nodes;

  final blocks = <String>[];
  final inlineBuffer = StringBuffer();

  void flushInline() {
    final raw = inlineBuffer.toString().trim();
    inlineBuffer.clear();
    if (raw.isEmpty) return;
    blocks.add(_processParagraph(parse(raw).body!));
  }

  var i = 0;
  while (i < nodes.length) {
    final node = nodes[i];
    if (node is dom.Element) {
      final tag = node.localName!.toLowerCase();
      if (_isBlockLevel(tag)) {
        flushInline();
        final special = _consecutiveInlineBlock(nodes, i, tag, node);
        if (special != null) {
          blocks.add(special.block);
          i = special.nextIndex;
          i++;
          continue;
        }
        blocks.add(_handleBlockElement(node));
      } else {
        inlineBuffer.write(node.outerHtml);
      }
    } else {
      inlineBuffer.write(_escapeTextNode(node.text ?? ''));
    }
    i++;
  }
  flushInline();

  final joined =
      blocks.where((b) => b.trim().isNotEmpty).join('\n\n').trim();
  return preserver.restoreCodeBlocks(_fixNewlineBeforeLink(joined));
}

/// Result of a special-cased top-level inline run (`<strong>+<ul>`, `<b>` /
/// `<i>` chains, top-level `<a>`).
typedef _SpecialBlock = ({String block, int nextIndex});

/// Handles the special top-level element runs the Java walker treats as
/// blocks: `<strong>` directly followed by `<ul>`, chains of sibling `<b>` /
/// `<i>` elements, and a top-level `<a>`. Returns `null` for the normal
/// block path. [nodes] is the body child list and [i] the current index of
/// [el] with [tag].
_SpecialBlock? _consecutiveInlineBlock(
  List<dom.Node> nodes,
  int i,
  String tag,
  dom.Element el,
) {
  if (tag == 'strong' &&
      i + 1 < nodes.length &&
      nodes[i + 1] is dom.Element &&
      (nodes[i + 1] as dom.Element).localName!.toLowerCase() == 'ul') {
    final heading = '# *${el.text.trim()}*';
    return (
      block: '$heading\n${_processUnorderedList(nodes[i + 1] as dom.Element)}',
      nextIndex: i + 1,
    );
  }
  if (tag == 'b' || tag == 'i') {
    final combined = StringBuffer(_trimLeadingSpaces(el.outerHtml));
    var j = i;
    while (j + 1 < nodes.length &&
        nodes[j + 1] is dom.Element &&
        (nodes[j + 1] as dom.Element).localName!.toLowerCase() == tag) {
      combined
        ..write(' ')
        ..write(_trimLeadingSpaces((nodes[j + 1] as dom.Element).outerHtml));
      j++;
    }
    return (
      block: _processParagraph(parse(combined.toString()).body!),
      nextIndex: j,
    );
  }
  if (tag == 'a') {
    return (
      block: '[${el.text}|${el.attributes['href'] ?? ''}]',
      nextIndex: i,
    );
  }
  return null;
}

/// Strips leading whitespace from every element's own text, destroying
/// nested markup in the process (Java `trimLeadingSpaces` — `Element.text()`
/// clears children).
String _trimLeadingSpaces(String html) {
  final body = parse(html).body!;
  for (final e in body.querySelectorAll('*')) {
    final own = e.nodes.whereType<dom.Text>().map((t) => t.text).join();
    if (own.isEmpty) continue;
    final cleaned = own.replaceFirst(RegExp(r'^\s+'), '');
    if (cleaned != own) {
      e
        ..nodes.clear()
        ..append(dom.Text(cleaned));
    }
  }
  return body.innerHtml;
}

/// Escapes a bare text node for re-parsing (Jsoup `TextNode.outerHtml`
/// round-trips the text entity-escaped).
String _escapeTextNode(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Dispatches a block-level element to its Jira construct (Java
/// `handleBlockElement`).
String _handleBlockElement(dom.Element el) {
  final tag = el.localName!.toLowerCase();
  if (tag.startsWith('h') && tag.length == 2) {
    return 'h${tag[1]}. ${el.text}';
  }
  return switch (tag) {
    'p' => _processParagraph(el),
    'pre' => _processPre(el),
    'ul' => _processUnorderedList(el),
    'ol' => _processOrderedList(el),
    'table' => _processTable(el),
    'code' || 'ac:structured-macro' => _processCodeElement(el),
    _ => _processParagraph(el),
  };
}

/// The shared inline replacement chain for paragraph/list/table cells
/// (Java's repeated `pClone.html()` replacement chain).
String _inlineMarkup(String html) => html
    .replaceAll(
        RegExp(r'(?i)<a\s+href="([^"]+)">(.*?)</a>'), '[\$2|\$1]')
    .replaceAll(RegExp(r'(?i)<strong>(.*?)</strong>'), '*\$1*')
    .replaceAll(RegExp(r'(?i)<em>(.*?)</em>'), '_$1_')
    .replaceAll(RegExp(r'(?i)<b>(.*?)</b>'), '*\$1*')
    .replaceAll(RegExp(r'(?i)<i>(.*?)</i>'), '_$1_')
    .replaceAll(RegExp(r'(?i)<br\s*/?>'), '\n')
    .replaceAll(RegExp('(?)<code>(?!\\$codeBlockPlaceholder\\d+)(.*?)</code>'),
        '{{\$1}}')
    .replaceAll(RegExp(r'<[^>]+>'), '');

/// Paragraph conversion: inline replacement chain over the element's inner
/// HTML, entity decode, trim (Java `processParagraph`).
String _processParagraph(dom.Element p) {
  final html = p.innerHtml;
  if (html.contains(codeBlockPlaceholder)) {
    return html.replaceAll(RegExp(r'(?i)</?code[^>]*>'), '');
  }
  final text = _inlineMarkup(html);
  return _fixNewlineBeforeLink(decodeHtmlEntities(text).trim());
}

/// `<code>` element: inline when single-line, `{code:lang}` block when
/// multi-line (Java `processCodeElement`).
String _processCodeElement(dom.Element codeEl) {
  if (codeEl.outerHtml.contains(codeBlockPlaceholder)) {
    return codeEl.outerHtml.replaceAll(RegExp(r'(?i)</?code[^>]*>'), '');
  }
  final codeText = decodeHtmlEntities(codeEl.innerHtml)
      .replaceAll(RegExp(r'^\r?\n+'), '')
      .replaceAll(RegExp(r'\r?\n+$'), '');
  final lang = codeEl.attributes['class']?.trim();
  if (codeText.contains('\n')) {
    return '\n{code:${lang == null || lang.isEmpty ? 'java' : lang}}\n'
        '$codeText\n{code}\n';
  }
  return '{{$codeText}}';
}

/// `<pre>` element: `<code>` child becomes a `{code:lang}` block; otherwise
/// the plain text (Java `processPre`).
String _processPre(dom.Element pre) {
  final codeEl = pre.querySelector('code');
  if (codeEl != null) {
    if (codeEl.innerHtml.contains(codeBlockPlaceholder)) {
      return codeEl.innerHtml.replaceAll(RegExp(r'(?i)</?code[^>]*>'), '');
    }
    final codeText = decodeHtmlEntities(codeEl.innerHtml)
        .replaceAll(RegExp(r'^\r?\n+'), '')
        .replaceAll(RegExp(r'\r?\n+$'), '');
    final lang = codeEl.attributes['class']?.trim();
    return '{code:${lang == null || lang.isEmpty ? 'java' : lang}}\n'
        '$codeText\n{code}';
  }
  return decodeHtmlEntities(pre.text ?? '');
}

/// `<ul>` → `* item` lines with nested-list recursion (Java
/// `processUnorderedList`).
String _processUnorderedList(dom.Element ul) {
  final sb = StringBuffer();
  for (final li in ul.children.where((c) => c.localName == 'li')) {
    sb.writeln('* ${_listItemText(li)}');
    _appendNestedLists(sb, li);
  }
  return sb.toString().trim();
}

/// `<ol>` → `# item` lines; a direct `<strong>+<ul>` pair becomes a
/// `# *heading*` + bullets block (Java `processOrderedList`).
String _processOrderedList(dom.Element ol) {
  final sb = StringBuffer();
  for (final li in ol.children.where((c) => c.localName == 'li')) {
    final strongEl = li.children.where((c) => c.localName == 'strong');
    final nestedUl = li.children.where((c) => c.localName == 'ul');
    if (strongEl.isNotEmpty && nestedUl.isNotEmpty) {
      sb
        ..writeln('# *${strongEl.first.text.trim()}*')
        ..writeln(_processUnorderedList(nestedUl.first));
      continue;
    }
    if (li.innerHtml.contains(codeBlockPlaceholder)) {
      sb.writeln(
          li.innerHtml.replaceAll(RegExp(r'(?i)</?code[^>]*>'), ''));
      continue;
    }
    sb.writeln('# ${_listItemText(li)}');
    _appendNestedLists(sb, li);
  }
  return sb.toString().trim();
}

/// The inline-converted text of one `<li>` with nested lists stripped (the
/// shared middle of the two list processors).
String _listItemText(dom.Element li) {
  final clone = li.clone(true);
  clone.querySelectorAll('ul,ol').forEach((e) => e.remove());
  final raw = clone.innerHtml.replaceAll(RegExp(r'(?i)</?code[^>]*>'), '');
  return decodeHtmlEntities(_listInlineMarkup(raw)).trim();
}

/// List-item inline chain — like [_inlineMarkup] but `<br>` also swallows
/// trailing whitespace (Java list variant).
String _listInlineMarkup(String html) => html
    .replaceAll(
        RegExp(r'(?i)<a\s+href="([^"]+)">(.*?)</a>'), '[\$2|\$1]')
    .replaceAll(RegExp(r'(?i)<strong>(.*?)</strong>'), '*\$1*')
    .replaceAll(RegExp(r'(?i)<em>(.*?)</em>'), '_$1_')
    .replaceAll(RegExp(r'(?i)<b>(.*?)</b>'), '*\$1*')
    .replaceAll(RegExp(r'(?i)<i>(.*?)</i>'), '_$1_')
    .replaceAll(RegExp(r'(?i)<br\s*/?>\s*'), '\n')
    .replaceAll(RegExp('(?)<code>(?!\\$codeBlockPlaceholder\\d+)(.*?)</code>'),
        '{{\$1}}')
    .replaceAll(RegExp(r'<[^>]+>'), '');

/// Appends nested `<ul>`/`<ol>` children of [li] to [sb] (Java's recursion
/// tail in both list processors).
void _appendNestedLists(StringBuffer sb, dom.Element li) {
  for (final child in li.children) {
    final tag = child.localName?.toLowerCase();
    if (tag == 'ul') {
      sb.writeln(_processUnorderedList(child));
    } else if (tag == 'ol') {
      sb.writeln(_processOrderedList(child));
    }
  }
}

/// `<table>` → Jira table markup: `||header||` rows first, then `|cell|`
/// rows; `<br>` inside a cell becomes a literal `\\` line continuation
/// (Java `processTable`).
String _processTable(dom.Element table) {
  final sb = StringBuffer();
  var headerDone = false;
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('th,td');
    if (cells.isEmpty) continue;
    if (!headerDone && row.querySelectorAll('th').isNotEmpty) {
      sb.write('||');
      for (final th in cells) {
        final trimmed = th.text.trim();
        sb
          ..write(decodeHtmlEntities(trimmed.isEmpty ? ' ' : trimmed))
          ..write('||');
        for (var i = 1; i < _colspan(th); i++) {
          sb.write(' ||');
        }
      }
      sb.writeln();
      headerDone = true;
    } else {
      sb.write('|');
      for (final cell in cells) {
        if (cell.innerHtml.contains(codeBlockPlaceholder)) {
          sb
            ..write(cell.innerHtml
                .replaceAll(RegExp(r'(?i)</?code[^>]*>'), ''))
            ..write('|');
        } else {
          final cellText = _tableCellMarkup(cell.innerHtml);
          final trimmed = cellText.trim().replaceAll('|', '/');
          sb
            ..write(decodeHtmlEntities(trimmed.isEmpty ? ' ' : trimmed))
            ..write('|');
        }
        for (var i = 1; i < _colspan(cell); i++) {
          sb.write(' |');
        }
      }
      sb.writeln();
    }
  }
  return sb.toString().trim();
}

/// Table-cell inline chain — `<br>` becomes newline + two literal
/// backslashes (the Jira table line break, Java `processTable` cell chain).
String _tableCellMarkup(String html) => html
    .replaceAll(
        RegExp(r'(?i)<a\s+href="([^"]+)">(.*?)</a>'), '[\$2|\$1]')
    .replaceAll(RegExp(r'(?i)<strong>(.*?)</strong>'), '*\$1*')
    .replaceAll(RegExp(r'(?i)<em>(.*?)</em>'), '_$1_')
    .replaceAll(RegExp(r'(?i)<b>(.*?)</b>'), '*\$1*')
    .replaceAll(RegExp(r'(?i)<br\s*/?>'), '\n\\\\')
    .replaceAll(RegExp(r'(?i)<i>(.*?)</i>'), '_$1_')
    .replaceAll(RegExp('(?)<code>(?!\\$codeBlockPlaceholder\\d+)(.*?)</code>'),
        '{{\$1}}')
    .replaceAll(RegExp(r'<[^>]+>'), '');

/// Numeric `colspan` attribute of [cell], `1` when absent or unparseable.
int _colspan(dom.Element cell) =>
    int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;

/// Java `fixNewlineBeforeLink` — the three literal regex passes from the
/// original, ported unchanged (two of them are effectively no-ops but keep
/// byte-parity with the Java output).
String _fixNewlineBeforeLink(String text) => text
    .replaceAll(RegExp(r'(\S)\n\[(https?://)'), '\$1\n[\$2')
    .replaceAll(RegExp(r'\n\[\n(https?://)'), '\n[https://')
    .replaceAll(RegExp(r'\n\[https?://'), '\n[https://');

/// Preserves `<code>…</code>` spans across HTML parsing/conversion by
/// swapping them for indexed placeholders (Dart port of the Java
/// `HTMLCodeBlockPreserver`).
class HtmlCodeBlockPreserver {
  static final _codePattern =
      RegExp(r'<code[^>]*>(.*?)</code>', dotAll: true);
  static final _classPattern = RegExp(r'class=["\']([^"\']*)["\']');

  final List<({String content, String language, bool isInline})>
      _preservedCodeBlocks = [];

  /// Swaps every `<code>` span for a placeholder element; spans already
  /// carrying a placeholder are left alone.
  String preserveCodeBlocks(String html) => html.replaceAllMapped(
        _codePattern,
        (match) {
          final fullMatch = match.group(0)!;
          final codeContent = match.group(1)!;
          if (codeContent.contains(codeBlockPlaceholder)) return fullMatch;
          final classMatch = _classPattern.firstMatch(fullMatch);
          final language = classMatch?.group(1) ?? 'java';
          final isInline =
              !fullMatch.contains('class=') && !codeContent.contains('\n');
          _preservedCodeBlocks
              .add((content: codeContent, language: language, isInline: isInline));
          return '<code>$codeBlockPlaceholder${_preservedCodeBlocks.length - 1}'
              '</code>';
        },
      );

  /// Swaps each placeholder back for its Jira construct: `{{inline}}` for
  /// single-line spans, `{code:lang}…{code}` blocks otherwise (`properties`
  /// maps to `bash` like the Java `mapLanguage`).
  String restoreCodeBlocks(String processedHtml) {
    var result = processedHtml;
    for (var i = 0; i < _preservedCodeBlocks.length; i++) {
      final block = _preservedCodeBlocks[i];
      final lines = block.content.split(RegExp(r'\r?\n'));
      final normalized = lines
          .where((line) => line.isNotEmpty)
          .join('\n')
          .replaceAll(RegExp(r'[\r\n]+$'), '');
      final text = decodeHtmlEntities(normalized);
      final replacement = block.isInline
          ? '{{${text.trim()}}}'
          : '{code:${_mapLanguage(block.language)}}$text{code}';
      result = result.replaceAll('$codeBlockPlaceholder$i', replacement);
    }
    return result;
  }

  static String _mapLanguage(String language) =>
      language.equalsIgnoreCase('properties') ? 'bash' : language;
}

/// Case-insensitive comparison helper local to this library.
extension on String {
  bool equalsIgnoreCase(String other) =>
      toLowerCase() == other.toLowerCase();
}
