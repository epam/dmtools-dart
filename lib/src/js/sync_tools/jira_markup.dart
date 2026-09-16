/// Jira wiki markup → GitHub-flavored Markdown conversion for comment
/// bodies posted through the GitHub Issues tracker router (gh-125).
///
/// The agents' JS post-action templates hard-code Jira wiki markup
/// (`developBugAndCreatePR.js`, `preparePRForReview.js`, …), so every
/// machine comment landed on GitHub issues as raw `{code}` blocks and
/// `h3.` headers (gh-122). The Jira path must pass bodies through
/// unchanged (Java parity) — conversion applies ONLY where this router
/// serves the comment ([TrackerGitHubRouter] `_postComment`).
///
/// Constructs (owner's refined scope on gh-125):
/// - `{code:lang}` / `{code}lang` / `{code}` paired blocks → fenced
///   ``` blocks; a pair embedded after text becomes an inline backtick
///   span (a mid-line fence would not open a GFM code block, and a lone
///   trailing fence would swallow the rest of the comment); tags may be
///   whitespace-indented and a bare-tag hint tolerates leading
///   whitespace (`{code} dart`)
/// - `h1.`–`h6.` line prefixes → `#`–`######`
/// - `[text|url]` → `[text](url)`
/// - `{panel:title=X}` … `{panel}` → blockquote (indented openers behave
///   exactly like unindented ones)
/// - `{color:…} … {color}` → tags stripped, text kept
/// - `{{monospace}}` → `` `monospace` ``
///
/// Markdown-safety guarantees:
/// - a body without any Jira marker (`{code`, `{panel`, `{color`, `{{`,
///   `[text|url]`, an `h1.`–`h6.` line prefix) is returned
///   byte-for-byte — in particular `*text*` stays GFM *emphasis*, so
///   `*bold*` conversion applies only to Jira-sourced bodies;
/// - lines inside an existing Markdown ``` fence pass through verbatim
///   (quoted legacy markup inside a fence is never rewritten);
/// - everything inside a `{code}` block passes through verbatim.
library;

/// Cheap Jira-marker scan — a body without any of these is returned
/// unchanged (pure-Markdown passthrough; keeps `*italic*` intact).
final _jiraMarker = RegExp(
  r'\{code|\{panel|\{color|\{\{|\[[^\]\n|]+\|[^\]\n]+\]|^\s*h[1-6]\.',
  multiLine: true,
);

/// Opening `{code}` tag with an optional `:lang` suffix (an empty `:`
/// value is a valid "no language" hint); leading whitespace allowed so
/// indented tags behave like unindented ones.
final _codeOpen = RegExp(r'^\s*\{code(?::([\w#+.-]*))?\}');

/// Single-line `{code}…{code}` / `{code:lang}…{code}` pair.
final _codePair = RegExp(r'\{code(?::([\w#+.-]+))?\}([^\n]*?)\{code\}');

/// `lang rest…` after a bare `{code}` opening tag — the first token is
/// the language hint, the remainder the block's first content line.
final _langRest = RegExp(r'^(\S+)(?:\s+([^\n]*))?$');

/// Jira heading prefix (`h1.`–`h6.`).
final _heading = RegExp(r'^\s*h([1-6])\.\s*');

/// Panel opening tag with an optional `:title=…` (whitespace-lenient —
/// indented openers must not be dropped).
final _panelOpen = RegExp(r'^\s*\{panel(?::title=([^}]*))?\}');

/// `[text|url]` Jira link (Markdown links have no pipe and never match).
final _jiraLink = RegExp(r'\[([^|\]\n]+)\|([^\]\n]+?)\]');

/// Jira `*bold*`: content must be non-space at both ends, and neither
/// star may touch another star — bullets (`* item`), arithmetic
/// (`2 * 3 * 4`) and existing `**bold**` never match.
final _jiraBold = RegExp(r'(?<!\*)\*([^*\s](?:[^*\n]*[^*\s])?)\*(?!\*)');

/// `{color:…}` opening and `{color}` closing tags.
final _colorTag = RegExp(r'\{color(?::[^}]*)?\}');

/// `{{monospace}}` span (a `{{` without a closing `}}` never matches
/// and stays untouched).
final _jiraMono = RegExp(r'\{\{([^{}\n]+)\}\}');

/// First-token language hint for a single-line pair's content — a
/// letter-leading language-ish token followed by whitespace (`2 + 2` is
/// content, not `lang=2`).
final _pairLangRest = RegExp(r'^([A-Za-z][\w#+.-]*)(?:\s+([\s\S]+))?$');

/// A Markdown ``` fence opener/closer line.
final _mdFence = RegExp(r'^\s*```');

/// Converts Jira wiki markup in a comment body to GitHub-flavored
/// Markdown (see the library doc for the construct table).
String jiraMarkupToMarkdown(String body) =>
    _jiraMarker.hasMatch(body) ? _Converter().convert(body) : body;

/// Line-scanning state machine for [jiraMarkupToMarkdown] — split per
/// concern so each step stays small: Jira code state, Markdown fence
/// state, panel state, then plain line conversion.
class _Converter {
  final _out = <String>[];
  bool _inCode = false;
  bool _inMdFence = false;
  bool _inPanel = false;

  String convert(String body) {
    for (final line in body.split('\n')) {
      _line(line);
    }
    if (_inCode) _out.add('```');
    return _out.join('\n');
  }

  void _line(String line) {
    if (_inCode) return _insideCode(line);
    if (_inMdFence) return _insideMdFence(line);
    if (_inPanel) return _insidePanel(line);
    _convertOpenLine(line);
  }

  /// Outside every context: panel/fence openers claim the line first,
  /// then a single-line `{code}…{code}` pair (it starts with `{code`
  /// too, so it must win over the block-open branch), else inline.
  void _convertOpenLine(String line) {
    if (_openPanel(line)) return;
    if (_opensMdFence(line)) return;
    if (_codePair.hasMatch(line)) return _out.add(_convertLine(line));
    if (_openFence(line)) return;
    _out.add(_convertLine(line));
  }

  /// Inside an existing Markdown fence: verbatim until the fence closes
  /// (quoted legacy markup is never rewritten).
  void _insideMdFence(String line) {
    _out.add(line);
    if (_mdFence.hasMatch(line)) _inMdFence = false;
  }

  bool _opensMdFence(String line) {
    if (!_mdFence.hasMatch(line)) return false;
    _out.add(line);
    _inMdFence = true;
    return true;
  }

  /// Inside a fenced block: only the closing `{code}` ends it; every
  /// other line passes through verbatim (no inner conversion).
  void _insideCode(String line) {
    if (line.trim() == '{code}') {
      _out.add('```');
      _inCode = false;
    } else {
      _out.add(line);
    }
  }

  /// Inside a panel: body lines become blockquotes; `{panel}` closes it.
  void _insidePanel(String line) {
    if (line.trim() == '{panel}') {
      _inPanel = false;
    } else {
      _out.add('> ${_convertLine(line)}');
    }
  }

  /// A `{panel[:title=…]}` opening line → blockquote with a bold title.
  bool _openPanel(String line) {
    final panel = _panelOpen.firstMatch(line);
    if (panel == null) return false;
    final title = panel.group(1)?.trim();
    final rest = _convertText(line.substring(panel.end).trim());
    _out.add('> ${title == null || title.isEmpty ? '' : '**$title** '}$rest'
        .trimRight());
    _inPanel = true;
    return true;
  }

  /// A block-opening `{code}` / `{code:lang}` / `{code}lang` line →
  /// fence. Content after the tag becomes the block's first line; the
  /// block stays open until its closing `{code}` (or the defensive EOF
  /// fence) — an early close would strand the following lines.
  bool _openFence(String line) {
    final open = _codeOpen.firstMatch(line);
    if (open == null) return false;
    final part = _langAndBody(
      explicit: open.group(1),
      afterTag: line.substring(open.end),
    );
    _out.add('```' + part.lang);
    if (part.body.isNotEmpty) _out.add(part.body);
    _inCode = true;
    return true;
  }
}

/// The language hint and first body line after a `{code}` opening tag.
///
/// - `{code:lang}` → the explicit hint (possibly empty — `{code:}` means
///   "no language"), everything after the tag is body.
/// - `{code}lang` / `{code}lang body` → the first token is the hint
///   (the gh-122 template form), the remainder is body. The remainder
///   may start with whitespace (`{code} dart`, padded templates) — trim
///   before matching; no token at all means "no hint".
({String lang, String body}) _langAndBody({
  required String? explicit,
  required String afterTag,
}) {
  if (explicit != null) return (lang: explicit, body: afterTag.trim());
  final m = _langRest.firstMatch(afterTag.trimLeft());
  if (m == null) return (lang: '', body: afterTag.trim());
  return (lang: m.group(1)!, body: m.group(2)?.trim() ?? '');
}

/// Converts one line outside code/panel contexts: heading prefix first,
/// then an inline `{code}` pair scan, then link/bold conversion.
String _convertLine(String line) {
  var s = line.replaceAll(_colorTag, '');
  final h = _heading.firstMatch(s);
  var prefix = '';
  if (h != null) {
    prefix = '${'#' * int.parse(h.group(1)!)} ';
    s = s.substring(h.end);
  }
  if (_codePair.hasMatch(s)) return prefix + _convertPairs(s);
  return prefix + _convertText(s);
}

/// Converts inline `{code}` pairs: a pair spanning the (non-blank) line
/// becomes a fenced block, an embedded pair a backtick span. Surrounding
/// segments still get link/bold conversion; pair content stays verbatim.
String _convertPairs(String s) {
  final buf = StringBuffer();
  var last = 0;
  for (final m in _codePair.allMatches(s)) {
    buf.write(_convertText(s.substring(last, m.start)));
    var content = m.group(2)?.trim() ?? '';
    var lang = m.group(1) ?? '';
    final wholeLine = s.substring(0, m.start).trim().isEmpty &&
        s.substring(m.end).trim().isEmpty;
    if (wholeLine && lang.isEmpty) {
      final hint = _pairLangRest.firstMatch(content);
      if (hint != null && hint.group(2) != null) {
        lang = hint.group(1)!;
        content = hint.group(2)!.trim();
      }
    }
    buf.write(wholeLine ? '```$lang\n$content\n```' : '`$content`');
    last = m.end;
  }
  buf.write(_convertText(s.substring(last)));
  return buf.toString();
}

/// Link + bold + monospace conversion for one text segment (color
/// already stripped).
String _convertText(String s) => s
    .replaceAllMapped(_jiraMono, (m) => '`${m.group(1)}`')
    .replaceAllMapped(_jiraLink, (m) => '[${m.group(1)}](${m.group(2)})')
    .replaceAllMapped(_jiraBold, (m) => '**${m.group(1)}**');
