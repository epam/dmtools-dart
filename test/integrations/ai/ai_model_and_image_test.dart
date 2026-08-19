import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ai_test_support.dart';

/// Tests for the model and image AI tools (`ai_list_models`,
/// `ai_generate_image`).
void main() {
  tearDown(PropertyReader.clearOverrides);
  listModelsCatalogTests();
  listModelsDispatchTests();
  generateImageCatalogTests();
  generateImageDispatchTests();
}

/// Catalog checks for `ai_list_models`.
void listModelsCatalogTests() {
  group('ai_list_models definition', () {
    final tool = aiTools().firstWhere((t) => t.name == 'ai_list_models');

    test('declares a single required provider param', () {
      expect(tool.params.map((p) => p.name), ['provider']);
      expect(tool.requiredParams, ['provider']);
      expect(tool.category, 'models');
      expect(tool.integration, 'ai');
    });
  });
}

/// Dispatch tests for the `ai_list_models` tool.
void listModelsDispatchTests() {
  group('AiToolExecutor ai_list_models', () {
    test('returns the static model list for gemini', () async {
      final f = mockAiExecutor((_) => '{}');
      final result =
          await f.executor.execute('ai_list_models', {'provider': 'gemini'});
      expect(jsonDecode(result), aiModels['gemini']);
    });

    test('returns the static model list for openai', () async {
      final f = mockAiExecutor((_) => '{}');
      final result =
          await f.executor.execute('ai_list_models', {'provider': 'openai'});
      expect(jsonDecode(result), aiModels['openai']);
    });

    test('makes no HTTP calls', () async {
      final f = mockAiExecutor((_) => '{}');
      await f.executor.execute('ai_list_models', {'provider': 'ollama'});
      expect(f.adapter.calls, isEmpty);
    });

    test('throws ArgumentError for an unknown provider', () {
      final f = mockAiExecutor((_) => '{}');
      expect(
        () => f.executor.execute('ai_list_models', {'provider': 'bedrock'}),
        throwsArgumentError,
      );
    });
  });
}

/// Catalog checks for `ai_generate_image`.
void generateImageCatalogTests() {
  group('ai_generate_image definition', () {
    final tool = aiTools().firstWhere((t) => t.name == 'ai_generate_image');

    test('declares provider, model, prompt', () {
      expect(tool.params.map((p) => p.name), ['provider', 'model', 'prompt']);
      expect(tool.requiredParams, ['provider', 'model', 'prompt']);
      expect(tool.category, 'image');
      expect(tool.integration, 'ai');
    });
  });
}

/// Dispatch tests for the `ai_generate_image` tool.
void generateImageDispatchTests() {
  group('AiToolExecutor ai_generate_image', () {
    test('returns a stub descriptor for openai', () async {
      final f = mockAiExecutor((_) => '{}');
      final result = await f.executor.execute('ai_generate_image', {
        'provider': 'openai',
        'model': 'dall-e-3',
        'prompt': 'a cat',
      });
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], 'stub');
      expect(decoded['provider'], 'openai');
      expect(decoded['model'], 'dall-e-3');
      expect(decoded['prompt'], 'a cat');
    });

    test('makes no HTTP calls', () async {
      final f = mockAiExecutor((_) => '{}');
      await f.executor.execute('ai_generate_image', {
        'provider': 'gemini',
        'model': 'imagen-3',
        'prompt': 'a dog',
      });
      expect(f.adapter.calls, isEmpty);
    });

    test('throws ArgumentError for an unknown provider', () {
      final f = mockAiExecutor((_) => '{}');
      expect(
        () => f.executor.execute('ai_generate_image', {
          'provider': 'unknown',
          'model': 'm',
          'prompt': 'p',
        }),
        throwsArgumentError,
      );
    });
  });
}
