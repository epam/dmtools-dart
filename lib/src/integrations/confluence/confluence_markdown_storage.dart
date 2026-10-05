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
  return _wrapStorage(node, parts);
}

/// Wraps already-rendered child [parts] for the storage tag [node.name].
String _wrapStorage(_XmlNode node, List<String> parts) {
  final inner = parts.join();
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

/// Inline emphasis/code tags (and unknown tags: children verbatim).
String _wrapInlineStyle(_XmlNode node, String inner) {
  switch (node.name) {
    case 'strong':
    case 'b':
      return '**$inner**';
    case 'em':
    case 'i':
      return '*$inner*';
    case 'del':
    case 'strike':
      return '~~$inner~~';
    case 'code':
      return '`${node.content}`';
  }
  return inner;
}

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

/// Renders a `code` macro (or other macros as fenced plain text).
String _macroToMarkdown(_XmlNode node) {
  if (node.attrs['ac:name'] == 'native-embed:whiteboard') {
    return _whiteboardMarker(node);
  }
  final body = node.child('ac:plain-text-body')?.content ??
      node.child('ac:rich-text-body')?.content ??
      '';
  final lang = node.attrs['ac:name'] == 'code'
      ? node.child('ac:parameter')?.content ?? ''
      : '';
  final fence = lang.isEmpty ? '```' : '```$lang';
  return '\n\n$fence\n$body\n```\n\n';
}

/// `[Whiteboard (content not available via API)…]` marker for
/// `native-embed:whiteboard` macros (Java 932e0db0): whiteboard content is
/// not exposed by the Confluence API, so only a marker with the whiteboard
/// `url` parameter (when present) is kept.
String _whiteboardMarker(_XmlNode node) {
  for (final param in node.children) {
    if (param.name == 'ac:parameter' && param.attrs['ac:name'] == 'url') {
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

/// Collects `tr > th/td` cell text from [node] into [rows].
void _collectRows(_XmlNode node, List<List<String>> rows) {
  if (node.name == 'tr') {
    rows.add([
      for (final cell in node.children)
        if (cell.name == 'td' || cell.name == 'th') cell.content.trim(),
    ]);
    return;
  }
  for (final child in node.children) {
    _collectRows(child, rows);
  }
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
