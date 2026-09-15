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
///   trailing fence would swallow the rest of the comment)
/// - `h1.`–`h6.` line prefixes → `#`–`######`
/// - `[text|url]` → `[text](url)`
/// - `*bold*` → `**bold**` (existing `**bold**`, bullets and arithmetic
///   asterisks are preserved)
/// - `{panel:title=X}` … `{panel}` → blockquote
/// - `{color:…} … {color}` → tags stripped, text kept
///
/// Everything inside a code block passes through verbatim, and
/// already-Markdown text is returned unchanged.
library;

/// Opening `{code}` tag with an optional `:lang` suffix.
final _codeOpen = RegExp(r'^\{code(?::([\w#+.-]+))?\}');

/// Single-line `{code}…{code}` / `{code:lang}…{code}` pair.
final _codePair = RegExp(r'\{code(?::([\w#+.-]+))?\}([^\n]*?)\{code\}');

/// Jira heading prefix (`h1.`–`h6.`).
final _heading = RegExp(r'^\s*h([1-6])\.\s*');

/// Panel opening tag with an optional `:title=…`.
final _panelOpen = RegExp(r'^\{panel(?::title=([^}]*))?\}');

/// `[text|url]` Jira link (Markdown links have no pipe and never match).
final _jiraLink = RegExp(r'\[([^|\]\n]+)\|([^\]\n]+?)\]');

/// Jira `*bold*`: content must be non-space at both ends, and neither
/// star may touch another star — bullets (`* item`), arithmetic
/// (`2 * 3 * 4`) and existing `**bold**` never match.
final _jiraBold = RegExp(r'(?<!\*)\*([^*\s](?:[^*\n]*[^*\s])?)\*(?!\*)');

/// `{color:…}` opening and `{color}` closing tags.
final _colorTag = RegExp(r'\{color(?::[^}]*)?\}');

/// Converts Jira wiki markup in a comment body to GitHub-flavored
/// Markdown (see the library doc for the construct table).
String jiraMarkupToMarkdown(String body) {
  final out = <String>[];
  var inCode = false;
  var inPanel = false;
  for (final line in body.split('\n')) {
    if (inCode) {
      if (line.trim() == '{code}') {
        out.add('```');
        inCode = false;
      } else {
        out.add(line);
      }
      continue;
    }
    // Panel state first: the bare `{panel}` closing tag also matches the
    // open pattern (its title group is optional).
    if (inPanel) {
      if (line.trim() == '{panel}') {
        inPanel = false;
      } else {
        out.add('> ${_convertLine(line)}');
      }
      continue;
    }
    final panel = _panelOpen.firstMatch(line);
    if (panel != null) {
      final title = panel.group(1)?.trim();
      final rest = _convertText(line.substring(panel.end).trim());
      out.add('> ${title == null || title.isEmpty ? '' : '**$title** '}$rest'
          .trimRight());
      inPanel = true;
      continue;
    }
    if (line.trim() == '{panel}') continue;
    // A single-line `{code}…{code}` pair must win over the block-open
    // branch — it starts with `{code` too.
    if (_codePair.hasMatch(line)) {
      out.add(_convertLine(line));
      continue;
    }
    final open = _codeOpen.firstMatch(line);
    if (open != null) {
      final explicit = open.group(1);
      var rest = line.substring(open.end).trim();
      final lang = (explicit != null && explicit.isNotEmpty)
          ? explicit
          : _firstWord(rest);
      if (explicit == null || explicit.isEmpty) {
        rest =
            rest.length > lang.length ? rest.substring(lang.length).trim() : '';
      }
      out.add('```$lang');
      if (rest.isNotEmpty) {
        out.add(rest);
        out.add('```');
      } else {
        inCode = true;
      }
      continue;
    }
    out.add(_convertLine(line));
  }
  if (inCode) out.add('```');
  return out.join('\n');
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
    final content = m.group(2)!.trim();
    final wholeLine = s.substring(0, m.start).trim().isEmpty &&
        s.substring(m.end).trim().isEmpty;
    buf.write(
        wholeLine ? '```${m.group(1) ?? ''}\n$content\n```' : '`$content`');
    last = m.end;
  }
  buf.write(_convertText(s.substring(last)));
  return buf.toString();
}

/// Link + bold conversion for one text segment (color already stripped).
String _convertText(String s) => s
    .replaceAllMapped(_jiraLink, (m) => '[${m.group(1)}](${m.group(2)})')
    .replaceAllMapped(_jiraBold, (m) => '**${m.group(1)}**');

/// The first whitespace-delimited token of [s], or `''`.
String _firstWord(String s) => RegExp(r'^\S+').firstMatch(s)?.group(0) ?? '';
