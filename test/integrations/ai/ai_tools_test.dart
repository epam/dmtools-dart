import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [aiTools] and [AiToolExecutor].
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Tool-definition tests for the `ai_chat` tool.
void toolCatalogTests() {
  group('aiTools', () {
    test('defines ai_chat with provider param', () {
      final tools = aiTools();
      expect(tools, hasLength(1));
      final chat = tools.single;
      expect(chat.name, 'ai_chat');
      expect(chat.integration, 'ai');
      expect(chat.params.map((p) => p.name).toList(),
          ['provider', 'model', 'prompt', 'system_prompt']);
      expect(chat.requiredParams, ['provider', 'model', 'prompt']);
    });

    test('toJson produces MCP protocol JSON', () {
      final json = aiTools().single.toJson();
      expect(json['name'], 'ai_chat');
      final schema = json['inputSchema'] as Map<String, dynamic>;
      final props = schema['properties'] as Map<String, dynamic>;
      expect(props['provider'], isNotNull);
      expect(props['system_prompt'], isNotNull);
      expect(schema['required'], ['provider', 'model', 'prompt']);
    });
  });
}

/// Provider-dispatch tests for [AiToolExecutor].
void executorDispatchTests() {
  group('AiToolExecutor', () {
    test('dispatches to gemini', () async {
      final f = mockAiExecutor(_routerFor('/gemini'));
      final result = await f.executor.execute('ai_chat', {
        'provider': 'gemini',
        'model': 'gemini-1.5-flash',
        'prompt': 'hi',
        'system_prompt': 'be nice',
      });
      expect(result, 'Gemini response');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['systemInstruction'], isNotNull);
    });

    test('dispatches to openai', () async {
      final f = mockAiExecutor(_routerFor('openai.example.com'));
      final result = await f.executor.execute('ai_chat', {
        'provider': 'openai',
        'model': 'gpt-4',
        'prompt': 'hi',
      });
      expect(result, 'OpenAI response');
      expect(f.adapter.calls.single.path, contains('openai.example.com'));
    });

    test('dispatches to ollama (ignores system_prompt)', () async {
      final f = mockAiExecutor(_routerFor('/api/chat'));
      final result = await f.executor.execute('ai_chat', {
        'provider': 'ollama',
        'model': 'llama3',
        'prompt': 'hi',
        'system_prompt': 'be nice',
      });
      expect(result, 'Ollama response');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body.containsKey('systemInstruction'), isFalse);
      expect(body['messages'], hasLength(1));
    });
  });
  executorErrorTests();
}

/// Error-path tests for [AiToolExecutor].
void executorErrorTests() {
  group('AiToolExecutor errors', () {
    test('throws ArgumentError for unknown tool', () async {
      final f = mockAiExecutor((o) => '{}');
      expect(
        () => f.executor.execute('ai_unknown', {}),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for unknown provider', () async {
      final f = mockAiExecutor((o) => '{}');
      expect(
        () => f.executor.execute('ai_chat', {
          'provider': 'anthropic',
          'model': 'm',
          'prompt': 'p',
        }),
        throwsArgumentError,
      );
    });
  });
}

/// Builds a router returning the canned body for [marker]'s provider.
String Function(RequestOptions) _routerFor(String marker) {
  switch (marker) {
    case '/gemini':
      return (_) =>
          '{"candidates":[{"content":{"parts":[{"text":"Gemini response"}]}}]}';
    case 'openai.example.com':
      return (_) => '{"choices":[{"message":{"content":"OpenAI response"}}]}';
    default:
      return (_) => '{"message":{"content":"Ollama response"}}';
  }
}
