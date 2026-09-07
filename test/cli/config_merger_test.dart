/// Unit tests for [deepMerge] and [mergeEncodedConfig] (Java
/// `ConfigurationMerger` port).
library;

import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  _testDeepMerge();
  _testDeepMergeExtra();
  _testMergeEncodedConfig();
  _testMergeErrorMessages();
}

void _testDeepMerge() {
  group('deepMerge', () {
    test('override scalar wins', () {
      expect(
        deepMerge({'a': 'base'}, {'a': 'override'}),
        {'a': 'override'},
      );
    });

    test('adds keys missing from base', () {
      expect(
        deepMerge({'a': 1}, {'b': 2}),
        {'a': 1, 'b': 2},
      );
    });

    test('recursively merges nested maps', () {
      final result = deepMerge(
        {
          'outer': {'a': 'base', 'b': 'base'}
        },
        {
          'outer': {'b': 'override', 'c': 'new'}
        },
      );
      expect(
        result,
        {
          'outer': {'a': 'base', 'b': 'override', 'c': 'new'}
        },
      );
    });
  });
}

/// Java-parity error messages for malformed encoded configs.
void _testMergeErrorMessages() {
  group('mergeEncodedConfig error messages', () {
    test('empty base JSON is rejected (Java IAE message)', () {
      // Java ConfigurationMerger.mergeConfigurations: "File JSON cannot be
      // null or empty" when the file config is blank.
      expect(
          () => mergeEncodedConfig('', '{}'),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
              'File JSON cannot be null or empty')));
    });

    test('invalid base JSON error includes the file content (Java #525)', () {
      // Java 8e5fc724: the offending JSON string is embedded in the error
      // so malformed configs are debuggable straight from CI logs.
      const broken = '{"name": "job",';
      expect(
        () => mergeEncodedConfig(broken, '{}'),
        throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(startsWith('Invalid JSON format: '),
                contains('. File JSON content: $broken')))),
      );
    });

    test('invalid override JSON error includes the decoded content', () {
      const broken = '{"params": ';
      final encoded = base64.encode(utf8.encode(broken));
      expect(
        () => mergeEncodedConfig('{"name": "job"}', encoded),
        throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(startsWith('Invalid JSON format: '),
                contains('. Encoded JSON content: $broken')))),
      );
    });
  });
}

void _testDeepMergeExtra() {
  group('deepMerge (edge cases)', () {
    test('array values are replaced, not concatenated', () {
      final result = deepMerge(
        {
          'items': [1, 2]
        },
        {
          'items': [3]
        },
      );
      expect(result, {
        'items': [3]
      });
    });

    test('does not mutate the input maps', () {
      final base = {
        'a': {'k': 'v'}
      };
      deepMerge(base, {
        'a': {'k2': 'v2'}
      });
      expect(base, {
        'a': {'k': 'v'}
      });
    });

    test('override null replaces base value', () {
      expect(deepMerge({'a': 'value'}, {'a': null}), {'a': null});
    });
  });
}

void _testMergeEncodedConfig() {
  group('mergeEncodedConfig', () {
    test('returns base unchanged when encoded is null', () {
      const base = '{"name":"job"}';
      expect(mergeEncodedConfig(base, null), base);
    });

    test('returns base unchanged when encoded is empty', () {
      const base = '{"name":"job"}';
      expect(mergeEncodedConfig(base, ''), base);
    });

    test('merges base64-encoded JSON override', () {
      const base = '{"name":"job","params":{"k1":"v1"}}';
      final encoded = base64.encode(utf8.encode('{"params":{"k2":"v2"}}'));
      final result = mergeEncodedConfig(base, encoded);
      expect(
        jsonDecode(result),
        {
          'name': 'job',
          'params': {'k1': 'v1', 'k2': 'v2'}
        },
      );
    });

    test('merges URL-encoded JSON override', () {
      const base = '{"name":"job"}';
      const encoded = '%7B%22params%22%3A%7B%22k%22%3A%22v%22%7D%7D';
      final result = mergeEncodedConfig(base, encoded);
      expect(
        jsonDecode(result),
        {
          'name': 'job',
          'params': {'k': 'v'}
        },
      );
    });
  });
}
