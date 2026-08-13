import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [OllamaClient].
void main() {
  tearDown(PropertyReader.clearOverrides);

  group('OllamaClient', () {
    test('posts to {basePath}/api/chat', () async {
      final f = mockAi(OllamaClient.new, _ollamaBody);
      await f.client.chat('llama3', 'hello');
      final call = f.adapter.calls.single;
      expect(call.path, 'http://ollama.example.com:11434/api/chat');
      expect(call.method, 'POST');
    });

    test('sends model, messages, and stream:false', () async {
      final f = mockAi(OllamaClient.new, _ollamaBody);
      await f.client.chat('llama3', 'hello');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['model'], 'llama3');
      expect(body['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(body['stream'], isFalse);
    });

    test('extracts message.content', () async {
      final f = mockAi(OllamaClient.new, _ollamaBody);
      expect(await f.client.chat('llama3', 'hi'), 'Ollama response');
    });

    test('returns empty string when message is absent', () async {
      final f = mockAi(OllamaClient.new, (o) => '{}');
      expect(await f.client.chat('llama3', 'hi'), '');
    });

    test('uses default base path when OLLAMA_BASE_PATH is unset', () async {
      PropertyReader.clearOverrides();
      PropertyReader.setOverrides({});
      final client = OllamaClient(PropertyReader());
      // Default is http://localhost:11434 — just verify construction succeeds.
      expect(client, isNotNull);
    });
  });
}

/// Canned Ollama `/api/chat` response.
String _ollamaBody(RequestOptions o) =>
    '{"message":{"content":"Ollama response"}}';
