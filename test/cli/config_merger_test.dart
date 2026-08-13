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
