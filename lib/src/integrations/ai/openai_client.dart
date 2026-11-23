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
  Map<String, dynamic>? _extraBody;

  /// Creates a client from [reader]'s OpenAI configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `OPENAI_API_KEY` is missing or empty, or
  /// [ArgumentError] when `OPENAI_EXTRA_BODY` is not a valid JSON object.
  factory OpenAIClient(PropertyReader reader, {Dio? dio}) => OpenAIClient._(
        dio ?? createDefaultAiDio(),
        reader.getOpenAIBasePath(),
        requiredConfig(reader.getOpenAIApiKey(), 'OPENAI_API_KEY'),
        reader.getOpenAIMaxTokens(),
        reader.getOpenAITemperature(),
        reader.getOpenAIMaxTokensParamName(),
        reader.getOpenAIExtraBody(),
      );

  OpenAIClient._(
    this._dio,
    this._basePath,
    this._apiKey,
    this._maxTokens,
    this._temperature,
    this._maxTokensParamName,
    String? extraBodyJson,
  ) {
    setExtraBody(extraBodyJson);
  }

  /// Parses [extraBodyJson] as a JSON object; returns `null` when unset,
  /// blank, or an unresolved `$` placeholder, or throws [ArgumentError]
  /// when the value is not a JSON object (Java `OpenAIClient.setExtraBody`).
  static Map<String, dynamic>? parseExtraBody(String? extraBodyJson) {
    final trimmed = extraBodyJson?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.startsWith(r'$')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return jsonDecode(jsonEncode(decoded)) as Map<String, dynamic>;
      }
    } on FormatException catch (e) {
      throw ArgumentError('OPENAI_EXTRA_BODY must be a JSON object: $e');
    }
    throw ArgumentError('OPENAI_EXTRA_BODY must be a JSON object');
  }

  /// Merges [extraBody] fields into [body], skipping `model` and `messages`
  /// (Java `OpenAIClient.performChatCompletion` parity).
  static void mergeExtraBody(
    Map<String, dynamic> body,
    Map<String, dynamic>? extraBody,
  ) {
    if (extraBody == null) return;
    for (final entry in extraBody.entries) {
      if (entry.key == 'model' || entry.key == 'messages') continue;
      body[entry.key] = jsonDecode(jsonEncode(entry.value));
    }
  }

  /// Sets extra fields merged into every chat request body, overriding
  /// temperature and the max-tokens field (`model` and `messages` cannot
  /// be overridden).
  void setExtraBody(String? extraBodyJson) {
    _extraBody = parseExtraBody(extraBodyJson);
  }

  /// Defensive copy of the configured extra body, or `null` when unset.
  Map<String, dynamic>? get extraBody => _extraBody == null
      ? null
      : jsonDecode(jsonEncode(_extraBody)) as Map<String, dynamic>;

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
      _post(
          _buildBody(model, messages, systemPrompt, _maxTokens, _temperature));

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
        temperature ?? -1,
      ));

  /// Generates an embedding via the OpenAI embeddings endpoint.
  @override
  Future<String> embed(String model, String text) => postChat(
        _dio,
        _embeddingsUrl(),
        {'model': model, 'input': text},
        bearerHeaders(_apiKey),
        extractEmbeddingArray,
      );

  /// Derives the embeddings endpoint from the configured chat-completions path.
  String _embeddingsUrl() =>
      _basePath.replaceAll('chat/completions', 'embeddings');

  /// Posts a chat-completions [body] with the client's auth and headers.
  Future<String> _post(Map<String, dynamic> body) => postChat(
      _dio, _basePath, body, bearerHeaders(_apiKey), extractChoiceContent);

  /// Builds the chat-completions request body.
  ///
  /// A negative [temperature] (the default `-1`) suppresses the field, and
  /// the max-tokens key uses the configured param name
  /// (default `max_completion_tokens`).
  Map<String, dynamic> _buildBody(
    String model,
    List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens,
    double temperature,
  ) {
    final body = <String, dynamic>{
      'model': model,
      'messages': withSystemMessage(messages, systemPrompt),
      if (_maxTokensParamName.trim().isNotEmpty)
        _maxTokensParamName.trim(): maxTokens,
    };
    if (temperature >= 0) {
      body['temperature'] = temperature;
    }
    mergeExtraBody(body, _extraBody);
    return body;
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
