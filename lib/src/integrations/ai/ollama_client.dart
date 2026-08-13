/// Ollama chat client.
///
/// Ports the Ollama subset of the Java DMTools `AIClients` / `OllamaClient`:
/// sends a non-streaming `/api/chat` POST and extracts the text from the
/// returned `message.content`.
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';
import 'ai_messages.dart';
import 'ai_request.dart';

/// Ollama API client for single-turn and multi-turn chat completions.
class OllamaClient implements AiChatClient {
  final Dio _dio;
  final String _basePath;

  /// Creates a client from [reader]'s Ollama configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  factory OllamaClient(PropertyReader reader, {Dio? dio}) => OllamaClient._(
        dio ?? createDefaultAiDio(),
        reader.getOllamaBasePath(),
      );

  OllamaClient._(this._dio, this._basePath);

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
      _post(_chatBody(model, withSystemMessage(messages, systemPrompt)));

  /// Sends a low-level completion with an explicit token cap and temperature,
  /// serialized under Ollama's `options` object.
  @override
  Future<String> complete(
    String model,
    String prompt,
    int maxTokens, [
    double? temperature,
  ]) =>
      _post(_chatBody(model, userMessages(prompt))
        ..['options'] = _options(maxTokens, temperature));

  /// Posts an `/api/chat` [body] with the client's headers.
  Future<String> _post(Map<String, dynamic> body) => postChat(
        _dio,
        '$_basePath/api/chat',
        body,
        jsonHeaders(),
        extractMessageContent,
      );

  /// Builds the base `/api/chat` body: model, messages, and `stream: false`.
  Map<String, dynamic> _chatBody(
    String model,
    List<Map<String, String>> messages,
  ) =>
      {'model': model, 'messages': messages, 'stream': false};

  /// Builds the Ollama `options` object for an explicit token cap.
  ///
  /// `num_predict` caps the generated length; a null [temperature] is omitted.
  Map<String, dynamic> _options(int maxTokens, double? temperature) {
    final options = <String, dynamic>{'num_predict': maxTokens};
    if (temperature != null) {
      options['temperature'] = temperature;
    }
    return options;
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
