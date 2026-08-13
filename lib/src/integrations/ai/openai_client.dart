/// OpenAI (and compatible) chat client.
///
/// Ports the OpenAI subset of the Java DMTools `AIClients` / `OpenAIClient`:
/// sends a chat-completions POST with a `Bearer` API key and extracts the
/// text from the first choice's message content.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';
import 'ai_messages.dart';
import 'ai_request.dart';

/// OpenAI API client for single-turn and multi-turn chat completions.
class OpenAIClient implements AiChatClient {
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
  factory OpenAIClient(PropertyReader reader, {Dio? dio}) => OpenAIClient._(
        dio ?? createDefaultAiDio(),
        reader.getOpenAIBasePath(),
        requiredConfig(reader.getOpenAIApiKey(), 'OPENAI_API_KEY'),
        reader.getOpenAIMaxTokens(),
        reader.getOpenAITemperature(),
        reader.getOpenAIMaxTokensParamName(),
      );

  OpenAIClient._(
    this._dio,
    this._basePath,
    this._apiKey,
    this._maxTokens,
    this._temperature,
    this._maxTokensParamName,
  );

  /// Sends a multi-turn chat request built from [messages] and returns the
  /// response text.
  ///
  /// When [systemPrompt] is non-empty it is prepended as a `system` message.
  @override
  Future<String> chatWithMessages(
    String model,
    ChatMessages messages, [
    String? systemPrompt,
  ]) =>
      postChat(
        _dio,
        _basePath,
        _buildBody(model, messages, systemPrompt),
        bearerHeaders(_apiKey),
        extractChoiceContent,
      );

  /// Builds the chat-completions request body.
  ///
  /// A negative [_temperature] (the default `-1`) suppresses the field, and
  /// the max-tokens key uses the configured param name
  /// (default `max_completion_tokens`).
  Map<String, dynamic> _buildBody(
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
  ) {
    final body = <String, dynamic>{
      'model': model,
      'messages': withSystemMessage(messages, systemPrompt),
      _maxTokensParamName: _maxTokens,
    };
    if (_temperature >= 0) {
      body['temperature'] = _temperature;
    }
    return body;
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
