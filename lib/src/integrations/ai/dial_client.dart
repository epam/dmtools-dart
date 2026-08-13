/// DIAL chat client.
///
/// Ports the DIAL subset of the Java DMTools `AIClients` / `DialAIClient`:
/// sends an OpenAI-compatible chat-completions POST with a Bearer API key
/// and extracts the text from the first choice's message content.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';
import 'ai_messages.dart';
import 'ai_request.dart';

/// DIAL API client for single-turn and multi-turn chat completions.
class DialClient implements AiChatClient {
  final Dio _dio;
  final String _basePath;
  final String _apiKey;

  /// Creates a client from [reader]'s DIAL configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `DIAL_API_KEY` or `DIAL_BASE_PATH` is missing.
  factory DialClient(PropertyReader reader, {Dio? dio}) => DialClient._(
        dio ?? createDefaultAiDio(),
        requiredConfig(reader.getDialBathPath(), 'DIAL_BASE_PATH'),
        requiredConfig(reader.getDialIApiKey(), 'DIAL_API_KEY'),
      );

  DialClient._(this._dio, this._basePath, this._apiKey);

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
        {'model': model, 'messages': withSystemMessage(messages, systemPrompt)},
        bearerHeaders(_apiKey),
        extractChoiceContent,
      );

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
