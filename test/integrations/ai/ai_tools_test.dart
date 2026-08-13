import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [aiTools] and [AiToolExecutor].
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  newToolCatalogTests();
  chatDispatchTests();
  newProviderChatTests();
  historyDispatchTests();
  newProviderHistoryTests();
  systemPromptDispatchTests();
  completeDispatchTests();
  newProviderCompleteTests();
  executorErrorTests();
  newToolErrorTests();
}

/// Tool-definition tests for the AI tools.
void toolCatalogTests() {
  group('aiTools', () {
    final tools = aiTools();

    test('defines the four AI tools in catalog order', () {
      expect(tools.map((t) => t.name).toList(), [
        'ai_chat',
        'ai_chat_with_history',
        'ai_chat_with_system_prompt',
        'ai_complete',
      ]);
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

/// Tool-definition tests for the two new AI tools.
void newToolCatalogTests() {
  group('aiTools (new tools)', () {
    final tools = aiTools();

    test('ai_chat_with_system_prompt requires system_prompt', () {
      final tool =
          tools.firstWhere((t) => t.name == 'ai_chat_with_system_prompt');
      expect(tool.params.map((p) => p.name).toList(),
          ['provider', 'model', 'prompt', 'system_prompt']);
      expect(tool.requiredParams,
          ['provider', 'model', 'prompt', 'system_prompt']);
    });

    test('ai_complete has required max_tokens and optional temperature', () {
      final tool = tools.firstWhere((t) => t.name == 'ai_complete');
      expect(tool.params.map((p) => p.name).toList(),
          ['provider', 'model', 'prompt', 'max_tokens', 'temperature']);
      expect(
          tool.requiredParams, ['provider', 'model', 'prompt', 'max_tokens']);
      final maxTokens = tool.params.singleWhere((p) => p.name == 'max_tokens');
      expect(maxTokens.type, 'number');
      final temperature =
          tool.params.singleWhere((p) => p.name == 'temperature');
      expect(temperature.type, 'number');
      expect(temperature.required, isFalse);
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

/// Dispatch tests for `ai_chat_with_system_prompt`.
///
/// Unlike `ai_chat`, the system prompt must reach every provider, including
/// ollama, dial, and anthropic (which ignore it in plain `ai_chat`).
void systemPromptDispatchTests() {
  group('AiToolExecutor ai_chat_with_system_prompt', () {
    test('ollama applies the system prompt (unlike ai_chat)', () async {
      final f = mockAiExecutor(_routerFor('/api/chat'));
      await f.executor.execute('ai_chat_with_system_prompt', {
        'provider': 'ollama',
        'model': 'llama3',
        'prompt': 'hi',
        'system_prompt': 'be nice',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['messages'].first, {'role': 'system', 'content': 'be nice'});
    });

    test('dial applies the system prompt', () async {
      final f = mockAiExecutor(_routerFor('dial.example.com'));
      await f.executor.execute('ai_chat_with_system_prompt', {
        'provider': 'dial',
        'model': 'gpt-4',
        'prompt': 'hi',
        'system_prompt': 'be nice',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['messages'].first, {'role': 'system', 'content': 'be nice'});
    });

    test('anthropic sends system as top-level field', () async {
      final f = mockAiExecutor(_routerFor('anthropic.example.com'));
      await f.executor.execute('ai_chat_with_system_prompt', {
        'provider': 'anthropic',
        'model': 'claude-3',
        'prompt': 'hi',
        'system_prompt': 'be nice',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['system'], 'be nice');
    });

    test('gemini still uses systemInstruction', () async {
      final f = mockAiExecutor(_routerFor('/gemini'));
      await f.executor.execute('ai_chat_with_system_prompt', {
        'provider': 'gemini',
        'model': 'gemini-1.5-flash',
        'prompt': 'hi',
        'system_prompt': 'be concise',
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['systemInstruction']['parts'][0]['text'], 'be concise');
    });
  });
}

/// Dispatch tests for the low-level `ai_complete` tool.
void completeDispatchTests() {
  group('AiToolExecutor ai_complete', () {
    test('openai: explicit max_tokens and temperature', () async {
      final f = mockAiExecutor(_routerFor('openai.example.com'));
      final result = await f.executor.execute('ai_complete', {
        'provider': 'openai',
        'model': 'gpt-4',
        'prompt': 'hi',
        'max_tokens': 256,
        'temperature': 0.7,
      });
      expect(result, 'OpenAI response');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['max_completion_tokens'], 256);
      expect(body['temperature'], 0.7);
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('openai: omits temperature when not provided', () async {
      final f = mockAiExecutor(_routerFor('openai.example.com'));
      await f.executor.execute('ai_complete', {
        'provider': 'openai',
        'model': 'gpt-4',
        'prompt': 'hi',
        'max_tokens': 128,
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body.containsKey('temperature'), isFalse);
      expect(body['max_completion_tokens'], 128);
    });

    test('anthropic: max_tokens and temperature', () async {
      final f = mockAiExecutor(_routerFor('anthropic.example.com'));
      await f.executor.execute('ai_complete', {
        'provider': 'anthropic',
        'model': 'claude-3',
        'prompt': 'hi',
        'max_tokens': 512,
        'temperature': 0.2,
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['max_tokens'], 512);
      expect(body['temperature'], 0.2);
    });
  });
}

/// Completion-dispatch tests for the gemini, ollama, and dial providers.
void newProviderCompleteTests() {
  group('AiToolExecutor ai_complete (gemini, ollama, dial)', () {
    test('gemini: generationConfig with maxOutputTokens', () async {
      final f = mockAiExecutor(_routerFor('/gemini'));
      await f.executor.execute('ai_complete', {
        'provider': 'gemini',
        'model': 'gemini-1.5-flash',
        'prompt': 'hi',
        'max_tokens': 64,
        'temperature': 0.1,
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['generationConfig']['maxOutputTokens'], 64);
      expect(body['generationConfig']['temperature'], 0.1);
      expect(body['contents'][0]['parts'][0]['text'], 'hi');
    });

    test('ollama: options.num_predict with token cap', () async {
      final f = mockAiExecutor(_routerFor('/api/chat'));
      await f.executor.execute('ai_complete', {
        'provider': 'ollama',
        'model': 'llama3',
        'prompt': 'hi',
        'max_tokens': 100,
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['options']['num_predict'], 100);
      expect(body.containsKey('temperature'), isFalse);
    });

    test('dial: max_tokens and optional temperature', () async {
      final f = mockAiExecutor(_routerFor('dial.example.com'));
      await f.executor.execute('ai_complete', {
        'provider': 'dial',
        'model': 'gpt-4',
        'prompt': 'hi',
        'max_tokens': 200,
        'temperature': 0.9,
      });
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['max_tokens'], 200);
      expect(body['temperature'], 0.9);
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

/// Error-path tests for the new AI tools.
void newToolErrorTests() {
  group('AiToolExecutor errors (new tools)', () {
    test('throws ArgumentError for unknown provider on system-prompt tool',
        () async {
      final f = mockAiExecutor((o) => '{}');
      expect(
        () => f.executor.execute('ai_chat_with_system_prompt', {
          'provider': 'unknown',
          'model': 'm',
          'prompt': 'p',
          'system_prompt': 's',
        }),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for unknown provider on ai_complete', () async {
      final f = mockAiExecutor((o) => '{}');
      expect(
        () => f.executor.execute('ai_complete', {
          'provider': 'unknown',
          'model': 'm',
          'prompt': 'p',
          'max_tokens': 64,
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
