/// OpenAI (and compatible) chat client.
///
/// Ports the OpenAI subset of the Java DMTools `AIClients` / `OpenAIClient`:
/// sends a chat-completions POST with a `Bearer` API key and extracts the
/// text from the first choice's message content.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';

/// OpenAI API client for single-turn chat completions.
class OpenAIClient {
  final Dio _dio;
  final String _basePath;
  final String _apiKey;
  final int _maxTokens;
  final double _temperature;
  final String _maxTokensParamName;

  /// Creates a client from [reader]'s OpenAI configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `OPENAI_API_KEY` is missing or empty.
  factory OpenAIClient(PropertyReader reader, {Dio? dio}) {
    final apiKey = reader.getOpenAIApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY is not configured');
    }
    return OpenAIClient._(
      dio: dio ?? createDefaultAiDio(),
      basePath: reader.getOpenAIBasePath(),
      apiKey: apiKey,
      maxTokens: reader.getOpenAIMaxTokens(),
      temperature: reader.getOpenAITemperature(),
      maxTokensParamName: reader.getOpenAIMaxTokensParamName(),
    );
  }

  OpenAIClient._({
    required Dio dio,
    required String basePath,
    required String apiKey,
    required int maxTokens,
    required double temperature,
    required String maxTokensParamName,
  })  : _dio = dio,
        _basePath = basePath,
        _apiKey = apiKey,
        _maxTokens = maxTokens,
        _temperature = temperature,
        _maxTokensParamName = maxTokensParamName;

  /// Sends a single-turn chat request and returns the response text.
  ///
  /// Posts to [basePath] with a body containing `model`, `messages` (built
  /// from [systemPrompt] and [prompt]), and max-tokens/temperature fields.
  Future<String> chat(
    String model,
    String prompt, [
    String? systemPrompt,
  ]) async {
    final response = await _dio.post<String>(
      _basePath,
      data: jsonEncode(_buildBody(model, prompt, systemPrompt)),
      options: Options(headers: _headers),
    );
    return _extractText(response.data ?? '');
  }

  /// Auth and content headers sent with every request.
  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };

  /// Builds the chat-completions request body.
  ///
  /// A negative [_temperature] (the default `-1`) suppresses the field, and
  /// the max-tokens key uses the configured param name
  /// (default `max_completion_tokens`).
  Map<String, dynamic> _buildBody(
    String model,
    String prompt,
    String? systemPrompt,
  ) {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': prompt});
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      _maxTokensParamName: _maxTokens,
    };
    if (_temperature >= 0) {
      body['temperature'] = _temperature;
    }
    return body;
  }

  /// Extracts text from `choices[0].message.content`.
  ///
  /// Returns an empty string when the response has no choices.
  String _extractText(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List? ?? const [];
    if (choices.isEmpty) return '';
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>? ?? {};
    return message['content'] as String? ?? '';
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
