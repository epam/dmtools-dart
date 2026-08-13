/// Test doubles for exercising AI provider clients against canned HTTP
/// responses.
///
/// Provides a [Dio] whose transport ([RoutingAdapter]) answers every request
/// from a per-request router callback and records what was served, plus
/// fixtures that wire real provider clients on top of it with a
/// [PropertyReader] pre-loaded from overrides.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';

/// A mocked provider client plus the [RoutingAdapter] serving its requests.
typedef MockAiFixture<T> = ({T client, RoutingAdapter adapter});

/// A canned-response [HttpClientAdapter] that records each served request.
class RoutingAdapter implements HttpClientAdapter {
  RoutingAdapter(this._router);

  final String Function(RequestOptions options) _router;

  /// Requests served so far, in call order.
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return ResponseBody.fromString(
      _router(options),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The full AI config injected for every fixture built by [mockAi].
///
/// Covers all five providers so any fixture client can be constructed from
/// the same [PropertyReader] overrides.
const _testConfig = {
  'GEMINI_API_KEY': 'gem-key',
  'GEMINI_BASE_PATH': 'https://gemini.example.com/v1beta/models',
  'OPENAI_API_KEY': 'oai-key',
  'OPENAI_BASE_PATH': 'https://openai.example.com/v1/chat/completions',
  'OPENAI_MAX_TOKENS': '1024',
  'OPENAI_TEMPERATURE': '0.5',
  'OLLAMA_BASE_PATH': 'http://ollama.example.com:11434',
  'DIAL_API_KEY': 'dial-key',
  'DIAL_BASE_PATH': 'https://dial.example.com/openai/deployments',
  'ANTHROPIC_API_KEY': 'ant-key',
  'ANTHROPIC_BASE_PATH': 'https://anthropic.example.com/v1/messages',
  'ANTHROPIC_MAX_TOKENS': '2048',
};

/// Builds a mocked AI client of type [T] routed by [router].
///
/// The router maps each incoming [RequestOptions] to the response body the
/// fake server should return; served requests land in `fixture.adapter.calls`.
MockAiFixture<T> mockAi<T>(
  T Function(PropertyReader reader, {Dio? dio}) factoryOf,
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  return (client: factoryOf(PropertyReader(), dio: dio), adapter: adapter);
}

/// Builds a mocked [AiToolExecutor] routed by [router].
///
/// All five provider clients share the same mocked [Dio] so one router
/// serves every request regardless of which provider a call dispatches to.
({AiToolExecutor executor, RoutingAdapter adapter}) mockAiExecutor(
  String Function(RequestOptions options) router,
) {
  PropertyReader.setOverrides(_testConfig);
  final adapter = RoutingAdapter(router);
  final dio = Dio()..httpClientAdapter = adapter;
  final reader = PropertyReader();
  return (
    executor: AiToolExecutor(
      gemini: GeminiClient(reader, dio: dio),
      openai: OpenAIClient(reader, dio: dio),
      ollama: OllamaClient(reader, dio: dio),
      dial: DialClient(reader, dio: dio),
      anthropic: AnthropicClient(reader, dio: dio),
    ),
    adapter: adapter,
  );
}
