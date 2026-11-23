import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [OpenAIClient].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  group('OpenAIClient', () {
    _testBasicOpenAiCalls();
    _testOpenAiExtraBody();
  });
}

void _testBasicOpenAiCalls() {
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
    expect(body['messages'].first, {'role': 'system', 'content': 'be helpful'});
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
}

void _testOpenAiExtraBody() {
  test('merges OPENAI_EXTRA_BODY including nested objects and overrides',
      () async {
    final f = mockAi(OpenAIClient.new, _openaiBody);
    f.client.setExtraBody(
      '{"top_k":20,"min_p":0.0,"temperature":0.9,"max_completion_tokens":8,"chat_template_kwargs":{"enable_thinking":true}}',
    );
    await f.client.chat('gpt-4', 'hello');
    final body = jsonDecode(f.adapter.calls.single.data as String);
    expect(body['top_k'], 20);
    expect(body['min_p'], 0.0);
    expect(body['temperature'], 0.9);
    expect(body['max_completion_tokens'], 8);
    expect(body['chat_template_kwargs'], {'enable_thinking': true});
  });

  test('OPENAI_EXTRA_BODY cannot override model or messages', () async {
    final f = mockAi(OpenAIClient.new, _openaiBody);
    f.client.setExtraBody('{"model":"other","messages":[],"top_k":5}');
    await f.client.chat('gpt-4', 'hello');
    final body = jsonDecode(f.adapter.calls.single.data as String);
    expect(body['model'], 'gpt-4');
    expect(body['messages'], hasLength(1));
    expect(body['top_k'], 5);
  });

  test('blank, null, or placeholder OPENAI_EXTRA_BODY clears extraBody',
      () async {
    final f = mockAi(OpenAIClient.new, _openaiBody);
    f.client.setExtraBody('{"top_k":5}');
    expect(f.client.extraBody, {'top_k': 5});
    f.client.extraBody!['top_k'] = 99;
    expect(f.client.extraBody, {'top_k': 5});
    f.client.setExtraBody('   ');
    expect(f.client.extraBody, isNull);
    f.client.setExtraBody(r'${OPENAI_EXTRA_BODY}');
    expect(f.client.extraBody, isNull);
    await f.client.chat('gpt-4', 'hello');
    final body = jsonDecode(f.adapter.calls.single.data as String);
    expect(body.containsKey('top_k'), isFalse);
  });

  test('invalid OPENAI_EXTRA_BODY throws ArgumentError', () {
    expect(() => OpenAIClient.parseExtraBody('top_k=20'), throwsArgumentError);
    expect(() => OpenAIClient.parseExtraBody('[1,2]'), throwsArgumentError);
  });
}

/// Canned OpenAI chat-completions response.
String _openaiBody(RequestOptions o) =>
    '{"choices":[{"message":{"content":"OpenAI response"}}]}';
