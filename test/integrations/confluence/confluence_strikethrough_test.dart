import 'package:dmtools/src/integrations/confluence/confluence_markdown.dart';
import 'package:test/test.dart';

/// Strikethrough parity with Java HtmlToMarkdownConverter.
void main() {
  _basicTests();
  _whitespaceTests();
  _adjacentTests();
  _nestingTests();
}

String _md(String html) => confluenceStorageToMarkdown('<p>$html</p>');

void _basicTests() {
  group('strike tags', () {
    test('del', () => expect(_md('<del>x</del>'), '~~x~~'));
    test('s', () => expect(_md('<s>x</s>'), '~~x~~'));
    test('strike', () => expect(_md('<strike>x</strike>'), '~~x~~'));
    test(
      'uppercase with attributes',
      () => expect(_md('<DEL class="a">x</DEL>'), '~~x~~'),
    );
    test('code stays literal',
        () => expect(_md('<code>a ~ b</code>'), '`a ~ b`'));
  });
}

void _whitespaceTests() {
  group('strike whitespace', () {
    test(
      'leading space moves out',
      () => expect(_md('a<del> text</del>'), 'a ~~text~~'),
    );
    test(
      'trailing space moves out',
      () => expect(_md('<del>text </del>b'), '~~text~~ b'),
    );
    test(
      'whitespace-only has no markers',
      () => expect(_md('a<del> </del>b'), 'a b'),
    );
    test('empty has no markers', () => expect(_md('a<del></del>b'), 'ab'));
  });
}

void _adjacentTests() {
  group('adjacent strikes', () {
    test(
      'separated by space',
      () => expect(_md('<del>A</del><del> B</del>'), '~~A~~ ~~B~~'),
    );
    test(
      'touching runs merge',
      () => expect(_md('<del>A</del><del>B</del>'), '~~AB~~'),
    );
  });
}

void _nestingTests() {
  group('strike nesting', () {
    test(
      'strong around del',
      () => expect(
        _md('<strong><del>Title</del></strong><del> text</del>'),
        '**~~Title~~** ~~text~~',
      ),
    );
    test(
      'strong inside del',
      () => expect(
        _md('<del><strong>Title</strong> text</del>'),
        '~~**Title** text~~',
      ),
    );
  });
}
