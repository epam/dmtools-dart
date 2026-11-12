part of 'confluence_markdown.dart';

/// Storage → Markdown side of the converters: the structural XML parser
/// ([_parseXml] via [_XmlNode]) and the Markdown renderer it feeds. Split
/// into a part file to keep both halves under the file-size gate.

// ── Storage → Markdown: XML parsing ────────────────────────────────────────

/// A minimal XML node: [name], [attrs], [children], or a text/cDATA [text].
class _XmlNode {
  final String? name;
  final Map<String, String> attrs;
  final List<_XmlNode> children;
  String text;

  _XmlNode.text(String this.text)
      : name = null,
        attrs = const {},
        children = const [];

  _XmlNode.tag(String this.name)
      : attrs = {},
        children = [],
        text = '';

  /// Concatenated descendant text (entities unescaped; `<time>` date
  /// lozenges contribute their `datetime` attribute — the Java preprocess
  /// substitutes them before rendering, bb1b51e9).
  String get content => children.map(_childContent).join();

  /// The text one [child] contributes to [_XmlNode.content].
  String _childContent(_XmlNode child) {
    if (child.name == null) return unescapeXml(child.text);
    if (child.name == 'time') return child.attrs['datetime'] ?? child.content;
    if (child.name == 'br') return '<br/>';
    return child.content;
  }

  /// First child element named [tag], or `null`.
  _XmlNode? child(String tag) {
    for (final c in children) {
      if (c.name == tag) return c;
    }
    return null;
  }
}

final _xmlToken = RegExp(
  r'<(/?)([a-zA-Z][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*"[^"]*")*)\s*(/?)>'
  r'|<!\[CDATA\[(.*?)\]\]>',
  dotAll: true,
);
final _xmlAttr = RegExp(r'([\w:.-]+)\s*=\s*"([^"]*)"');

/// Storage heading tags `h1`…`h6`.
final _storageHeadingTag = RegExp(r'^h[1-6]$');

/// Parses a storage-format fragment into a synthetic root node.
_XmlNode _parseXml(String storage) {
  final root = _XmlNode.tag('#root');
  final stack = <_XmlNode>[root];
  var pos = 0;
  while (pos < storage.length) {
    final matches = _xmlToken.allMatches(storage, pos);
    if (matches.isEmpty) {
      _appendText(stack.last, storage.substring(pos).trim());
      break;
    }
    final m = matches.first;
    if (m.start > pos) {
      _appendText(stack.last, storage.substring(pos, m.start));
    }
    _applyToken(stack, m);
    pos = m.end;
  }
  return root;
}

/// Appends [raw] text to [node], collapsing whitespace runs to single
/// spaces (kept even when whitespace-only, so inline siblings stay
/// separated; block wrappers trim their own boundaries).
void _appendText(_XmlNode node, String raw) {
  node.children.add(_XmlNode.text(raw.replaceAll(RegExp(r'\s+'), ' ')));
}

/// Applies one matched tag/cDATA [token] to the parse [stack].
void _applyToken(List<_XmlNode> stack, RegExpMatch m) {
  final cdata = m.group(5);
  if (cdata != null) {
    stack.last.children.add(_XmlNode.text(cdata));
    return;
  }
  final closing = m.group(1) == '/';
  final name = m.group(2)!;
  if (closing) {
    if (stack.length > 1) stack.removeLast();
    return;
  }
  final node = _XmlNode.tag(name);
  for (final attr in _xmlAttr.allMatches(m.group(3) ?? '')) {
    node.attrs[attr.group(1)!] = unescapeXml(attr.group(2)!);
  }
  stack.last.children.add(node);
  if (m.group(4) != '/') stack.add(node); // not self-closing
}

// ── Storage → Markdown: rendering ──────────────────────────────────────────

/// Renders an XML [node] subtree as Markdown.
String _storageNodeToMarkdown(_XmlNode node) {
  if (node.name == null) return unescapeXml(node.text);
  final parts = [
    for (final child in node.children) _storageNodeToMarkdown(child),
  ];
/// Joins child [parts], merging touching strike runs (`~~A~~~~B~~` →
/// `~~AB~~`) so adjacent `<del>` siblings never emit `~~~~`.
String _joinParts(_XmlNode node, List<String> parts) {
  final buf = StringBuffer();
  var prevStrike = false;
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    final strike = _isStrikeTag(node.children[i]);
    final merge = prevStrike && strike && _touches(buf, part);
    if (merge) {
      final text = buf.toString();
      buf
        ..clear()
        ..write(text.substring(0, text.length - 2))
        ..write(part.substring(2));
    } else {
      buf.write(part);
    }
    prevStrike = strike;
  }
  return buf.toString();
}

/// Whether [buf] ends and [part] starts with a strike marker.
bool _touches(StringBuffer buf, String part) =>
    buf.toString().endsWith('~~') && part.startsWith('~~');

/// Strike tags (`del`/`s`/`strike`, case-insensitive).
const _strikeTags = {'del', 's', 'strike'};
bool _isStrikeTag(_XmlNode node) =>
    _strikeTags.contains(node.name?.toLowerCase());

/// Wraps [inner] in `~~`, moving edge whitespace outside the markers;
/// whitespace-only content yields just the whitespace.
String _strike(String inner) {
  final m = RegExp(r'^(\s*)([\s\S]*?)(\s*)$').firstMatch(inner)!;
  final body = m[2]!;
  if (body.isEmpty) return inner;
  return '${m[1]}~~$body~~${m[3]}';
}

  return _wrapStorage(node, parts);
}

/// Wraps already-rendered child [parts] for the storage tag [node.name].
String _wrapStorage(_XmlNode node, List<String> parts) {
  final inner = _joinParts(node, parts);
  return _wrapHeadingOrParagraph(node, inner) ??
      _wrapListOrStructural(node, inner) ??
      _wrapConfluenceBlock(node, inner) ??
      _wrapTimeTag(node, inner) ??
      _wrapAdfNode(node, inner) ??
      _wrapAnchorOrImage(node) ??
      _wrapInlineStyle(node, inner);
}

/// Storage heading/paragraph tags; `null` for anything else.
String? _wrapHeadingOrParagraph(_XmlNode node, String inner) {
  final name = node.name ?? '';
  if (_storageHeadingTag.hasMatch(name)) {
    return '\n\n${'#' * int.parse(name[1])} ${inner.trim()}\n\n';
  }
  switch (name) {
    case 'p':
      return '\n\n${inner.trim()}\n\n';
    case 'br':
      return '\n';
  }
  return null;
}

/// Storage list/quote/rule tags; `null` for anything else.
String? _wrapListOrStructural(_XmlNode node, String inner) {
  switch (node.name) {
    case 'hr':
      return '\n\n---\n\n';
    case 'blockquote':
      return '\n\n${_quoteLines(inner)}\n\n';
    case 'ul':
    case 'ol':
    case 'ac:task-list':
      return '\n${_listItems(node, node.name == 'ol')}\n';
  }
  return null;
}

/// Confluence macro/table wrappers; `null` for anything else.
String? _wrapConfluenceBlock(_XmlNode node, String inner) {
  switch (node.name) {
    case 'ac:image':
      return _imageToMarkdown(node);
    case 'ac:link':
      return _linkToMarkdown(node);
    case 'ac:task':
      return _taskToMarkdown(node);
    case 'ac:structured-macro':
      return _macroToMarkdown(node);
    case 'table':
      return _tableToMarkdown(node);
    case 'li':
      return inner;
  }
  return null;
}

/// `<time datetime="…">` date lozenges (Java bb1b51e9): the date lives only
/// in the attribute, so it is rendered verbatim (an absent attribute falls
/// back to the element's inner text); `null` for anything else.
String? _wrapTimeTag(_XmlNode node, String inner) {
  if (node.name != 'time') return null;
  final datetime = node.attrs['datetime'];
  return datetime == null ? inner : datetime;
}

/// `ac:adf-node` wrappers (Java dm.ai #596 parity): a synced block
/// (`type="bodied-sync-block"`) renders its `ac:adf-content` payload inline
/// via the normal converters (falling back to the rendered children when the
/// content element is missing); any other adf-node — draw.io / ecosystem
/// extension with no readable content — becomes the `[Diagram]` placeholder.
/// `null` for anything else.
String? _wrapAdfNode(_XmlNode node, String inner) {
  if (node.name != 'ac:adf-node') return null;
  if (node.attrs['type'] != 'bodied-sync-block') return '\n[Diagram]\n';
  final content = node.child('ac:adf-content');
  return content == null ? inner : _storageNodeToMarkdown(content);
}

/// Plain HTML anchors/images; `null` for anything else.
String? _wrapAnchorOrImage(_XmlNode node) {
  switch (node.name) {
    case 'a':
      return '[${node.content}](${node.attrs['href'] ?? ''})';
    case 'img':
      return '![${node.attrs['alt'] ?? ''}](${node.attrs['src'] ?? ''})';
  }
  return null;
}

/// Markers for inline emphasis/strike tags (`_wrapInlineStyle`).
const _inlineStyleMarkers = <String, String>{
  'strong': '**',
  'b': '**',
  'em': '*',
  'i': '*',
};
  if (_isStrikeTag(node)) return _strike(inner);

/// Inline emphasis/code tags (and unknown tags: children verbatim).
String _wrapInlineStyle(_XmlNode node, String inner) {
  final marker = _inlineStyleMarkers[node.name];
  if (marker != null) return '$marker$inner$marker';
  if (node.name == 'code') return '`${node.content}`';
  return _wrapStyledSpan(node, inner);
}

/// `<span style="…line-through…">` becomes strikethrough; other spans pass through.
String _wrapStyledSpan(_XmlNode node, String inner) {
  if (node.name == 'span' && _isLineThrough(node)) return _strike(inner);
  return inner;
}

/// Whether a `<span style="…">` carries `text-decoration: line-through`.
bool _isLineThrough(_XmlNode node) =>
    (node.attrs['style'] ?? '').toLowerCase().contains('line-through');

/// Prefixes every line of [inner] with `> `.
String _quoteLines(String inner) => inner
    .trim()
    .split('\n')
    .map((l) => l.trim().isEmpty ? '>' : '> $l')
    .join('\n');

/// Renders `<ac:image>` (attachment or plain URL) as Markdown.
String _imageToMarkdown(_XmlNode node) {
  final attachment = node.child('ri:attachment')?.attrs['ri:filename'];
  if (attachment != null) return '![$attachment]($attachment)';
  final url = node.child('ri:url')?.attrs['ri:value'] ?? '';
  return '![]($url)';
}

/// Renders `<ac:link>` (page, attachment, or URL) as Markdown.
String _linkToMarkdown(_XmlNode node) {
  final body = node.child('ac:link-body')?.content ?? '';
  final page = node.child('ri:page')?.attrs['ri:content-title'];
  if (page != null) return '[${body.isEmpty ? page : body}]($page)';
  final attachment = node.child('ri:attachment')?.attrs['ri:filename'];
  if (attachment != null)
    return '[${body.isEmpty ? attachment : body}]($attachment)';
  final url = node.child('ri:url')?.attrs['ri:value'] ?? '';
  return '[${body.isEmpty ? url : body}]($url)';
}

/// Renders `<ac:task>` as a `- [ ]`/`- [x]` item.
String _taskToMarkdown(_XmlNode node) {
  final status = node.child('ac:task-status')?.content ?? 'incomplete';
  final body = node.child('ac:task-body')?.content ?? '';
  return '- [${status == 'complete' ? 'x' : ' '}] $body\n';
}

const _kAcParameterTag = 'ac:parameter';
const _kAcNameAttr = 'ac:name';

/// Titled container macros whose optional `title` parameter is emitted as a
/// bold paragraph above their rich-text body (`dm.ai#847` parity).
const _titledContainerMacros = <String>{
  'expand',
  'panel',
  'info',
  'note',
  'warning',
  'tip',
  'details',
};

/// Structured macros whose content is already meaningful from `body.storage`
/// alone (`ConfluenceStorageMarkdown.SAFE_LOCAL_MACROS` parity).
const _safeLocalMacros = <String>{
  'toc',
  'code',
  'info',
  'note',
  'warning',
  'tip',
  'panel',
  'expand',
  'status',
  'children',
  'childpages',
  'anchor',
  'excerpt',
};

/// Renders a structured macro as Markdown (`code`, `children`, `whiteboard`,
/// titled containers like `expand`/`panel`/`note`, or rich-text bodies).
String _macroToMarkdown(_XmlNode node) {
  final macroName = (node.attrs[_kAcNameAttr] ?? '').toLowerCase();
  if (_simpleMacroHandlers.containsKey(macroName)) {
    return _simpleMacroHandlers[macroName]!(node);
  }
  final plainBody = node.child('ac:plain-text-body');
  if (macroName == 'code' || plainBody != null) {
    return _codeMacroToMarkdown(node, plainBody?.content ?? '');
  }
  final richBody = node.child('ac:rich-text-body');
  if (richBody != null) {
    return _richBodyMacroToMarkdown(node, macroName, richBody);
  }
  return '';
}

String _childPagesMacro(_XmlNode _) => '\n\n[Child pages]\n\n';
String _emptyMacro(_XmlNode _) => '';

final Map<String, String Function(_XmlNode)> _simpleMacroHandlers = {
  'native-embed:whiteboard': _whiteboardMarker,
  'children': _childPagesMacro,
  'childpages': _childPagesMacro,
  'toc': _emptyMacro,
  'anchor': _emptyMacro,
  'status': _statusMacroToMarkdown,
};

String _statusMacroToMarkdown(_XmlNode node) {
  for (final child in node.children) {
    if (child.name == _kAcParameterTag &&
        child.attrs[_kAcNameAttr] == 'title') {
      final t = child.content.trim();
      if (t.isNotEmpty) return '[$t]';
    }
  }
  return '';
}

String _codeMacroToMarkdown(_XmlNode node, String body) {
  var lang = '';
  for (final child in node.children) {
    if (child.name == _kAcParameterTag &&
        (child.attrs[_kAcNameAttr] == 'language' ||
            child.attrs[_kAcNameAttr] == null)) {
      lang = child.content.trim();
      if (lang.isNotEmpty) break;
    }
  }
  final fence = lang.isEmpty ? '```' : '```$lang';
  return '\n\n$fence\n$body\n```\n\n';
}

String _richBodyMacroToMarkdown(
  _XmlNode node,
  String macroName,
  _XmlNode richBody,
) {
  final title = _extractMacroTitle(node, macroName);
  final bodyMd = [
    for (final child in richBody.children)
      if (child.name != _kAcParameterTag) _storageNodeToMarkdown(child),
  ].join().trim();
  if (title.isNotEmpty && _titledContainerMacros.contains(macroName)) {
    return bodyMd.isEmpty
        ? '\n\n**$title**\n\n'
        : '\n\n**$title**\n\n$bodyMd\n\n';
  }
  return bodyMd.isEmpty ? '' : '\n\n$bodyMd\n\n';
}

String _extractMacroTitle(_XmlNode node, String macroName) {
  for (final child in node.children) {
    if (child.name != _kAcParameterTag) continue;
    final paramName = (child.attrs[_kAcNameAttr] ?? '').toLowerCase();
    if (paramName == 'title' || (paramName.isEmpty && macroName == 'expand')) {
      return child.content.trim();
    }
  }
  return '';
}

/// `[Whiteboard (content not available via API)…]` marker for
/// `native-embed:whiteboard` macros (Java 932e0db0): whiteboard content is
/// not exposed by the Confluence API, so only a marker with the whiteboard
/// `url` parameter (when present) is kept.
String _whiteboardMarker(_XmlNode node) {
  for (final param in node.children) {
    if (param.name == _kAcParameterTag && param.attrs[_kAcNameAttr] == 'url') {
      final url = param.content.trim();
      if (url.isNotEmpty) {
        return '\n[Whiteboard (content not available via API): $url]\n';
      }
    }
  }
  return '\n[Whiteboard (content not available via API)]\n';
}

/// Renders a `<table>` subtree as a GFM pipe table.
String _tableToMarkdown(_XmlNode node) {
  final rows = <List<String>>[];
  _collectRows(node, rows);
  if (rows.isEmpty) return '';
  final buf = StringBuffer();
  buf.write('| ${rows.first.join(' | ')} |\n');
  buf.write('|${rows.first.map((_) => ' --- ').join('|')}|\n');
  for (var i = 1; i < rows.length; i++) {
    buf.write('| ${rows[i].join(' | ')} |\n');
  }
  return '\n\n$buf\n\n';
}

/// Collects direct `tr > th/td` cell text from [node] into [rows] (`dm.ai#847`
/// parity: nested tables inside a `<td>`/`<th>` cell are rendered inline rather
/// than leaking as extra top-level rows of the enclosing table).
void _collectRows(_XmlNode node, List<List<String>> rows) {
  for (final tr in _directTableRows(node)) {
    final cells = <String>[
      for (final cell in tr.children)
        if (cell.name == 'td' || cell.name == 'th') _cellToMarkdown(cell),
    ];
    if (cells.isNotEmpty) rows.add(cells);
  }
}

const Set<String> _tableSectionTags = {'thead', 'tbody', 'tfoot'};

List<_XmlNode> _directTableRows(_XmlNode table) {
  final trs = <_XmlNode>[];
  for (final child in table.children) {
    final tag = (child.name ?? '').toLowerCase();
    if (tag == 'tr') {
      trs.add(child);
    } else if (_tableSectionTags.contains(tag)) {
      trs.addAll(
        child.children.where((r) => (r.name ?? '').toLowerCase() == 'tr'),
      );
    }
  }
  return trs;
}

String _cellToMarkdown(_XmlNode cell) {
  final parts = <String>[];
  for (final child in cell.children) {
    if ((child.name ?? '').toLowerCase() == 'table') {
      final nested = _nestedTableInline(child);
      if (nested.isNotEmpty) parts.add(nested);
    } else {
      parts.add(cell._childContent(child));
    }
  }
  return parts
      .join()
      .replaceAll('|', r'\|')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _nestedTableInline(_XmlNode table) {
  final rowStrings = <String>[];
  for (final tr in _directTableRows(table)) {
    final cells = <String>[
      for (final cell in tr.children)
        if (cell.name == 'td' || cell.name == 'th')
          if (_cellToMarkdown(cell).isNotEmpty) _cellToMarkdown(cell),
    ];
    if (cells.isNotEmpty) rowStrings.add(cells.join(': '));
  }
  return rowStrings.join('<br/>');
}

/// Renders list items of [node] as Markdown lines (nested lists indented).
String _listItems(_XmlNode node, bool ordered) {
  final buf = StringBuffer();
  var n = 1;
  for (final item in node.children) {
    if (item.name == 'ac:task') {
      buf.write(_taskToMarkdown(item));
    } else if (item.name == 'li') {
      final body = _indentNested(
        _storageNodeToMarkdown(item).replaceAll(RegExp(r'\n{2,}'), '\n').trim(),
      );
      buf.write(ordered ? '$n. $body\n' : '- $body\n');
      n++;
    }
  }
  return buf.toString();
}

/// Indents a rendered item body's nested-list continuation lines.
String _indentNested(String body) {
  final lines = body.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      i == 0 || lines[i].trim().isEmpty ? lines[i] : '    ${lines[i]}',
  ].join('\n');
}

// ── Storage + export_view section fallback (`dm.ai#847` parity) ────────────

typedef _DocSection = ({String? headingKey, List<_XmlNode> nodes});

String _renderStorageWithExportViewFallback(
  String storageHtml,
  String exportViewHtml,
) {
  final storageRoot = _parseXml(storageHtml);
  final exportRoot = _parseXml(exportViewHtml);
  final storageSections = _splitSections(_unwrapRootElements(storageRoot));
  final exportSections = _splitSections(_unwrapRootElements(exportRoot));
  final merged = _mergeSections(storageSections, exportSections);
  final synthetic = _XmlNode.tag('#root')..children.addAll(merged);
  final rendered = _storageNodeToMarkdown(synthetic);
  return rendered
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]+\n'), '\n\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

const Set<String> _rootWrapperTags = {'div', 'body', 'html'};

List<_XmlNode> _unwrapRootElements(_XmlNode node) {
  var cur = node;
  while (cur.children.length == 1 &&
      _rootWrapperTags
          .contains((cur.children.first.name ?? '').toLowerCase())) {
    cur = cur.children.first;
  }
  return cur.children;
}

List<_DocSection> _splitSections(List<_XmlNode> nodes) {
  final sections = <_DocSection>[];
  var current = (headingKey: null as String?, nodes: <_XmlNode>[]);
  sections.add(current);
  for (final node in nodes) {
    final name = (node.name ?? '').toLowerCase();
    if (_storageHeadingTag.hasMatch(name)) {
      final key =
          node.content.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      current = (headingKey: key, nodes: <_XmlNode>[node]);
      sections.add(current);
    } else {
      current.nodes.add(node);
    }
  }
  return sections;
}

List<_XmlNode> _mergeSections(
  List<_DocSection> storageSections,
  List<_DocSection> exportSections,
) {
  final exportHeadingSections = [
    for (final s in exportSections)
      if (s.headingKey != null) s,
  ];
  final byHeading = <String, List<_DocSection>>{};
  for (final s in exportHeadingSections) {
    byHeading.putIfAbsent(s.headingKey!, () => <_DocSection>[]).add(s);
  }
  final out = <_XmlNode>[];
  var ordinal = 0;
  for (final s in storageSections) {
    if (s.headingKey == null) {
      out.addAll(s.nodes);
      continue;
    }
    final idx = ordinal++;
    if (!_sectionNeedsFallback(s.nodes)) {
      out.addAll(s.nodes);
      continue;
    }
    final match = _matchExportSection(
      s.headingKey!,
      byHeading,
      idx,
      exportHeadingSections,
    );
    if (match != null && _nodesContainTable(match.nodes)) {
      out.add(s.nodes.first);
      out.addAll(match.nodes.skip(1));
    } else {
      out.addAll(s.nodes);
    }
  }
  return out;
}

_DocSection? _matchExportSection(
  String key,
  Map<String, List<_DocSection>> byHeading,
  int ordinal,
  List<_DocSection> allHeadingSections,
) {
  final queue = byHeading[key];
  if (queue != null && queue.isNotEmpty) return queue.removeAt(0);
  if (ordinal < allHeadingSections.length) return allHeadingSections[ordinal];
  return null;
}

bool _sectionNeedsFallback(List<_XmlNode> nodes) {
  for (final n in nodes) {
    if (_hasUnresolvedMacro(n)) return true;
  }
  return false;
}

bool _hasUnresolvedMacro(_XmlNode node) {
  if (node.name == 'ac:structured-macro') {
    final macroName = (node.attrs['ac:name'] ?? '').toLowerCase();
    if (!_safeLocalMacros.contains(macroName)) return true;
  }
  for (final c in node.children) {
    if (_hasUnresolvedMacro(c)) return true;
  }
  return false;
}

bool _nodesContainTable(List<_XmlNode> nodes) {
  for (final n in nodes) {
    if (_hasTableNode(n)) return true;
  }
  return false;
}

bool _hasTableNode(_XmlNode node) {
  if ((node.name ?? '').toLowerCase() == 'table') return true;
  for (final c in node.children) {
    if (_hasTableNode(c)) return true;
  }
  return false;
}
