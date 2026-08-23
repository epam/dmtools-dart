import 'package:dmtools/src/integrations/confluence/confluence_markdown.dart';
import 'package:test/test.dart';

/// Tests for the Markdown ↔ Confluence Storage Format converters.
void main() {
  _markdownToStorageTests();
  _storageToMarkdownTests();
  _roundTripTests();
  _referenceTests();
}

void _markdownToStorageTests() {
  group('markdownToConfluenceStorage', () {
    _mdToStorageInlineTests();
    _mdToStorageLinkTests();
    _mdToStorageBlockTests();
  });
}

void _mdToStorageInlineTests() {
  test('empty input produces empty storage', () {
    expect(markdownToConfluenceStorage(''), '');
    expect(markdownToConfluenceStorage('   \n  '), '');
  });

  test('headings render as h1-h6', () {
    expect(
      markdownToConfluenceStorage('# T\n## U\n### V'),
      '<h1>T</h1><h2>U</h2><h3>V</h3>',
    );
  });

  test('paragraphs escape XML and join soft breaks with spaces', () {
    expect(
      markdownToConfluenceStorage('a < b &\nc > d'),
      '<p>a &lt; b &amp; c &gt; d</p>',
    );
  });

  test('inline emphasis, code, and links render', () {
    expect(
      markdownToConfluenceStorage('**b** *i* `c` [x](https://e.com) ~~s~~'),
      '<p><strong>b</strong> <em>i</em> <code>c</code> '
      '<a href="https://e.com">x</a> <del>s</del></p>',
    );
  });

  test('bare URLs autolink', () {
    expect(
      markdownToConfluenceStorage('see https://e.com/page'),
      '<p>see <a href="https://e.com/page">https://e.com/page</a></p>',
    );
  });
}

void _mdToStorageLinkTests() {
  test('external images render as img', () {
    expect(
      markdownToConfluenceStorage('![alt](https://e.com/i.png)'),
      '<p><img src="https://e.com/i.png" alt="alt"/></p>',
    );
  });

  test('local images render as attachment references', () {
    expect(
      markdownToConfluenceStorage('![alt](images/shot.png)'),
      '<p><ac:image><ri:attachment ri:filename="shot.png"/></ac:image></p>',
    );
  });

  test('non-external links to pages render as ri:page links', () {
    expect(
      markdownToConfluenceStorage('[Home](Home Page)'),
      '<p><ac:link><ri:page ri:content-title="Home%20Page"/>'
      '<ac:link-body>Home</ac:link-body></ac:link></p>',
    );
  });

  test('attachment-extension links render as ri:attachment links', () {
    expect(
      markdownToConfluenceStorage('[r](docs/report.pdf)'),
      '<p><ac:link><ri:attachment ri:filename="report.pdf"/>'
      '<ac:link-body>r</ac:link-body></ac:link></p>',
    );
  });

  test('legacy links with spaces in the URL are encoded', () {
    expect(
      markdownToConfluenceStorage('[t](Some Page)'),
      '<p><ac:link><ri:page ri:content-title="Some%20Page"/>'
      '<ac:link-body>t</ac:link-body></ac:link></p>',
    );
  });
}

void _mdToStorageBlockTests() {
  test('unordered and ordered lists render with nesting', () {
    expect(
      markdownToConfluenceStorage('- a\n- b\n  - c'),
      '<ul><li><p>a</p></li><li><p>b</p><ul><li><p>c</p></li></ul></li></ul>',
    );
    expect(
      markdownToConfluenceStorage('1. a\n2. b'),
      '<ol><li><p>a</p></li><li><p>b</p></li></ol>',
    );
  });

  test('task lists render as ac:task entries', () {
    expect(
      markdownToConfluenceStorage('- [x] done\n- [ ] open'),
      '<ac:task-list>'
      '<ac:task><ac:task-status>complete</ac:task-status>'
      '<ac:task-body><p>done</p></ac:task-body></ac:task>'
      '<ac:task><ac:task-status>incomplete</ac:task-status>'
      '<ac:task-body><p>open</p></ac:task-body></ac:task>'
      '</ac:task-list>',
    );
  });

  test('fenced code renders as a code macro with language', () {
    expect(
      markdownToConfluenceStorage('```dart\nvoid m() {}\n```'),
      '<ac:structured-macro ac:name="code">'
      '<ac:parameter ac:name="language">dart</ac:parameter>'
      '<ac:plain-text-body><![CDATA[void m() {}]]></ac:plain-text-body>'
      '</ac:structured-macro>',
    );
  });

  test('tables render with th header cells', () {
    expect(
      markdownToConfluenceStorage('| A | B |\n|---|---|\n| 1 | 2 |'),
      '<table><tbody><tr><th>A</th><th>B</th></tr>'
      '<tr><td>1</td><td>2</td></tr></tbody></table>',
    );
  });

  test('blockquotes and horizontal rules render', () {
    expect(
      markdownToConfluenceStorage('> quoted'),
      '<blockquote><p>quoted</p></blockquote>',
    );
    expect(markdownToConfluenceStorage('---'), '<hr/>');
  });
}

void _storageToMarkdownTests() {
  group('confluenceStorageToMarkdown', () {
    _storageToMdInlineTests();
    _storageToMdConfluenceTests();
    _storageToMdBlockTests();
  });
}

void _storageToMdInlineTests() {
  test('empty input produces empty markdown', () {
    expect(confluenceStorageToMarkdown(''), '');
  });

  test('headings and paragraphs convert', () {
    expect(
      confluenceStorageToMarkdown('<h1>T</h1><p>Hello <strong>b</strong>'
          '</p>'),
      '# T\n\nHello **b**',
    );
  });

  test('inline code, links, and emphasis convert', () {
    expect(
      confluenceStorageToMarkdown(
          '<p><code>c</code> <a href="https://e.com">x</a> '
          '<em>i</em> <del>s</del></p>'),
      '`c` [x](https://e.com) *i* ~~s~~',
    );
  });

  test('unknown tags render their children', () {
    expect(confluenceStorageToMarkdown('<span>x</span>'), 'x');
  });

  test('XML entities unescape', () {
    expect(confluenceStorageToMarkdown('<p>a &lt; b &amp; c</p>'), 'a < b & c');
  });
}

void _storageToMdConfluenceTests() {
  test('ac:link page and attachment references convert', () {
    expect(
      confluenceStorageToMarkdown(
        '<p><ac:link><ri:page ri:content-title="Home"/>'
        '<ac:link-body>H</ac:link-body></ac:link></p>',
      ),
      '[H](Home)',
    );
    expect(
      confluenceStorageToMarkdown(
        '<p><ac:link><ri:attachment ri:filename="r.pdf"/>'
        '<ac:link-body>r</ac:link-body></ac:link></p>',
      ),
      '[r](r.pdf)',
    );
  });

  test('ac:image attachments and img tags convert', () {
    expect(
      confluenceStorageToMarkdown(
        '<p><ac:image><ri:attachment ri:filename="s.png"/></ac:image></p>',
      ),
      '![s.png](s.png)',
    );
    expect(
      confluenceStorageToMarkdown('<p><img src="https://e/i.png"/></p>'),
      '![](https://e/i.png)',
    );
  });

  test('code macros convert to fenced blocks with language', () {
    expect(
      confluenceStorageToMarkdown(
        '<ac:structured-macro ac:name="code">'
        '<ac:parameter ac:name="language">dart</ac:parameter>'
        '<ac:plain-text-body><![CDATA[void m()]]></ac:plain-text-body>'
        '</ac:structured-macro>',
      ),
      '```dart\nvoid m()\n```',
    );
  });

  test('task lists convert back to checkboxes', () {
    expect(
      confluenceStorageToMarkdown(
        '<ac:task-list><ac:task><ac:task-status>complete</ac:task-status>'
        '<ac:task-body><p>done</p></ac:task-body></ac:task></ac:task-list>',
      ),
      '- [x] done',
    );
  });
}

void _storageToMdBlockTests() {
  test('tables convert to GFM pipe tables', () {
    expect(
      confluenceStorageToMarkdown(
        '<table><tbody><tr><th>A</th><th>B</th></tr>'
        '<tr><td>1</td><td>2</td></tr></tbody></table>',
      ),
      '| A | B |\n| --- | --- |\n| 1 | 2 |',
    );
  });

  test('lists convert back with nesting', () {
    expect(
      confluenceStorageToMarkdown(
        '<ul><li><p>a</p></li><li><p>b</p><ul><li><p>c</p></li></ul></li>'
        '</ul>',
      ),
      '- a\n- b\n    - c',
    );
    expect(
      confluenceStorageToMarkdown('<ol><li><p>a</p></li></ol>'),
      '1. a',
    );
  });

  test('blockquotes prefix every line', () {
    expect(
      confluenceStorageToMarkdown('<blockquote><p>q1</p></blockquote>'),
      '> q1',
    );
  });
}

void _roundTripTests() {
  group('round trips', () {
    test('agent-style discovery document survives storage and back', () {
      const md = '# TICKET-1 Summary\n\n'
          'Some **context** with a [link](https://e.com).\n\n'
          '- point one\n- point two\n';
      final back = confluenceStorageToMarkdown(
        markdownToConfluenceStorage(md),
      );
      expect(back, md.trim());
    });
  });
}

void _referenceTests() {
  group('extractAttachmentReferences', () {
    test('collects local image and attachment-extension link targets', () {
      expect(
        extractAttachmentReferences(
          '![i](img/shot.png) see [r](docs/report.pdf) '
          'and [page](Other Page) and [ext](https://e.com/x.pdf)',
        ),
        {'shot.png', 'report.pdf'},
      );
    });

    test('ignores non-attachment references', () {
      expect(extractAttachmentReferences('[x](https://e.com) [a](#frag)'),
          isEmpty);
    });
  });

  group('isExternalUrl', () {
    test('http, https, mailto, ftp are external', () {
      expect(isExternalUrl('http://a'), isTrue);
      expect(isExternalUrl('HTTPS://a'), isTrue);
      expect(isExternalUrl('mailto:a@b'), isTrue);
      expect(isExternalUrl('ftp://a'), isTrue);
    });

    test('local paths and anchors are internal', () {
      expect(isExternalUrl('images/x.png'), isFalse);
      expect(isExternalUrl('#sec'), isFalse);
    });
  });
}
