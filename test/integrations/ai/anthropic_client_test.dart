import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [AnthropicClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  requestTests();
  messageAndErrorTests();
}

/// Request-shape and response-extraction tests for [AnthropicClient].
void requestTests() {
  group('AnthropicClient', () {
    test('posts to basePath with x-api-key header', () async {
      final f = mockAi(AnthropicClient.new, _anthropicBody);
      await f.client.chat('claude-3', 'hello');
      final call = f.adapter.calls.single;
      expect(call.path, 'https://anthropic.example.com/v1/messages');
      expect(call.method, 'POST');
      expect(call.headers['x-api-key'], 'ant-key');
    });

    test('sends model, max_tokens, and user message', () async {
      final f = mockAi(AnthropicClient.new, _anthropicBody);
      await f.client.chat('claude-3', 'hello');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['model'], 'claude-3');
      expect(body['max_tokens'], 2048);
      expect(body['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
    });

    test('extracts content[0].text', () async {
      final f = mockAi(AnthropicClient.new, _anthropicBody);
      expect(await f.client.chat('claude-3', 'hi'), 'Anthropic response');
    });

    test('returns empty string when content is empty', () async {
      final f = mockAi(AnthropicClient.new, (o) => '{"content":[]}');
      expect(await f.client.chat('claude-3', 'hi'), '');
    });
  });
}

/// Multi-turn and configuration-error tests for [AnthropicClient].
void messageAndErrorTests() {
  group('AnthropicClient chatWithMessages', () {
    test('sends system as top-level field', () async {
      final f = mockAi(AnthropicClient.new, _anthropicBody);
      await f.client.chatWithMessages(
          'claude-3',
          [
            {'role': 'user', 'content': 'q1'},
          ],
          'be nice');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['system'], 'be nice');
      expect(body['messages'], [
        {'role': 'user', 'content': 'q1'},
      ]);
    });

    test('omits system field when absent', () async {
      final f = mockAi(AnthropicClient.new, _anthropicBody);
      await f.client.chatWithMessages('claude-3', [
        {'role': 'user', 'content': 'q1'},
      ]);
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body.containsKey('system'), isFalse);
    });

    test('throws StateError when ANTHROPIC_API_KEY is missing', () {
      PropertyReader.clearOverrides();
      expect(() => AnthropicClient(PropertyReader()), throwsStateError);
    });
  });
}

/// Canned Anthropic messages response.
String _anthropicBody(RequestOptions o) =>
    '{"content":[{"type":"text","text":"Anthropic response"}]}';
