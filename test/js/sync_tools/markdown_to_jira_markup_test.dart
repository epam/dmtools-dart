/// Unit tests for `markdownToJiraMarkup` (gh-191, P6-JSY-09) — the Dart port
/// of the Java `MarkdownToJiraConverter.convertToJiraMarkdown` that
/// `JiraClient.postComment` runs on Markdown comment bodies.
///
/// The Markdown-path cases are ported 1:1 from the Java
/// `MarkdownToJiraConverterTest`; the HTML/mixed cases cover every block
/// construct the HTML walker handles (headings, paragraphs, lists, tables,
/// code, links, images, entities).
library;

import 'package:dmtools/src/js/sync_tools/markdown_to_jira_markup.dart';
import 'package:test/test.dart';

void main() {
  edgeCaseTests();
  markdownBranchTests();
  htmlBranchTests();
  mixedBranchTests();
  preserverTests();
}

void edgeCaseTests() {
  group('markdownToJiraMarkup: edge cases (Java testEdgeCases)', () {
    test('empty input yields empty string', () {
      expect(markdownToJiraMarkup(''), '');
    });

    test('whitespace-only input yields empty string', () {
      expect(markdownToJiraMarkup('  \n  \t  '), '');
    });

    test('pure HTML entities are decoded', () {
      expect(markdownToJiraMarkup('&lt; &gt; &amp; &quot;'), '< > & "');
    });
  });
}

void markdownBranchTests() {
  group('markdownToJiraMarkup: markdown branch', () {
    test('markdown input (Java testMarkdownInput)', () {
      const markdown = 'This is **bold** and _italic_\n\n'
          '```java\npublic class Test {}\n```';
      expect(
        markdownToJiraMarkup(markdown),
        'This is *bold* and _italic_\n\n{code:java}public class Test {}{code}',
      );
    });

    test('complex markdown input (Java testComplexMarkdownInput)', () {
      const markdown = '# Title\n\n'
          '**Bold text** and _italic text_\n\n'
          '```java\npublic class Test {}\n```\n\n'
          '* Item 1\n* Item 2\n\n'
          '[Link](http://example.com)\n\n'
          '`inline code`';
      expect(
        markdownToJiraMarkup(markdown),
        'h1. Title\n\n'
        '*Bold text* and _italic text_\n\n'
        '{code:java}public class Test {}{code}\n\n'
        '* Item 1\n* Item 2\n\n'
        '[Link|http://example.com]\n\n'
        '{{inline code}}',
      );
    });

    test('complex markdown input 2 (Java testComplexMarkdownInput2)', () {
      const markdown = '1. **Step one**\n'
          '2. Do the thing\n'
          '\n'
          '```dart\nfinal x = 1;\n```\n'
          '\n'
          'See [the docs](https://example.com/docs) for `details`.';
      expect(
        markdownToJiraMarkup(markdown),
        '*Step one*\n2. Do the thing\n\n'
        '{code:dart}final x = 1;{code}\n\n'
        'See [the docs|https://example.com/docs] for {{details}}.',
      );
    });

    test('code blocks conversion (Java testCodeBlocksConversion)', () {
      const input = "Here's how to implement a feature:\n"
          '\n'
          '1. Update `src/auth.ts`:\n'
          '\n'
          '<code class="typescript">\n'
          "import { auth } from './auth';\n"
          '\n'
          'export const useAuth = () => {\n'
          '  return auth;\n'
          '};\n'
          '</code>\n';
      expect(
        markdownToJiraMarkup(input),
        "Here's how to implement a feature:\n"
        '\n'
        '1. Update {{src/auth.ts}}:\n'
        '\n'
        '{code:typescript}import { auth } from \'./auth\';\n'
        'export const useAuth = () => {\n'
        '  return auth;\n'
        '};{code}',
      );
    });

    test('multi-item list stays a list (2+ items)', () {
      expect(
        markdownToJiraMarkup('* First\n* Second\n* Third'),
        '* First\n* Second\n* Third',
      );
    });
  });
}

void htmlBranchTests() {
  group('markdownToJiraMarkup: HTML branch', () {
    test('html input (Java testHtmlInput)', () {
      const html = '<p>This is <strong>bold</strong> and <em>italic</em></p>'
          '<pre><code class="java">public class Test {}</code></pre>';
      expect(
        markdownToJiraMarkup(html),
        'This is *bold* and _italic_\n\n{code:java}public class Test {}{code}',
      );
    });

    test('complex html input (Java testComplexHtmlInput)', () {
      const input = '<h1>Title</h1><p><strong>Bold text</strong> and '
          '<em>italic text</em></p>'
          '<pre><code class="java">public class Test {}</code></pre>'
          '<ul><li>Item 1</li><li>Item 2</li></ul>'
          '<a href="http://example.com">Link</a>'
          '<code>inline code</code>';
      expect(
        markdownToJiraMarkup(input),
        'h1. Title\n\n'
        '*Bold text* and _italic text_\n\n'
        '{code:java}public class Test {}{code}\n\n'
        '* Item 1\n* Item 2\n\n'
        '[Link|http://example.com]\n\n'
        '{{inline code}}',
      );
    });

    test('nested unordered list', () {
      const html = '<ul><li>Parent<ul><li>Child</li></ul></li></ul>';
      expect(markdownToJiraMarkup(html), '* Parent\n* Child');
    });

    test('ordered list with strong+ul pair', () {
      const html = '<ol><li><strong>Given</strong><ul><li>a page</li></ul>'
          '</li><li>plain item</li></ol>';
      expect(markdownToJiraMarkup(html), '# *Given*\n* a page\n# plain item');
    });

    test('table with header, line break, and emphasis', () {
      const html = '<table><tr><th>Name</th><th>Value</th></tr>'
          '<tr><td><strong>event.name</strong></td>'
          '<td>trackEvent("x")<br>second line</td></tr></table>';
      expect(
        markdownToJiraMarkup(html),
        '||Name||Value||\n'
        '|*event.name*|trackEvent("x")\n'
        '\\\\second line|',
      );
    });

    test('multi-line code element becomes a block', () {
      const html = '<p>before</p><code class="kotlin">\nval x = 1\n'
          'val y = 2\n</code>';
      expect(
        markdownToJiraMarkup(html),
        'before\n\n{code:kotlin}val x = 1\nval y = 2{code}',
      );
    });

    test('greeting line breaks inside a paragraph', () {
      const html = '<p><strong>Given</strong> a page<br>'
          '<strong>When</strong> the user clicks</p>';
      expect(
        markdownToJiraMarkup(html),
        '*Given* a page\n*When* the user clicks',
      );
    });

    test('entities inside html are decoded', () {
      expect(
        markdownToJiraMarkup('<p>fish &amp; chips &lt;3</p>'),
        'fish & chips <3',
      );
    });

    test('markdown image syntax converts', () {
      expect(
        markdownToJiraMarkup('![Screenshot|width=300](img.png)'),
        '!Screenshot|width=300!',
      );
    });
  });
}

void mixedBranchTests() {
  group('markdownToJiraMarkup: mixed branch', () {
    test('mixed input (Java testMixedInput)', () {
      const input = '# Heading\n\n<p>This is <strong>bold</strong></p>'
          '\n\n* List item\n\n```java\ncode\n```';
      expect(
        markdownToJiraMarkup(input),
        'h1. Heading\n\n'
        'This is *bold*\n\n'
        '* List item\n\n'
        '{code:java}code{code}',
      );
    });

    test('html chunk without markdown markers routes to the html branch', () {
      const input = 'plain paragraph\n\n<p><em>emph</em></p>';
      expect(markdownToJiraMarkup(input), 'plain paragraph\n\n_emph_');
    });
  });
}

void preserverTests() {
  group('HtmlCodeBlockPreserver', () {
    test('placeholder survives a preserve/restore round trip', () {
      final preserver = HtmlCodeBlockPreserver();
      final preserved = preserver.preserveCodeBlocks(
          '<p>a <code class="java">x = 1;</code> b</p>');
      expect(preserved, contains(codeBlockPlaceholder));
      final restored = preserver.restoreCodeBlocks(preserved);
      expect(restored, '<p>a {code:java}x = 1;{code} b</p>');
    });

    test('inline code without class becomes {{monospace}}', () {
      final preserver = HtmlCodeBlockPreserver();
      final preserved = preserver.preserveCodeBlocks('<p>a <code>x</code> b</p>');
      expect(preserver.restoreCodeBlocks(preserved), '<p>a {{x}} b</p>');
    });

    test('properties language maps to bash', () {
      final preserver = HtmlCodeBlockPreserver();
      final preserved = preserver.preserveCodeBlocks(
          '<code class="properties">a=b\nc=d</code>');
      expect(preserver.restoreCodeBlocks(preserved),
          '{code:bash}a=b\nc=d{code}');
    });

    test('decodeHtmlEntities normalizes newlines and decodes basics', () {
      expect(decodeHtmlEntities('&lt;x&gt;&amp;\r\nnext'), '<x>&\nnext');
    });
  });
}
