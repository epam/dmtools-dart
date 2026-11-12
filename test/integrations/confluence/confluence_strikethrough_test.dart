import 'package:dmtools/src/integrations/confluence/confluence_markdown.dart';
import 'package:test/test.dart';

/// Strikethrough parity with Java HtmlToMarkdownConverter.
void main() {
  _basicTests();
  _whitespaceTests();
  _adjacentTests();
  _nestingTests();
}

void _check(String html, String expected) =>
    expect(confluenceStorageToMarkdown('<p>$html</p>'), expected);

void _basicTests() {
  group('strike tags', () {
    test('del', () => _check('<del>x</del>', '~~x~~'));
    test('s', () => _check('<s>x</s>', '~~x~~'));
    test('strike', () => _check('<strike>x</strike>', '~~x~~'));
    test(
      'uppercase with attributes',
      () => _check('<DEL class="a">x</DEL>', '~~x~~'),
    );
    test('code stays literal', () => _check('<code>a ~ b</code>', '`a ~ b`'));
  });
}

void _whitespaceTests() {
  group('strike whitespace', () {
    test(
      'leading space moves out',
      () => _check('a<del> text</del>', 'a ~~text~~'),
    );
    test(
      'trailing space moves out',
      () => _check('<del>text </del>b', '~~text~~ b'),
    );
    test(
      'whitespace-only has no markers',
      () => _check('a<del> </del>b', 'a b'),
    );
    test('empty has no markers', () => _check('a<del></del>b', 'ab'));
  });
}

void _adjacentTests() {
  group('adjacent strikes', () {
    test(
      'separated by space',
      () => _check('<del>A</del><del> B</del>', '~~A~~ ~~B~~'),
    );
    test(
      'touching runs merge',
      () => _check('<del>A</del><del>B</del>', '~~AB~~'),
    );
  });
}

void _nestingTests() {
  group('strike nesting', () {
    test(
      'strong around del',
      () => _check(
        '<strong><del>Title</del></strong><del> text</del>',
        '**~~Title~~** ~~text~~',
      ),
    );
    test(
      'strong inside del',
      () => _check(
        '<del><strong>Title</strong> text</del>',
        '~~**Title** text~~',
      ),
    );
  });
}
