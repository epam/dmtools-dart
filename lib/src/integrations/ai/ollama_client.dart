/// Ollama chat client.
///
/// Ports the Ollama subset of the Java DMTools `AIClients` / `OllamaClient`:
/// sends a non-streaming `/api/chat` POST and extracts the text from the
/// returned `message.content`.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';

/// Ollama API client for single-turn chat completions.
class OllamaClient {
  final Dio _dio;
  final String _basePath;

  /// Creates a client from [reader]'s Ollama configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  factory OllamaClient(PropertyReader reader, {Dio? dio}) {
    return OllamaClient._(
      dio: dio ?? createDefaultAiDio(),
      basePath: reader.getOllamaBasePath(),
    );
  }

  OllamaClient._({
    required Dio dio,
    required String basePath,
  })  : _dio = dio,
        _basePath = basePath;

  /// Sends a single-turn chat request and returns the response text.
  ///
  /// Posts to `{basePath}/api/chat` with `model`, `messages`, and
  /// `stream: false`.
  Future<String> chat(String model, String prompt) async {
    final response = await _dio.post<String>(
      '$_basePath/api/chat',
      data: jsonEncode(_buildBody(model, prompt)),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return _extractText(response.data ?? '');
  }

  /// Builds the `/api/chat` request body with `stream: false`.
  Map<String, dynamic> _buildBody(String model, String prompt) => {
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': false,
      };

  /// Extracts text from `message.content`.
  String _extractText(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final message = decoded['message'] as Map<String, dynamic>? ?? {};
    return message['content'] as String? ?? '';
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
