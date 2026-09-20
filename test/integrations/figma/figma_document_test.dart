/// Tests for the Java-parity Figma document shaping (`figma_document.dart`):
/// `findAllComponents` visual-element extraction, layer summaries, text
/// extraction, and the styles/icons result envelopes.
library;

import 'package:dmtools/src/integrations/figma/figma_document.dart';
import 'package:test/test.dart';

void main() {
  group('figmaFindAllComponents (document response)', () {
    test('collects exportable elements recursively with metadata', () {
      final response = {
        'document': {
          'id': '0:0',
          'type': 'DOCUMENT',
          'children': [
            {
              'id': '1:1',
              'name': 'Frame',
              'type': 'FRAME',
              'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 100, 'height': 50},
              'children': [
                {
                  'id': '2:2',
                  'name': 'close icon',
                  'type': 'VECTOR',
                  'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 24, 'height': 24},
                },
              ],
            },
          ],
        },
      };
      final icons = figmaFindAllComponents(response);
      expect(icons, hasLength(2));
      final frame = icons[0];
      expect(frame['id'], '1:1');
      expect(frame['type'], 'FRAME');
      expect(frame['width'], 100);
      expect(frame['height'], 50);
      expect(frame['supportedFormats'], ['png', 'jpg', 'pdf']);
      expect(frame['isVectorBased'], isFalse);
      expect(frame['category'], 'graphic');
      final vector = icons[1];
      expect(vector['category'], 'icon');
      expect(vector['supportedFormats'], ['png', 'jpg', 'svg']);
      expect(vector['isVectorBased'], isTrue);
    });

    test('skips non-exportable types and zero-size nodes', () {
      final response = {
        'document': {
          'id': '0:0',
          'type': 'DOCUMENT',
          'children': [
            {'id': '1:1', 'name': 'slice', 'type': 'SLICE', 'absoluteBoundingBox': {'width': 10, 'height': 10}},
            {'id': '1:2', 'name': 'empty', 'type': 'RECTANGLE', 'absoluteBoundingBox': {'width': 0, 'height': 10}},
            {'id': '1:3', 'name': 'hidden', 'type': 'RECTANGLE', 'visible': false, 'absoluteBoundingBox': {'width': 10, 'height': 10}},
            {'id': '1:4', 'name': 'faint', 'type': 'RECTANGLE', 'opacity': 0.005, 'absoluteBoundingBox': {'width': 10, 'height': 10}},
            {'id': '1:5', 'name': 'too complex', 'type': 'VECTOR', 'id_conflict': 'x', 'absoluteBoundingBox': {'width': 10, 'height': 10}},
          ],
        },
      };
      // Give the "too complex" node a 4-part semicolon ID via children path.
      final icons = figmaFindAllComponents(response);
      expect(icons, isEmpty);
    });

    test('filters 4+ part semicolon IDs but keeps 2-part ones', () {
      Map<String, Object?> node(String id) => {
            'id': id,
            'name': 'n',
            'type': 'VECTOR',
            'absoluteBoundingBox': {'width': 10, 'height': 10},
          };
      final response = {
        'document': {
          'id': '0:0',
          'type': 'DOCUMENT',
          'children': [
            node('I1:1;2:2'),
            node('I1:1;2:2;3:3;4:4'),
          ],
        },
      };
      final icons = figmaFindAllComponents(response);
      expect(icons.map((i) => i['id']), ['I1:1;2:2']);
    });

    test('skips large FRAME and GROUP containers', () {
      final response = {
        'document': {
          'id': '0:0',
          'type': 'DOCUMENT',
          'children': [
            {'id': '1:1', 'name': 'screen', 'type': 'FRAME', 'absoluteBoundingBox': {'width': 400, 'height': 300}},
            {'id': '1:2', 'name': 'group', 'type': 'GROUP', 'absoluteBoundingBox': {'width': 300, 'height': 300}},
            {'id': '1:3', 'name': 'big vector', 'type': 'VECTOR', 'absoluteBoundingBox': {'width': 300, 'height': 300}},
          ],
        },
      };
      final icons = figmaFindAllComponents(response);
      // Only the oversized vector survives: FRAME/GROUP >200x200 are
      // containers, vectors have no size cap.
      expect(icons.single['id'], '1:3');
      expect(icons.single['category'], 'illustration');
    });

    test('categorizes by name patterns and type', () {
      Map<String, Object?> node(String name, String type, double w, double h) => {
            'id': '9:9',
            'name': name,
            'type': type,
            'absoluteBoundingBox': {'width': w, 'height': h},
          };
      final response = {
        'document': {
          'id': '0:0',
          'type': 'DOCUMENT',
          'children': [
            node('Chevron down', 'FRAME', 20, 20),
            node('hero illustration', 'RECTANGLE', 20, 20),
            node('label', 'TEXT', 100, 20),
            node('plain', 'RECTANGLE', 20, 20),
            node('tab services', 'RECTANGLE', 20, 20),
          ],
        },
      };
      final icons = figmaFindAllComponents(response);
      expect(
        icons.map((i) => i['category']).toList(),
        ['icon', 'illustration', 'text', 'graphic', 'illustration'],
      );
    });
  });

  group('figmaFindAllComponents (nodes response)', () {
    test('walks each node document', () {
      final response = {
        'nodes': {
          '1:1': {
            'document': {
              'id': '1:1',
              'type': 'FRAME',
              'absoluteBoundingBox': {'width': 10, 'height': 10},
            },
          },
          '2:2': {
            'document': {
              'id': '2:2',
              'type': 'VECTOR',
              'absoluteBoundingBox': {'width': 24, 'height': 24},
            },
          },
        },
      };
      final icons = figmaFindAllComponents(response);
      expect(icons.map((i) => i['id']).toList(), ['1:1', '2:2']);
    });

    test('returns empty for a response with neither nodes nor document', () {
      expect(figmaFindAllComponents({'name': 'x'}), isEmpty);
    });
  });

  group('figmaLayerSummaries', () {
    final document = {
      'children': [
        {
          'id': '1:1',
          'name': 'Header',
          'type': 'FRAME',
          'visible': false,
          'absoluteBoundingBox': {'x': 1, 'y': 2, 'width': 100, 'height': 50},
        },
        {'id': '1:2', 'name': 'no-box', 'type': 'TEXT'},
      ],
    };

    test('maps children to layer info with bounding boxes', () {
      final layers = figmaLayerSummaries(document);
      expect(layers, hasLength(2));
      expect(layers[0], {
        'id': '1:1',
        'name': 'Header',
        'type': 'FRAME',
        'width': 100,
        'height': 50,
        'x': 1,
        'y': 2,
        'visible': false,
      });
    });

    test('omits bounds keys when no bounding box and defaults visible', () {
      final layers = figmaLayerSummaries(document);
      expect(layers[1], {
        'id': '1:2',
        'name': 'no-box',
        'type': 'TEXT',
        'visible': true,
      });
    });

    test('returns empty list when there are no children', () {
      expect(figmaLayerSummaries(const {}), isEmpty);
    });
  });

  group('figmaIconsResult', () {
    test('wraps icons with fileId and total', () {
      final icons = [
        {'id': '1:1', 'name': 'a', 'type': 'VECTOR'},
      ];
      final result = figmaIconsResult('fileKey', icons);
      expect(result['fileId'], 'fileKey');
      expect(result['totalIcons'], 1);
      expect(result['icons'], icons);
    });
  });

  group('figmaTextContent', () {
    final response = {
      'nodes': {
        '10:1': {
          'document': {
            'id': '10:1',
            'type': 'TEXT',
            'characters': 'Hello',
            'style': {
              'fontFamily': 'Inter',
              'fontSize': 16.0,
              'fontWeight': 700,
              'lineHeightPx': 20.0,
              'letterSpacing': 0.5,
              'textAlignHorizontal': 'CENTER',
            },
            'characterStyleOverrides': [0, 1],
            'styleOverrideTable': {'1': {'fontSize': 12}},
          },
        },
        '10:2': {
          'document': {'id': '10:2', 'type': 'RECTANGLE'},
        },
        '10:3': {
          'document': {
            'id': '10:3',
            'type': 'TEXT',
            'characters': 'No style',
          },
        },
      },
    };

    test('extracts styled text entries keyed by requested id', () {
      final result = figmaTextContent(response, ['10:1', '10:2', '10:3']);
      final textNodes = result['textNodes'] as Map<String, dynamic>;
      expect(textNodes.keys, ['10:1', '10:3']);
      final entry = textNodes['10:1'] as Map<String, dynamic>;
      expect(entry['text'], 'Hello');
      expect(entry['fontFamily'], 'Inter');
      expect(entry['fontSize'], 16.0);
      expect(entry['fontWeight'], 700);
      expect(entry['lineHeight'], 20.0);
      expect(entry['letterSpacing'], 0.5);
      expect(entry['textAlign'], 'CENTER');
      expect(entry['characterStyleOverrides'], [0, 1]);
      expect(entry['styleOverrideTable'], {'1': {'fontSize': 12}});
    });

    test('text without style carries only the text key', () {
      final result = figmaTextContent(response, ['10:3']);
      final entry = (result['textNodes'] as Map)['10:3'] as Map;
      expect(entry, {'text': 'No style'});
    });

    test('defaults style fields like the Java opt* calls', () {
      final response2 = {
        'nodes': {
          '1:1': {
            'document': {
              'id': '1:1',
              'type': 'TEXT',
              'style': const {},
            },
          },
        },
      };
      final entry =
          (figmaTextContent(response2, ['1:1'])['textNodes'] as Map)['1:1']
              as Map;
      expect(entry['text'], '');
      expect(entry['fontFamily'], '');
      expect(entry['fontSize'], 0.0);
      expect(entry['fontWeight'], 400);
      expect(entry['lineHeight'], 0.0);
      expect(entry['letterSpacing'], 0.0);
      expect(entry['textAlign'], 'LEFT');
    });
  });

  group('figmaStylesResult', () {
    test('returns the empty design-token envelope (Java stub parity)', () {
      expect(figmaStylesResult(), {
        'colorStyles': <dynamic>[],
        'textStyles': <dynamic>[],
      });
    });
  });

  group('figmaNodeDocument', () {
    test('returns the document of the given node id', () {
      final response = {
        'nodes': {
          '1:1': {
            'document': {'id': '1:1', 'type': 'FRAME'},
          },
        },
      };
      expect(figmaNodeDocument(response, '1:1'), {'id': '1:1', 'type': 'FRAME'});
    });

    test('returns null when the node or document is missing', () {
      expect(figmaNodeDocument(const {'nodes': <String, dynamic>{}}, '1:1'), isNull);
      expect(figmaNodeDocument(const {'nodes': {'1:1': <String, dynamic>{}}}, '1:1'), isNull);
    });
  });
}
