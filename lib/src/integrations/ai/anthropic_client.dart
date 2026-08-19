/// Anthropic (Claude) chat client.
///
/// Ports the Anthropic subset of the Java DMTools `AIClients` /
/// `AnthropicAIClient`: sends a messages POST with an `x-api-key` header and
/// extracts the text from the first content block's text.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';
import 'ai_messages.dart';
import 'ai_request.dart';

/// Anthropic API client for single-turn and multi-turn chat completions.
class AnthropicClient implements AiChatClient {
  final Dio _dio;
  final String _basePath;
  final String _apiKey;
  final int _maxTokens;

  /// Creates a client from [reader]'s Anthropic configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `ANTHROPIC_API_KEY` is missing or empty.
  factory AnthropicClient(PropertyReader reader, {Dio? dio}) =>
      AnthropicClient._(
        dio ?? createDefaultAiDio(),
        reader.getAnthropicBasePath(),
        requiredConfig(reader.getAnthropicApiKey(), 'ANTHROPIC_API_KEY'),
        reader.getAnthropicMaxTokens(),
      );

  AnthropicClient._(this._dio, this._basePath, this._apiKey, this._maxTokens);

  /// Sends a multi-turn chat request built from [messages] and returns the
  /// response text.
  ///
  /// When [systemPrompt] is non-empty it is sent as the top-level `system`
  /// field, per Anthropic's messages API.
  @override
  Future<String> chatWithMessages(
    String model,
    ChatMessages messages, [
    String? systemPrompt,
  ]) =>
      _post(_buildBody(model, messages, systemPrompt, _maxTokens));

  /// Sends a low-level completion with an explicit token cap and temperature.
  ///
  /// A null [temperature] suppresses the field; otherwise it overrides the
  /// configured sampling value.
  @override
  Future<String> complete(
    String model,
    String prompt,
    int maxTokens, [
    double? temperature,
  ]) =>
      _post(_buildBody(
        model,
        userMessages(prompt),
        null,
        maxTokens,
        temperature: temperature,
      ));

  /// Anthropic does not provide an embeddings API.
  @override
  Future<String> embed(String model, String text) =>
      throw UnsupportedError('Anthropic does not provide an embeddings API');

  /// Posts a messages request [body] with the client's auth and headers.
  Future<String> _post(Map<String, dynamic> body) => postChat(
        _dio,
        _basePath,
        body,
        _headers,
        extractContentBlockText,
      );

  /// Auth and content headers sent with every request.
  Map<String, String> get _headers => {
        'x-api-key': _apiKey,
        'Content-Type': 'application/json',
      };

  /// Builds the messages request body.
  Map<String, dynamic> _buildBody(
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens, {
    double? temperature,
  }) {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': messages,
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }
    if (temperature != null) {
      body['temperature'] = temperature;
    }
    return body;
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
