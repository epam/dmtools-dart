/// Unit tests for `jiraMarkupToMarkdown` (gh-125 rework) — the converter
/// that makes hard-coded Jira-wiki comment bodies (agents' JS post-action
/// templates) readable when `jira_post_comment` routes to GitHub Issues.
///
/// Every construct from the owner's refined scope is covered: `{code}`
/// blocks (all three tag spellings), `h1.`–`h6.` headings, `[text|url]`
/// links, `*bold*`, `{panel:title=X}`, `{color}` — plus the critical
/// non-goals: content inside code blocks and already-Markdown text must
/// pass through untouched.
library;

import 'package:dmtools/src/js/sync_tools/jira_markup.dart';
import 'package:test/test.dart';

void main() {
  codeBlockTests();
  codeBlockBoundaryTests();
  tagWhitespaceTests();
  codePairLangTests();
  mdFenceTests();
  headingTests();
  linkTests();
  boldTests();
  panelTests();
  colorTests();
  monospaceTests();
  passthroughTests();
  gh122EvidenceTests();
}

void codeBlockTests() {
  group('jiraMarkupToMarkdown: code blocks', () {
    test('{code}lang … {code} (the gh-122 evidence form)', () {
      expect(
        jiraMarkupToMarkdown('{code}dart\nfinal r = P();\n{code}'),
        '```dart\nfinal r = P();\n```',
      );
    });

    test('{code:lang} … {code} (canonical Jira spelling)', () {
      expect(
        jiraMarkupToMarkdown('{code:json}\n{"a": 1}\n{code}'),
        '```json\n{"a": 1}\n```',
      );
    });

    test('plain {code} … {code} without a language', () {
      expect(jiraMarkupToMarkdown('{code}\nx=1;\n{code}'), '```\nx=1;\n```');
    });

    test('single-line pair spanning the whole line becomes a fenced block', () {
      expect(
        jiraMarkupToMarkdown('{code:json} {"a": 1} {code}'),
        '```json\n{"a": 1}\n```',
      );
    });

    test('a pair embedded after text becomes an inline code span', () {
      // A mid-line fence would not open a GFM code block — the safe
      // conversion for template lines like `*Branch:* {code}ai/gh-125{code}`
      // is a backtick span.
      expect(
        jiraMarkupToMarkdown('*Branch:* {code}ai/gh-125{code}'),
        '**Branch:** `ai/gh-125`',
      );
    });

    test('code content passes through verbatim (no inner conversion)', () {
      expect(
        jiraMarkupToMarkdown('{code}\nh3. not a heading\n*not bold*\n{code}'),
        '```\nh3. not a heading\n*not bold*\n```',
      );
    });

    test('an unclosed code block gets a defensive fence', () {
      expect(jiraMarkupToMarkdown('{code}dart\nfinal r = P();'),
          '```dart\nfinal r = P();\n```');
    });

    test('multiple code blocks in one comment all convert', () {
      expect(
        jiraMarkupToMarkdown(
            '{code}dart\na();\n{code}\ntext\n{code:bash}\nls\n{code}'),
        '```dart\na();\n```\ntext\n```bash\nls\n```',
      );
    });
  });
}

/// Tag-shape boundaries: where the block starts/ends when content shares
/// the opening line, when the closing tag is missing, and degenerate
/// language hints.
/// `{code}` tags followed by whitespace — the PR-review BLOCKING crash
/// (null-assert in `_langAndBody`): every shape here must convert without
/// throwing and keep the language hint when one is present.
void tagWhitespaceTests() {
  group('jiraMarkupToMarkdown: {code} tags followed by whitespace', () {
    test('space before the language still yields the language hint', () {
      expect(
        jiraMarkupToMarkdown('{code} dart\nx();\n{code}'),
        '```dart\nx();\n```',
      );
    });

    test('bare tag with trailing whitespace converts to a plain fence', () {
      expect(jiraMarkupToMarkdown('{code} \nx();\n{code}'),
          '```\nx();\n```');
    });

    test('bare tag with a trailing tab does not crash', () {
      expect(jiraMarkupToMarkdown('{code}\t'), '```\n```');
    });

    test('leading-space body follows the first-token hint semantics', () {
      // Per the review's prescribed fix: the remainder is trimmed left,
      // so the first token becomes the hint and the rest the body.
      expect(
        jiraMarkupToMarkdown('{code}  indented first line'),
        '```indented\nfirst line\n```',
      );
    });
  });
}

/// Single-line `{code}…{code}` pairs with the bare-tag spelling: the
/// first content token is the language hint (same semantics as the
/// multi-line block path) so `{code}dart main();{code}` highlights.
void codePairLangTests() {
  group('jiraMarkupToMarkdown: single-line pair language hint', () {
    test('bare-tag pair derives the hint from the first content token', () {
      expect(jiraMarkupToMarkdown('{code}dart main();{code}'),
          '```dart\nmain();\n```');
    });

    test('content without a letter-leading token gets no hint', () {
      // `2` is arithmetic, not a language — the hint heuristic requires a
      // letter-leading token.
      expect(jiraMarkupToMarkdown('{code}2 + 2{code}'), '```\n2 + 2\n```');
    });

    test('embedded bare-tag pairs stay verbatim inline spans', () {
      expect(jiraMarkupToMarkdown('x {code}dart y{code} z'),
          'x `dart y` z');
    });
  });
}

/// Existing Markdown ``` fences: lines inside a fenced block pass through
/// verbatim (the PR-review IMPORTANT finding — fenced `h3.` / links /
/// italics were being rewritten), while Jira constructs outside still
/// convert.
void mdFenceTests() {
  group('jiraMarkupToMarkdown: Markdown fence passthrough', () {
    test('Jira-ish tokens inside a ``` fence stay untouched', () {
      const body = '## Fix\n'
          '```text\n'
          'h3. not a heading\n'
          '[link|url]\n'
          '*x*\n'
          '```\n';
      expect(jiraMarkupToMarkdown(body), body);
    });

    test('Jira constructs outside the fence still convert', () {
      expect(
        jiraMarkupToMarkdown('h3. Real\n```text\nh3. fake\n```'),
        '### Real\n```text\nh3. fake\n```',
      );
    });

    test('an unclosed Markdown fence leaves the rest of the body alone', () {
      expect(
        jiraMarkupToMarkdown('```text\nh3. inside\nh2. also inside'),
        '```text\nh3. inside\nh2. also inside',
      );
    });
  });
}

void codeBlockBoundaryTests() {
  group('jiraMarkupToMarkdown: code block boundaries', () {
    test('lang-first block closes at its closing tag, not mid-block', () {
      // `{code}lang content` with the closing `{code}` on a later line is
      // ONE block — an early fence close would strand the following lines
      // outside it.
      expect(
        jiraMarkupToMarkdown('{code}json {"a": 1}\nmore\n{code}'),
        '```json\n{"a": 1}\nmore\n```',
      );
    });

    test('explicit-lang tag with same-line content joins the block', () {
      expect(
        jiraMarkupToMarkdown('{code:json} {"a": 1}\n{code}'),
        '```json\n{"a": 1}\n```',
      );
    });

    test('unclosed lang-first block gets a defensive fence', () {
      expect(
        jiraMarkupToMarkdown('{code}dart final x = 1;'),
        '```dart\nfinal x = 1;\n```',
      );
    });

    test('{code:} empty explicit hint means no language', () {
      expect(
        jiraMarkupToMarkdown('{code:}\nx = 1;\n{code}'),
        '```\nx = 1;\n```',
      );
    });
  });
}

void headingTests() {
  group('jiraMarkupToMarkdown: headings', () {
    for (var level = 1; level <= 6; level++) {
      test('h$level. converts to ${'#' * level}', () {
        expect(jiraMarkupToMarkdown('h$level. Title'), '${'#' * level} Title');
      });
    }

    test('heading text is still link/bold converted', () {
      expect(jiraMarkupToMarkdown('h3. *Fix* the [thing|https://x.y]'),
          '### **Fix** the [thing](https://x.y)');
    });

    test('h7. is not a Jira heading and stays untouched', () {
      expect(jiraMarkupToMarkdown('h7. nope'), 'h7. nope');
    });
  });
}

void linkTests() {
  group('jiraMarkupToMarkdown: links', () {
    test('[text|url] converts to [text](url)', () {
      expect(
        jiraMarkupToMarkdown('See [PR #124|https://github.com/o/r/pull/124]'),
        'See [PR #124](https://github.com/o/r/pull/124)',
      );
    });

    test('existing Markdown links stay untouched', () {
      expect(
          jiraMarkupToMarkdown('See [PR #124](https://x.y)'), //
          'See [PR #124](https://x.y)');
    });
  });
}

void boldTests() {
  group('jiraMarkupToMarkdown: bold', () {
    test('*text* converts when the body carries a Jira marker', () {
      // Bold conversion only applies to Jira-sourced bodies — gated on a
      // marker (`h3.` here); see the italic-passthrough pin below.
      expect(jiraMarkupToMarkdown('h3. *Development Completed*'),
          '### **Development Completed**');
    });

    test('Markdown italics are preserved (no Jira marker, no conversion)', () {
      // `*text*` is valid GFM emphasis — a marker-free body passes through
      // byte-for-byte (PR-review suggestion: pin the italic guarantee).
      expect(jiraMarkupToMarkdown('normal *italic* stays'),
          'normal *italic* stays');
    });

    test('existing **bold** is not doubled', () {
      expect(jiraMarkupToMarkdown('**already bold**'), '**already bold**');
    });

    test('bullet lines are not mistaken for bold', () {
      expect(jiraMarkupToMarkdown('* item one\n* item two'),
          '* item one\n* item two');
    });

    test('arithmetic asterisks stay untouched', () {
      expect(jiraMarkupToMarkdown('2 * 3 * 4'), '2 * 3 * 4');
    });
  });
}

void panelTests() {
  group('jiraMarkupToMarkdown: panel', () {
    test('{panel:title=X} … {panel} becomes a blockquote', () {
      expect(
        jiraMarkupToMarkdown('{panel:title=Scope}\nbody line\n{panel}'),
        '> **Scope**\n> body line',
      );
    });

    test('a title-less panel becomes a plain blockquote', () {
      expect(jiraMarkupToMarkdown('{panel}\nnote\n{panel}'), '>\n> note');
    });

    test('an indented opener behaves like an unindented one', () {
      expect(
        jiraMarkupToMarkdown('  {panel:title=Scope}\nbody line\n  {panel}'),
        '> **Scope**\n> body line',
      );
    });

    test('an indented bare {panel} opens a title-less panel', () {
      expect(
        jiraMarkupToMarkdown('  {panel}\nnote\n{panel}'),
        '>\n> note',
      );
    });
  });
}

void monospaceTests() {
  group('jiraMarkupToMarkdown: {{monospace}}', () {
    test('{{text}} becomes an inline code span', () {
      expect(jiraMarkupToMarkdown('run {{ci build}} now'), 'run `ci build` now');
    });

    test('every {{...}} span in the body converts', () {
      expect(
        jiraMarkupToMarkdown('{{a}} and {{b}}'),
        '`a` and `b`',
      );
    });

    test('an unclosed {{ stays untouched', () {
      expect(jiraMarkupToMarkdown('template {{var goes on'), 'template {{var goes on');
    });

    test('mono content is not link/bold converted', () {
      expect(jiraMarkupToMarkdown('{{a*b}}'), '`a*b`');
    });
  });
}

void colorTests() {
  group('jiraMarkupToMarkdown: color', () {
    test('{color:…} … {color} tags are stripped, text kept', () {
      expect(jiraMarkupToMarkdown('{color:red}hot{color}'), 'hot');
    });
  });
}

void passthroughTests() {
  group('jiraMarkupToMarkdown: passthrough', () {
    test('already-Markdown comments are unchanged', () {
      const md = '## Fix\n\n- one\n- two\n\n```dart\nfinal r = P();\n```\n\n'
          '[text](https://x.y) and **bold** — done.';
      expect(jiraMarkupToMarkdown(md), md);
    });

    test('plain prose is unchanged', () {
      expect(jiraMarkupToMarkdown('Just a sentence.'), 'Just a sentence.');
    });
  });
}

void gh122EvidenceTests() {
  group('jiraMarkupToMarkdown: gh-122 evidence end-to-end', () {
    test('the reported unreadable comment becomes readable Markdown', () {
      const evidence = 'h3. *Development Completed*\n\n'
          '*Branch:* {code}ai/gh-125{code}\n'
          '*Pull Request:* '
          '[PR #127|https://github.com/epam/dmtools-dart/pull/127]\n\n'
          '{code}dart\nfinal reader = PropertyReader();\n{code}\n'
          'h3. Fix\n';
      expect(
        jiraMarkupToMarkdown(evidence),
        '### **Development Completed**\n'
        '\n'
        '**Branch:** `ai/gh-125`\n'
        '**Pull Request:** '
        '[PR #127](https://github.com/epam/dmtools-dart/pull/127)\n'
        '\n'
        '```dart\nfinal reader = PropertyReader();\n```\n'
        '### Fix\n',
      );
    });
  });
}
