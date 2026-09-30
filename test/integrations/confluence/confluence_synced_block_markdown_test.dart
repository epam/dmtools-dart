import 'package:dmtools/src/integrations/confluence/confluence_markdown.dart';
import 'package:test/test.dart';

/// Dart mirror of the Java `ConfluenceSyncedBlockMarkdownTest` (dm.ai #596):
/// a synced block reuses the `<ac:adf-node>` tag (same as draw.io / ecosystem
/// extensions) but carries its real content inline in `<ac:adf-content>`.
/// Synced-block content must convert inline; other adf-nodes map to the
/// `[Diagram]` placeholder.
void main() {
  group('confluenceStorageToMarkdown adf-node parity', () {
    test('synced block paragraph content converts inline', () {
      final md = confluenceStorageToMarkdown(_syncBlock(
        '<p>Mahler responds with the upload pre-signed URLs</p>',
      ));
      expect(
        md,
        contains('Mahler responds with the upload pre-signed URLs'),
      );
      expect(md, isNot(contains('Diagram')));
    });

    test('synced block code macro content is preserved', () {
      final md = confluenceStorageToMarkdown(_syncBlock(
        '<ac:structured-macro ac:name="code" ac:schema-version="1">'
        '<ac:plain-text-body><![CDATA[{"payload": {"request_id": "abc"}}]]>'
        '</ac:plain-text-body></ac:structured-macro>',
      ));
      expect(md, contains('request_id'));
      expect(md, isNot(contains('Diagram')));
    });

    test('synced block table content converts inline', () {
      final md = confluenceStorageToMarkdown(_syncBlock(
        '<table><tbody><tr><th>A</th></tr><tr><td>1</td></tr></tbody></table>',
      ));
      expect(md, contains('| A |'));
      expect(md, contains('| 1 |'));
      expect(md, isNot(contains('Diagram')));
    });

    test('synced block resource-id attributes do not leak as text', () {
      final md = confluenceStorageToMarkdown(_syncBlock(
        '<p>Visible payload</p>',
      ));
      expect(md, contains('Visible payload'));
      expect(md, isNot(contains('fedb2b81-0000')));
      expect(md, isNot(contains('08922e0e-0000')));
    });

    test('real draw.io extension becomes the [Diagram] placeholder', () {
      final md = confluenceStorageToMarkdown(
        '<ac:adf-extension>'
        '<ac:adf-node type="extension">'
        '<ac:adf-attribute key="extension-key">drawio</ac:adf-attribute>'
        '</ac:adf-node>'
        '</ac:adf-extension>',
      );
      expect(md, contains('[Diagram]'));
      expect(md, isNot(contains('drawio')));
    });
  });
}

/// A page fragment with a heading followed by a synced block carrying
/// [innerContent] (mirrors the Java test fixture).
String _syncBlock(String innerContent) {
  return '<h2>2. Get pre-signed URLs</h2>'
      '<ac:adf-extension>'
      '<ac:adf-node type="bodied-sync-block">'
      '<ac:adf-attribute key="resource-id">fedb2b81-0000</ac:adf-attribute>'
      '<ac:adf-attribute key="local-id">08922e0e-0000</ac:adf-attribute>'
      '<ac:adf-content>'
      '$innerContent'
      '</ac:adf-content>'
      '</ac:adf-node>'
      '</ac:adf-extension>';
}
