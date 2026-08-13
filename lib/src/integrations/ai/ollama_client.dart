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
      postChat(
        _dio,
        '$_basePath/api/chat',
        {
          'model': model,
          'messages': withSystemMessage(messages, systemPrompt),
          'stream': false,
        },
        jsonHeaders(),
        extractMessageContent,
      );

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
