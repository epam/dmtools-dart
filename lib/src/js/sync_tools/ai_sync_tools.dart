/// Synchronous per-provider AI chat tool executors for the JS tool bridge.
///
/// Java DMTools exposes one @MCPTool per AI provider — `gemini_ai_chat`,
/// `openai_ai_chat`, `anthropic_ai_chat`, `ollama_ai_chat`, `dial_ai_chat`,
/// `bedrock_ai_chat` — and the dmtools-agents `aiChat.js` helper resolves
/// them dynamically (`globalThis[provider + '_ai_chat']`), falling through
/// to the next provider when one throws. The generic `ai_chat` tool cannot
/// satisfy that lookup, so notifyBugMerged.js and every other AI-calling
/// agent script needs these per-provider executors.
///
/// Each executor resolves provider config from [PropertyReader] (the same
/// keys and defaults the async clients use), issues a NON-streaming chat
/// request through [SyncHttpClient] (curl subprocess — safe inside
/// NativeCallable callbacks where the Dart event loop is frozen), and
/// returns the extracted response text as a plain string, exactly what the
/// Java `chat(message)` tools return.
///
/// Error contract: unlike the jira/github sync tools, which return
/// `{"error": …}` JSON, these executors return a `{"__jsError": …}`
/// sentinel on failure (provider not configured, transport failure,
/// non-2xx response, unparseable body). The JS bridge bootstrap rethrows
/// that sentinel as a real JS `Error`, matching how the Java bridge
/// propagates tool exceptions — and what `aiChat.js` needs to fall through
/// to the next provider instead of treating an error payload as a
/// successful chat result.
///
/// Deviations from Java (recorded per AGENTS.md rule 2):
/// - The default model falls back to the first [aiModels] catalog entry
///   when the provider model env var is unset (Java would send `null` and
///   fail at the API); Bedrock still requires `BEDROCK_MODEL_ID`, matching
///   Java `isBedrockConfigured`.
/// - Bedrock supports bearer-token auth only; IAM SigV4 signing (Java
///   `IAMKeysAuthenticationStrategy` / default credentials chain) has no
///   sync-port equivalent.
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_ai_getters.dart';
import '../../integrations/ai/ai_request.dart'
    show
        bearerHeaders,
        extractChoiceContent,
        extractContentBlockText,
        extractGeminiText,
        extractMessageContent,
        firstBlock,
        jsonHeaders;
import '../../integrations/ai/ai_tools.dart' show aiModels;
import '../sync_http_client.dart';

/// Bedrock model families, each with its own wire envelope.
enum BedrockModelType { claude, nova, qwen, mistral }

/// Classifies a Bedrock model ID into its wire-format family.
///
/// Mirrors Java `BedrockAIClient.detectModelType`: `claude`/`anthropic` →
/// [BedrockModelType.claude], `nova` → nova, `qwen` → qwen, `mistral` →
/// mistral; anything else (including a null id) defaults to claude, the
/// most common envelope.
BedrockModelType detectBedrockModelType(String? modelId) {
  final id = (modelId ?? '').toLowerCase();
  if (id.contains('claude') || id.contains('anthropic')) {
    return BedrockModelType.claude;
  }
  if (id.contains('nova')) return BedrockModelType.nova;
  if (id.contains('qwen')) return BedrockModelType.qwen;
  if (id.contains('mistral')) return BedrockModelType.mistral;
  return BedrockModelType.claude;
}

/// URL path segment for a Bedrock [modelId].
///
/// Mirrors Java `performChatCompletion`: plain model IDs (including `:`
/// version suffixes) ride the path unencoded; only inference-profile ARNs
/// are percent-encoded (Dart's [Uri.encodeComponent] already emits `%20`
/// for spaces, so no `+` fixup is needed).
String bedrockModelPath(String modelId) =>
    modelId.contains('inference-profile/')
        ? Uri.encodeComponent(modelId)
        : modelId;

/// Builds the Bedrock invoke request body for [type].
///
/// Mirrors Java `buildRequestBody`: Claude adds `anthropic_version` and a
/// block-array `content`; Nova wraps limits in `inferenceConfig` with
/// `schemaVersion`; Qwen and Mistral use the plain OpenAI-style envelope.
Map<String, dynamic> bedrockRequestBody(
  BedrockModelType type,
  String message,
  int maxTokens,
  double temperature,
) {
  switch (type) {
    case BedrockModelType.claude:
      return {
        'anthropic_version': 'bedrock-2023-05-31',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': message},
            ],
          },
        ],
        'max_tokens': maxTokens,
        'temperature': temperature,
      };
    case BedrockModelType.nova:
      return {
        'schemaVersion': 'messages-v1',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'text': message},
            ],
          },
        ],
        'inferenceConfig': {
          'maxTokens': maxTokens,
          'temperature': temperature,
          'topP': 0.9,
          'stopSequences': <String>[],
        },
      };
    case BedrockModelType.qwen:
    case BedrockModelType.mistral:
      return {
        'messages': [
          {'role': 'user', 'content': message},
        ],
        'max_tokens': maxTokens,
        'temperature': temperature,
      };
  }
}

/// Extracts the assistant text from a Bedrock response for [type].
///
/// Mirrors Java `processResponse`: Claude reads `content[0].text`, Nova
/// `output.message.content[0].text`, Qwen/Mistral
/// `choices[0].message.content` (falling back to `output.choices`). Bodies
/// carrying a provider error shape (`error`, `__type`, `message`, or
/// `Output.__type`) are returned verbatim so callers see the raw error,
/// exactly like Java.
String extractBedrockText(String body, BedrockModelType type) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return '';
  if (_isBedrockError(decoded)) return body;
  switch (type) {
    case BedrockModelType.claude:
      return extractContentBlockText(body);
    case BedrockModelType.nova:
      final output = decoded['output'] as Map<String, dynamic>? ?? {};
      final message = output['message'] as Map<String, dynamic>? ?? {};
      final block = firstBlock(message, 'content');
      return block == null ? '' : block['text'] as String? ?? '';
    case BedrockModelType.qwen:
    case BedrockModelType.mistral:
      return _extractBedrockChoiceText(decoded);
  }
}

/// Whether [decoded] matches a Bedrock error envelope (Java parity).
bool _isBedrockError(Map<String, dynamic> decoded) {
  final output = decoded['Output'];
  if (output is Map<String, dynamic> && output['__type'] != null) return true;
  return decoded['error'] != null ||
      decoded['__type'] != null ||
      decoded['message'] != null;
}

/// Extracts `choices[0].message.content`, falling back to `output.choices`.
String _extractBedrockChoiceText(Map<String, dynamic> decoded) {
  var choices = decoded['choices'] as List?;
  if (choices == null) {
    final output = decoded['output'] as Map<String, dynamic>? ?? {};
    choices = output['choices'] as List?;
  }
  if (choices == null || choices.isEmpty) return '';
  final choice = choices.first as Map<String, dynamic>;
  final message = choice['message'] as Map<String, dynamic>? ?? {};
  return message['content'] as String? ?? '';
}

/// Executes the per-provider `*_ai_chat` MCP tools synchronously.
///
/// Wired into [SyncToolDispatcher] routing by the tool bridge; each
/// executor resolves its provider config lazily on every call so env
/// changes between jobs take effect without rebuilding the dispatcher.
class AiSyncTools {
  final PropertyReader _reader;

  /// Creates AI tooling reading provider config from [reader].
  AiSyncTools(this._reader);

  /// Per-provider chat executors keyed by Java @MCPTool name.
  ///
  /// The keys match [aiChatTools] 1:1 so the generated JS wrapper globals
  /// (`globalThis.gemini_ai_chat`, …) dispatch to these executors.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'gemini_ai_chat': _geminiAiChat,
        'openai_ai_chat': _openaiAiChat,
        'anthropic_ai_chat': _anthropicAiChat,
        'ollama_ai_chat': _ollamaAiChat,
        'dial_ai_chat': _dialAiChat,
        'bedrock_ai_chat': _bedrockAiChat,
      };

  /// `gemini_ai_chat` — POST `{base}/{model}:generateContent?key={key}`.
  ///
  /// Auth rides the query string (no header), mirroring [GeminiClient].
  String _geminiAiChat(Map<String, dynamic> args) {
    final apiKey = _reader.getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return _jsError('Gemini is not configured (GEMINI_API_KEY)');
    }
    final model = _reader.getGeminiDefaultModel() ?? _defaultModel('gemini');
    final url = '${_reader.getGeminiBasePath()}/$model:generateContent'
        '?key=${Uri.encodeQueryComponent(apiKey)}';
    return _postChat(
      url,
      jsonHeaders(),
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': _message(args)},
            ],
          },
        ],
      },
      extractGeminiText,
    );
  }

  /// `openai_ai_chat` — POST to the configured chat-completions endpoint.
  ///
  /// Body shape mirrors [OpenAIClient]: configured max-tokens param name,
  /// temperature only when non-negative.
  String _openaiAiChat(Map<String, dynamic> args) {
    final apiKey = _reader.getOpenAIApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return _jsError('OpenAI is not configured (OPENAI_API_KEY)');
    }
    final body = <String, dynamic>{
      'model': _reader.getOpenAIModel() ?? _defaultModel('openai'),
      'messages': [_userMessage(_message(args))],
      _reader.getOpenAIMaxTokensParamName(): _reader.getOpenAIMaxTokens(),
    };
    final temperature = _reader.getOpenAITemperature();
    if (temperature >= 0) body['temperature'] = temperature;
    return _postChat(
      _reader.getOpenAIBasePath(),
      bearerHeaders(apiKey),
      body,
      extractChoiceContent,
    );
  }

  /// `anthropic_ai_chat` — POST to the configured messages endpoint.
  ///
  /// Body shape mirrors [AnthropicClient]: `x-api-key` auth, plain-string
  /// message content, mandatory `max_tokens`.
  String _anthropicAiChat(Map<String, dynamic> args) {
    final apiKey = _reader.getAnthropicApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return _jsError('Anthropic is not configured (ANTHROPIC_API_KEY)');
    }
    return _postChat(
      _reader.getAnthropicBasePath(),
      {...jsonHeaders(), 'x-api-key': apiKey},
      {
        'model': _reader.getAnthropicModel() ?? _defaultModel('anthropic'),
        'max_tokens': _reader.getAnthropicMaxTokens(),
        'messages': [_userMessage(_message(args))],
      },
      extractContentBlockText,
    );
  }

  /// `ollama_ai_chat` — POST `{base}/api/chat` with `stream: false`.
  ///
  /// Ollama is local and unauthenticated, so it is always configured; the
  /// base path defaults to `http://localhost:11434`.
  String _ollamaAiChat(Map<String, dynamic> args) {
    return _postChat(
      '${_reader.getOllamaBasePath()}/api/chat',
      jsonHeaders(),
      {
        'model': _reader.getOllamaModel() ?? _defaultModel('ollama'),
        'messages': [_userMessage(_message(args))],
        'stream': false,
      },
      extractMessageContent,
    );
  }

  /// `dial_ai_chat` — POST to the configured DIAL endpoint.
  ///
  /// Body shape mirrors [DialClient]: model + messages only (no explicit
  /// token cap on the plain chat path).
  String _dialAiChat(Map<String, dynamic> args) {
    final basePath = _reader.getDialBathPath();
    if (basePath == null || basePath.isEmpty) {
      return _jsError('Dial is not configured (DIAL_BASE_PATH)');
    }
    final apiKey = _reader.getDialIApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return _jsError('Dial is not configured (DIAL_API_KEY)');
    }
    return _postChat(
      basePath,
      bearerHeaders(apiKey),
      {
        'model': _reader.getDialModel() ?? _defaultModel('dial'),
        'messages': [_userMessage(_message(args))],
      },
      extractChoiceContent,
    );
  }

  /// `bedrock_ai_chat` — POST `{base}/model/{id}/invoke` with the model
  /// family's envelope ([bedrockRequestBody]) and bearer auth.
  ///
  /// Requires `BEDROCK_MODEL_ID` (Java `isBedrockConfigured` parity) plus a
  /// bearer token; IAM SigV4 is out of scope for the sync path.
  String _bedrockAiChat(Map<String, dynamic> args) {
    final modelId = _reader.getBedrockModelId();
    if (modelId == null || modelId.isEmpty) {
      return _jsError('Bedrock is not configured (BEDROCK_MODEL_ID)');
    }
    final token = _reader.getBedrockBearerToken();
    if (token == null || token.isEmpty) {
      return _jsError(
        'Bedrock sync tools require AWS_BEARER_TOKEN_BEDROCK or '
        'BEDROCK_BEARER_TOKEN (IAM SigV4 signing is unsupported)',
      );
    }
    final basePath = _reader.getBedrockBasePath();
    if (basePath == null || basePath.isEmpty) {
      return _jsError(
        'Bedrock is not configured (BEDROCK_BASE_PATH or BEDROCK_REGION)',
      );
    }
    final type = detectBedrockModelType(modelId);
    return _postChat(
      '$basePath/model/${bedrockModelPath(modelId)}/invoke',
      {...jsonHeaders(), 'Authorization': 'Bearer $token'},
      bedrockRequestBody(
        type,
        _message(args),
        _reader.getBedrockMaxTokens(),
        _reader.getBedrockTemperature(),
      ),
      (body) => extractBedrockText(body, type),
    );
  }

  /// First entry of the static [aiModels] catalog for [provider].
  ///
  /// Used when the provider model env var is unset — see the library docs
  /// for the deviation note.
  static String _defaultModel(String provider) => aiModels[provider]!.first;

  /// POSTs [body] to [url] and returns the extracted response text.
  ///
  /// Transport failures (curl error, non-2xx) and parse failures surface as
  /// the `__jsError` sentinel so the JS bridge throws — see the library
  /// docs for why these tools deviate from the `{"error": …}` convention.
  String _postChat(
    String url,
    Map<String, String> headers,
    Map<String, dynamic> body,
    String Function(String body) extract,
  ) {
    final resp = SyncHttpClient.post(
      url,
      headers: headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode == 0) {
      return _jsError('AI request failed: ${resp.body}');
    }
    if (!resp.isOk) {
      return _jsError(
        'AI provider returned HTTP ${resp.statusCode}: ${resp.body}',
      );
    }
    return _extractOrSentinel(resp.body, extract);
  }

  /// Runs [extract], converting parse failures into the JS error sentinel.
  static String _extractOrSentinel(
    String body,
    String Function(String body) extract,
  ) {
    try {
      return extract(body);
    } catch (e) {
      return _jsError('AI response parse failed: $e');
    }
  }

  /// Wraps [message] as an OpenAI-style `{role, content}` user message.
  static Map<String, String> _userMessage(String message) =>
      {'role': 'user', 'content': message};

  /// Reads the `message` tool argument.
  static String _message(Map<String, dynamic> args) =>
      args['message']?.toString() ?? '';

  /// Encodes the JS error sentinel (rethrown as a JS `Error` by the bridge).
  static String _jsError(String message) => jsonEncode({'__jsError': message});
}
