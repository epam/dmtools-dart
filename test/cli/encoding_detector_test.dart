/// Unit tests for [autoDetectAndDecode] (Java `EncodingDetector` port).
library;

import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  _testBase64Decode();
  _testUrlDecode();
  _testFallbackAndErrors();
}

void _testBase64Decode() {
  group('base64 decoding', () {
    test('decodes valid base64 text', () {
      final encoded = base64.encode(utf8.encode('hello world'));
      expect(autoDetectAndDecode(encoded), 'hello world');
    });

    test('decodes base64 with full padding', () {
      final encoded = base64.encode(utf8.encode('a'));
      expect(autoDetectAndDecode(encoded), 'a');
    });

    test('decodes base64 JSON config', () {
      const json = '{"key":"value"}';
      final encoded = base64.encode(utf8.encode(json));
      expect(autoDetectAndDecode(encoded), json);
    });

    test('rejects a length not divisible by 4', () {
      // 'abc' has length 3 — fails the base64 length check, then URL-decodes.
      expect(autoDetectAndDecode('abc'), 'abc');
    });

    test('rejects characters outside the base64 alphabet', () {
      // Length 4 but contains '%', failing both the base64 regex and the
      // URL-decode fallback.
      expect(() => autoDetectAndDecode('%%%%'), throwsArgumentError);
    });

    test('rejects base64 that decodes to invalid UTF-8', () {
      // '////' is alphabet-valid base64 decoding to 0xFFFFFF, which is not
      // UTF-8; the URL-decode fallback then returns it unchanged.
      expect(autoDetectAndDecode('////'), '////');
    });

    test('rejects an empty candidate', () {
      expect(autoDetectAndDecode(''), '');
    });
  });
}

void _testUrlDecode() {
  group('URL decoding', () {
    test('decodes percent-encoded text', () {
      expect(autoDetectAndDecode('hello%20world'), 'hello world');
    });

    test('decodes URL-encoded JSON', () {
      const encoded = '%7B%22key%22%3A%22value%22%7D';
      expect(autoDetectAndDecode(encoded), '{"key":"value"}');
    });

    test('returns plain ASCII unchanged', () {
      expect(autoDetectAndDecode('plain'), 'plain');
    });
  });
}

void _testFallbackAndErrors() {
  group('fallback and errors', () {
    test('throws ArgumentError when both decoders fail', () {
      expect(() => autoDetectAndDecode('%%%'), throwsArgumentError);
    });
  });
}
