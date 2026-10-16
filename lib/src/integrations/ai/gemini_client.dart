/// Gemini (Google Generative AI) chat client.
///
/// Ports the Gemini subset of the Java DMTools `AIClients` / `GeminiClient`:
/// sends a `generateContent` POST with the API key as a query parameter and
/// extracts the text from the first candidate's first part.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';
import 'ai_messages.dart';
import 'ai_request.dart';

/// Gemini API client for single-turn and multi-turn chat completions.
class GeminiClient implements AiChatClient {
  final Dio _dio;
  final String _basePath;
  final String _apiKey;

  /// Creates a client from [reader]'s Gemini configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `GEMINI_API_KEY` is missing or empty.
  factory GeminiClient(PropertyReader reader, {Dio? dio}) => GeminiClient._(
        dio ?? createDefaultAiDio(),
        reader.getGeminiBasePath(),
        requiredConfig(reader.getGeminiApiKey(), 'GEMINI_API_KEY'),
      );

  GeminiClient._(this._dio, this._basePath, this._apiKey);

  /// Sends a multi-turn chat request built from [messages] and returns the
  /// response text.
  ///
  /// When [systemPrompt] is non-empty it is sent as `systemInstruction`.
  @override
  Future<String> chatWithMessages(
    String model,
    ChatMessages messages, [
    String? systemPrompt,
  ]) =>
      _post(model, _buildBody(messages, systemPrompt));

  /// Sends a low-level completion with an explicit token cap and temperature,
  /// serialized as a Gemini `generationConfig`.
  @override
  Future<String> complete(
    String model,
    String prompt,
    int maxTokens, [
    double? temperature,
  ]) =>
      _post(
        model,
        _buildBody(userMessages(prompt), null)
          ..['generationConfig'] = _generationConfig(maxTokens, temperature),
      );

  /// Posts a `generateContent` [body] for [model] with the client's headers.
  Future<String> _post(String model, Map<String, dynamic> body) => postChat(
        _dio,
        '$_basePath/$model:generateContent?key=$_apiKey',
        body,
        jsonHeaders(),
        extractGeminiText,
      );

  /// Generates an embedding via Gemini's `embedContent` endpoint.
  @override
  Future<String> embed(String model, String text) => postChat(
        _dio,
        '$_basePath/$model:embedContent?key=$_apiKey',
        {
          'content': {
            'parts': [
              {'text': text}
            ]
          }
        },
        jsonHeaders(),
        extractValuesEmbedding,
      );

  /// Builds the `generationConfig` object for an explicit token cap.
  ///
  /// A null [temperature] is omitted; otherwise it is included verbatim.
  Map<String, dynamic> _generationConfig(int maxTokens, double? temperature) {
    final config = <String, dynamic>{'maxOutputTokens': maxTokens};
    if (temperature != null) {
      config['temperature'] = temperature;
    }
    return config;
  }

  /// Builds the `generateContent` request body.
  Map<String, dynamic> _buildBody(
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    final body = <String, dynamic>{
      'contents': messages.map(_toContent).toList(),
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemPrompt},
        ],
      };
    }
    return body;
  }

  /// Maps a `{role, content}` pair to a Gemini `contents` entry.
  ///
  /// The `assistant`/`model` role maps to Gemini's `model`; anything else
  /// maps to `user`.
  static Map<String, dynamic> _toContent(Map<String, String> message) => {
        'role': message['role'] == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': message['content'] ?? ''},
        ],
      };

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
