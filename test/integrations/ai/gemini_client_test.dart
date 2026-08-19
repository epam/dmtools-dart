import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [GeminiClient].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  group('GeminiClient', () {
    test('posts to {basePath}/{model}:generateContent?key={apiKey}', () async {
      final f = mockAi(GeminiClient.new, _geminiBody);
      await f.client.chat('gemini-1.5-flash', 'hello');
      final call = f.adapter.calls.single;
      expect(
        call.path,
        'https://gemini.example.com/v1beta/models/'
        'gemini-1.5-flash:generateContent?key=gem-key',
      );
      expect(call.method, 'POST');
    });

    test('sends prompt as contents[0].parts[0].text', () async {
      final f = mockAi(GeminiClient.new, _geminiBody);
      await f.client.chat('gemini-1.5-flash', 'hello');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['contents'][0]['parts'][0]['text'], 'hello');
    });

    test('includes systemInstruction when systemPrompt is given', () async {
      final f = mockAi(GeminiClient.new, _geminiBody);
      await f.client.chat('gemini-1.5-flash', 'hi', 'be concise');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['systemInstruction']['parts'][0]['text'], 'be concise');
    });

    test('omits systemInstruction when systemPrompt is absent', () async {
      final f = mockAi(GeminiClient.new, _geminiBody);
      await f.client.chat('gemini-1.5-flash', 'hi');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body.containsKey('systemInstruction'), isFalse);
    });

    test('extracts candidates[0].content.parts[0].text', () async {
      final f = mockAi(GeminiClient.new, _geminiBody);
      expect(await f.client.chat('m', 'hi'), 'Gemini response');
    });

    test('returns empty string when candidates is empty', () async {
      final f = mockAi(GeminiClient.new, (o) => '{"candidates":[]}');
      expect(await f.client.chat('m', 'hi'), '');
    });

    test('throws StateError when GEMINI_API_KEY is missing', () {
      PropertyReader.clearOverrides();
      expect(() => GeminiClient(PropertyReader()), throwsStateError);
    });
  });
}

/// Canned Gemini `generateContent` response.
String _geminiBody(RequestOptions o) =>
    '{"candidates":[{"content":{"parts":[{"text":"Gemini response"}]}}]}';
