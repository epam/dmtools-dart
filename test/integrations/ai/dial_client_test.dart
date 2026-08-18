import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Coverage + behavior tests for [DialClient].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  requestTests();
  messageAndErrorTests();
}

/// Request-shape and response-extraction tests for [DialClient].
void requestTests() {
  group('DialClient', () {
    test('posts to basePath with Bearer auth header', () async {
      final f = mockAi(DialClient.new, _dialBody);
      await f.client.chat('gpt-4', 'hello');
      final call = f.adapter.calls.single;
      expect(call.path, 'https://dial.example.com/openai/deployments');
      expect(call.method, 'POST');
      expect(call.headers['authorization'], 'Bearer dial-key');
    });

    test('sends model and user message', () async {
      final f = mockAi(DialClient.new, _dialBody);
      await f.client.chat('gpt-4', 'hello');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['model'], 'gpt-4');
      expect(body['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
    });

    test('extracts choices[0].message.content', () async {
      final f = mockAi(DialClient.new, _dialBody);
      expect(await f.client.chat('gpt-4', 'hi'), 'DIAL response');
    });

    test('returns empty string when choices is empty', () async {
      final f = mockAi(DialClient.new, (o) => '{"choices":[]}');
      expect(await f.client.chat('gpt-4', 'hi'), '');
    });
  });
}

/// Multi-turn and configuration-error tests for [DialClient].
void messageAndErrorTests() {
  group('DialClient chatWithMessages', () {
    test('prepends system message', () async {
      final f = mockAi(DialClient.new, _dialBody);
      await f.client.chatWithMessages(
          'gpt-4',
          [
            {'role': 'user', 'content': 'q1'},
            {'role': 'assistant', 'content': 'a1'},
          ],
          'be nice');
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['messages'], [
        {'role': 'system', 'content': 'be nice'},
        {'role': 'user', 'content': 'q1'},
        {'role': 'assistant', 'content': 'a1'},
      ]);
    });

    test('passes messages through when no system', () async {
      final f = mockAi(DialClient.new, _dialBody);
      await f.client.chatWithMessages('gpt-4', [
        {'role': 'user', 'content': 'q1'},
      ]);
      final body = jsonDecode(f.adapter.calls.single.data as String);
      expect(body['messages'], [
        {'role': 'user', 'content': 'q1'},
      ]);
    });

    test('throws StateError when DIAL_API_KEY is missing', () {
      PropertyReader.clearOverrides();
      expect(() => DialClient(PropertyReader()), throwsStateError);
    });

    test('throws StateError when DIAL_BASE_PATH is missing', () {
      PropertyReader.setOverrides({'DIAL_API_KEY': 'dial-key'});
      expect(() => DialClient(PropertyReader()), throwsStateError);
    });
  });
}

/// Canned DIAL chat-completions response.
String _dialBody(RequestOptions o) =>
    '{"choices":[{"message":{"content":"DIAL response"}}]}';
