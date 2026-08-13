import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [aiTools] and [AiToolExecutor].
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  chatDispatchTests();
  newProviderChatTests();
  historyDispatchTests();
  newProviderHistoryTests();
  executorErrorTests();
}

/// Tool-definition tests for the `ai_chat` and `ai_chat_with_history` tools.
void toolCatalogTests() {
  group('aiTools', () {
    final tools = aiTools();

    test('defines ai_chat and ai_chat_with_history', () {
      expect(tools.map((t) => t.name).toList(),
          ['ai_chat', 'ai_chat_with_history']);
      expect(tools.every((t) => t.integration == 'ai'), isTrue);
    });

    test('ai_chat params are provider, model, prompt, system_prompt', () {
      final chat = tools.firstWhere((t) => t.name == 'ai_chat');
      expect(chat.params.map((p) => p.name).toList(),
          ['provider', 'model', 'prompt', 'system_prompt']);
      expect(chat.requiredParams, ['provider', 'model', 'prompt']);
    });

    test('ai_chat_with_history params include messages array', () {
      final history = tools.firstWhere((t) => t.name == 'ai_chat_with_history');
      expect(history.params.map((p) => p.name).toList(),
          ['provider', 'model', 'messages', 'system_prompt']);
      final messagesParam =
          history.params.singleWhere((p) => p.name == 'messages');
      expect(messagesParam.type, 'array');
      expect(history.requiredParams, ['provider', 'model', 'messages']);
    });

    test('toJson produces MCP protocol JSON', () {
      final json = tools.firstWhere((t) => t.name == 'ai_chat').toJson();
      expect(json['name'], 'ai_chat');
      final schema = json['inputSchema'] as Map<String, dynamic>;
      final props = schema['properties'] as Map<String, dynamic>;
      expect(props['provider'], isNotNull);
      expect(props['system_prompt'], isNotNull);
      expect(schema['required'], ['provider', 'model', 'prompt']);
    });
  });
}

/// Provider-dispatch tests for the single-turn `ai_chat` tool.
void chatDispatchTests() {
  group('AiToolExecutor ai_chat', () {
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
}

/// Single-turn chat-dispatch tests for the dial and anthropic providers.
void newProviderChatTests() {
  group('AiToolExecutor ai_chat (dial, anthropic)', () {
    test('dispatches to dial with Bearer auth', () async {
      final f = mockAiExecutor(_routerFor('dial.example.com'));
      final result = await f.executor.execute('ai_chat', {
        'provider': 'dial',
        'model': 'gpt-4',
        'prompt': 'hi',
      });
      expect(result, 'DIAL response');
      final call = f.adapter.calls.single;
      expect(call.path, 'https://dial.example.com/openai/deployments');
      expect(call.headers['authorization'], 'Bearer dial-key');
      final body = jsonDecode(call.data as String);
      expect(body['model'], 'gpt-4');
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('dispatches to anthropic with x-api-key', () async {
      final f = mockAiExecutor(_routerFor('anthropic.example.com'));
      final result = await f.executor.execute('ai_chat', {
        'provider': 'anthropic',
        'model': 'claude-3',
        'prompt': 'hi',
      });
      expect(result, 'Anthropic response');
      final call = f.adapter.calls.single;
      expect(call.headers['x-api-key'], 'ant-key');
      final body = jsonDecode(call.data as String);
      expect(body['model'], 'claude-3');
      expect(body['max_tokens'], 2048);
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });
  });
}

/// Two-turn message history used by the `ai_chat_with_history` tests.
const historyMessages = [
  {'role': 'user', 'content': 'q1'},
  {'role': 'assistant', 'content': 'a1'},
];

/// Provider-dispatch tests for the multi-turn `ai_chat_with_history` tool.
void historyDispatchTests() {
  group('AiToolExecutor ai_chat_with_history', () {
    test('openai: prepends system and sends messages', () async {
      final f = mockAiExecutor(_routerFor('openai.example.com'));
      final result = await f.executor.execute('ai_chat_with_history', {
        'provider': 'openai',
        'model': 'gpt-4',
        'messages': historyMessages,
        'system_prompt': 'be nice',
      });
      expect(result, 'OpenAI response');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['messages'], [
        {'role': 'system', 'content': 'be nice'},
        ...historyMessages,
      ]);
    });

    test('gemini: maps roles to contents and systemInstruction', () async {
      final f = mockAiExecutor(_routerFor('/gemini'));
      await f.executor.execute('ai_chat_with_history', {
        'provider': 'gemini',
        'model': 'gemini-1.5-flash',
        'messages': historyMessages,
        'system_prompt': 'be concise',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'q1'}
          ]
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'a1'}
          ]
        },
      ]);
      expect(body['systemInstruction']['parts'][0]['text'], 'be concise');
    });

    test('ollama: prepends system and keeps stream false', () async {
      final f = mockAiExecutor(_routerFor('/api/chat'));
      await f.executor.execute('ai_chat_with_history', {
        'provider': 'ollama',
        'model': 'llama3',
        'messages': historyMessages,
        'system_prompt': 'be nice',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['stream'], isFalse);
      expect(body['messages'].first, {'role': 'system', 'content': 'be nice'});
    });
  });
}

/// History-dispatch tests for the dial and anthropic providers.
void newProviderHistoryTests() {
  group('AiToolExecutor ai_chat_with_history (dial, anthropic)', () {
    test('dial: prepends system and sends messages', () async {
      final f = mockAiExecutor(_routerFor('dial.example.com'));
      await f.executor.execute('ai_chat_with_history', {
        'provider': 'dial',
        'model': 'gpt-4',
        'messages': historyMessages,
        'system_prompt': 'be nice',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['messages'], [
        {'role': 'system', 'content': 'be nice'},
        ...historyMessages,
      ]);
    });

    test('anthropic: sends system as top-level field', () async {
      final f = mockAiExecutor(_routerFor('anthropic.example.com'));
      await f.executor.execute('ai_chat_with_history', {
        'provider': 'anthropic',
        'model': 'claude-3',
        'messages': historyMessages,
        'system_prompt': 'be nice',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['system'], 'be nice');
      expect(body['messages'], historyMessages);
    });
  });
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

    test('throws ArgumentError for unknown provider on ai_chat', () async {
      final f = mockAiExecutor((o) => '{}');
      expect(
        () => f.executor.execute('ai_chat', {
          'provider': 'bedrock',
          'model': 'm',
          'prompt': 'p',
        }),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for unknown provider on history tool', () async {
      final f = mockAiExecutor((o) => '{}');
      expect(
        () => f.executor.execute('ai_chat_with_history', {
          'provider': 'unknown',
          'model': 'm',
          'messages': const [],
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
    case 'dial.example.com':
      return (_) => '{"choices":[{"message":{"content":"DIAL response"}}]}';
    case 'anthropic.example.com':
      return (_) => '{"content":[{"type":"text","text":"Anthropic response"}]}';
    default:
      return (_) => '{"message":{"content":"Ollama response"}}';
  }
}
