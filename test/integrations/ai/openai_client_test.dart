import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [OpenAIClient].
void main() {
  tearDown(PropertyReader.clearOverrides);

  group('OpenAIClient', () {
    test('posts to basePath with Bearer auth header', () async {
      final f = mockAi(OpenAIClient.new, _openaiBody);
      await f.client.chat('gpt-4', 'hello');
      final call = f.adapter.calls.single;
      expect(call.path, 'https://openai.example.com/v1/chat/completions');
      expect(call.method, 'POST');
      expect(call.headers['authorization'], 'Bearer oai-key');
    });

    test('sends model and user message', () async {
      final f = mockAi(OpenAIClient.new, _openaiBody);
      await f.client.chat('gpt-4', 'hello');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['model'], 'gpt-4');
      expect(body['messages'].last, {'role': 'user', 'content': 'hello'});
    });

    test('prepends system message when systemPrompt is given', () async {
      final f = mockAi(OpenAIClient.new, _openaiBody);
      await f.client.chat('gpt-4', 'hello', 'be helpful');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(
          body['messages'].first, {'role': 'system', 'content': 'be helpful'});
      expect(body['messages'].last, {'role': 'user', 'content': 'hello'});
    });

    test('includes max_tokens and temperature from config', () async {
      final f = mockAi(OpenAIClient.new, _openaiBody);
      await f.client.chat('gpt-4', 'hello');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['max_completion_tokens'], 1024);
      expect(body['temperature'], 0.5);
    });

    test('extracts choices[0].message.content', () async {
      final f = mockAi(OpenAIClient.new, _openaiBody);
      expect(await f.client.chat('gpt-4', 'hi'), 'OpenAI response');
    });

    test('returns empty string when choices is empty', () async {
      final f = mockAi(OpenAIClient.new, (o) => '{"choices":[]}');
      expect(await f.client.chat('gpt-4', 'hi'), '');
    });

    test('throws StateError when OPENAI_API_KEY is missing', () {
      PropertyReader.clearOverrides();
      expect(() => OpenAIClient(PropertyReader()), throwsStateError);
    });
  });
}

/// Canned OpenAI chat-completions response.
String _openaiBody(RequestOptions o) =>
    '{"choices":[{"message":{"content":"OpenAI response"}}]}';
