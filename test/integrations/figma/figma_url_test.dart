/// Tests for the Java-parity Figma URL helpers (`figma_url.dart`).
library;

import 'package:dmtools/src/integrations/figma/figma_url.dart';
import 'package:test/test.dart';

void main() {
  group('figmaParseFileId', () {
    test('extracts the key from a design URL', () {
      expect(
        figmaParseFileId(
            'https://www.figma.com/file/abc123/Design?node-id=1%3A2'),
        'abc123',
      );
    });

    test('extracts the key without query params', () {
      expect(figmaParseFileId('https://www.figma.com/file/KEY9/x'), 'KEY9');
    });

    test('throws StateError for a URL without a third segment', () {
      expect(
        () => figmaParseFileId('https://www.figma.com/file'),
        throwsStateError,
      );
    });
  });

  group('figmaExtractQueryParam', () {
    test('returns the node-id value', () {
      expect(
        figmaExtractQueryParam(
          'https://www.figma.com/file/abc123/Design?node-id=1-2',
          'node-id',
        ),
        '1-2',
      );
    });

    test('finds the parameter among several', () {
      expect(
        figmaExtractQueryParam(
            'https://x.test/a?fuid=9&node-id=3-4', 'node-id'),
        '3-4',
      );
    });

    test('throws StateError when the parameter is absent', () {
      expect(
        () => figmaExtractQueryParam('https://x.test/a?other=1', 'node-id'),
        throwsStateError,
      );
    });
  });

  group('figmaExtractTeamId', () {
    test('accepts a raw numeric ID', () {
      expect(figmaExtractTeamId('1633438210497791577'), '1633438210497791577');
    });

    test('extracts from a team files-listing URL', () {
      expect(
        figmaExtractTeamId(
          'https://www.figma.com/files/1008118788610687562/team/1633438210497791577?fuid=1',
        ),
        '1633438210497791577',
      );
    });

    test('trims surrounding whitespace', () {
      expect(figmaExtractTeamId('  42  '), '42');
    });

    test('throws StateError for an unusable value', () {
      expect(() => figmaExtractTeamId('nope'), throwsStateError);
      expect(() => figmaExtractTeamId(''), throwsStateError);
    });
  });

  group('figmaExtractProjectId', () {
    test('accepts a raw numeric ID', () {
      expect(figmaExtractProjectId('123456789'), '123456789');
    });

    test('extracts from a project URL', () {
      expect(
        figmaExtractProjectId('https://www.figma.com/files/project/123456789'),
        '123456789',
      );
    });

    test('throws StateError for an unusable value', () {
      expect(() => figmaExtractProjectId('abc'), throwsStateError);
    });
  });

  group('figmaColonNodeId', () {
    test('converts dashes to colons', () {
      expect(figmaColonNodeId('26032-397193'), '26032:397193');
    });

    test('leaves colon IDs untouched', () {
      expect(figmaColonNodeId('1:2'), '1:2');
    });
  });

  group('figmaCleanHref', () {
    test('unescapes ampersands', () {
      expect(figmaCleanHref('a?x=1&amp;y=2'), 'a?x=1&y=2');
    });
  });
}
