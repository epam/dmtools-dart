/// Shared HTTP request/response plumbing for AI provider clients.
///
/// Every provider client ([GeminiClient], [OpenAIClient], [OllamaClient],
/// [DialClient], [AnthropicClient]) routes its POST and response extraction
/// through [postChat] so the common sequence is not duplicated across files
/// and the per-provider classes stay thin. The [AiChatClient] interface
/// defines the chat, completion, and embedding contract each provider
/// implements.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'ai_messages.dart';

/// Contract for an AI provider client.
///
/// Despite the name this interface covers chat, completion, and embedding
/// operations — every provider client implements all three.
abstract interface class AiChatClient {
  /// Sends a multi-turn chat built from [messages] and returns the text.
  Future<String> chatWithMessages(
    String model,
    ChatMessages messages, [
    String? systemPrompt,
  ]);

  /// Sends a low-level single-turn completion of [prompt] with explicit
  /// generation limits: [maxTokens] caps the response length and the optional
  /// [temperature] overrides sampling.
  Future<String> complete(
    String model,
    String prompt,
    int maxTokens, [
    double? temperature,
  ]);

  /// Generates an embedding vector for [text] using [model], returned as a
  /// JSON-encoded array of numbers.
  ///
  /// Providers that do not expose an embeddings API throw [UnsupportedError].
  Future<String> embed(String model, String text);
}

/// Single-turn chat support for every [AiChatClient].
///
/// Defining [AiChatClient.chat] once here — instead of repeating an identical
/// delegator in every provider client — keeps cross-file duplication at zero.
extension AiClientChat on AiChatClient {
  /// Sends a single-turn chat wrapping [prompt] as one user message.
  ///
  /// When [systemPrompt] is non-empty it is forwarded to [chatWithMessages].
  Future<String> chat(String model, String prompt, [String? systemPrompt]) =>
      chatWithMessages(model, userMessages(prompt), systemPrompt);
}

/// Bearer-auth + JSON content-type headers for OpenAI-compatible clients.
Map<String, String> bearerHeaders(String apiKey) => {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

/// Plain JSON content-type headers for clients that authenticate out of band.
Map<String, String> jsonHeaders() => const {'Content-Type': 'application/json'};

/// Returns [value] when non-empty, otherwise throws a [StateError] for [envVar].
String requiredConfig(String? value, String envVar) {
  if (value == null || value.isEmpty) {
    throw StateError('$envVar is not configured');
  }
  return value;
}

/// Posts [body] to [url] and decodes the response text via [extract].
Future<String> postChat(
  Dio dio,
  String url,
  Map<String, dynamic> body,
  Map<String, String> headers,
  String Function(String body) extract,
) async {
  final response = await dio.post<String>(
    url,
    data: jsonEncode(body),
    options: Options(headers: headers),
  );
  return extract(response.data ?? '');
}

/// Returns the first map in `decoded[key]`, or `null` when absent/empty.
Map<String, dynamic>? firstBlock(Map<String, dynamic> decoded, String key) {
  final list = decoded[key] as List? ?? const [];
  return list.isEmpty ? null : list.first as Map<String, dynamic>;
}

/// Extracts `choices[0].message.content` (OpenAI / DIAL).
String extractChoiceContent(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final choice = firstBlock(decoded, 'choices');
  if (choice == null) return '';
  final message = choice['message'] as Map<String, dynamic>? ?? {};
  return message['content'] as String? ?? '';
}

/// Extracts `message.content` (Ollama).
String extractMessageContent(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final message = decoded['message'] as Map<String, dynamic>? ?? {};
  return message['content'] as String? ?? '';
}

/// Extracts `content[0].text` (Anthropic).
String extractContentBlockText(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final block = firstBlock(decoded, 'content');
  return block == null ? '' : block['text'] as String? ?? '';
}

/// Extracts `data[0].embedding` as a JSON array string (OpenAI / DIAL).
String extractEmbeddingArray(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final data = firstBlock(decoded, 'data');
  return data == null ? '[]' : jsonEncode(data['embedding'] ?? const []);
}

/// Extracts `embedding.values` as a JSON array string (Gemini).
String extractValuesEmbedding(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final embedding = decoded['embedding'] as Map<String, dynamic>?;
  return embedding == null ? '[]' : jsonEncode(embedding['values'] ?? const []);
}

/// Extracts the top-level `embedding` array as a JSON string (Ollama).
String extractPlainEmbedding(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  return jsonEncode(decoded['embedding'] ?? const []);
}
