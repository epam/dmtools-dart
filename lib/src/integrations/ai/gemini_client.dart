/// Gemini (Google Generative AI) chat client.
///
/// Ports the Gemini subset of the Java DMTools `AIClients` / `GeminiClient`:
/// sends a `generateContent` POST with the API key as a query parameter and
/// extracts the text from the first candidate's first part.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import 'ai_http.dart';

/// Gemini API client for single-turn chat completions.
class GeminiClient {
  final Dio _dio;
  final String _basePath;
  final String _apiKey;

  /// Creates a client from [reader]'s Gemini configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `GEMINI_API_KEY` is missing or empty.
  factory GeminiClient(PropertyReader reader, {Dio? dio}) {
    final apiKey = reader.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY is not configured');
    }
    return GeminiClient._(
      dio: dio ?? createDefaultAiDio(),
      basePath: reader.getGeminiBasePath(),
      apiKey: apiKey,
    );
  }

  GeminiClient._({
    required Dio dio,
    required String basePath,
    required String apiKey,
  })  : _dio = dio,
        _basePath = basePath,
        _apiKey = apiKey;

  /// Sends a single-turn chat request and returns the response text.
  ///
  /// Targets `{basePath}/{model}:generateContent?key={apiKey}`. When
  /// [systemPrompt] is provided it is sent as `systemInstruction`.
  Future<String> chat(
    String model,
    String prompt, [
    String? systemPrompt,
  ]) async {
    final url = '$_basePath/$model:generateContent?key=$_apiKey';
    final response = await _dio.post<String>(
      url,
      data: jsonEncode(_buildBody(prompt, systemPrompt)),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return _extractText(response.data ?? '');
  }

  /// Builds the `generateContent` request body.
  Map<String, dynamic> _buildBody(String prompt, String? systemPrompt) {
    final body = <String, dynamic>{
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
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

  /// Extracts text from `candidates[0].content.parts[0].text`.
  ///
  /// Returns an empty string when the response has no candidates or parts.
  String _extractText(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return '';
    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>? ?? {};
    final parts = content['parts'] as List? ?? const [];
    if (parts.isEmpty) return '';
    return (parts.first as Map<String, dynamic>)['text'] as String? ?? '';
  }

  /// Closes the underlying HTTP client and frees its connections.
  void close() => _dio.close();
}
