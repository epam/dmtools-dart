/// MCP tool definitions and dispatcher for the AI integration.
///
/// The tool list ports the AI subset of the Java `@MCPTool` catalog: the
/// provider-parameterized tools (`ai_chat`, …) plus the per-provider
/// `*_ai_chat` tools ([aiChatTools]) that mirror the Java clients 1:1. The
/// executor routes a tool name + arguments to the matching provider client
/// ([GeminiClient], [OpenAIClient], [OllamaClient], [DialClient], or
/// [AnthropicClient]); the per-provider tools execute synchronously in the
/// JS bridge via `AiSyncTools`.
library;

import 'dart:convert';

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'ai_request.dart';
import 'anthropic_client.dart';
import 'dial_client.dart';
import 'gemini_client.dart';
import 'ollama_client.dart';
import 'openai_client.dart';

/// Supported AI provider identifiers.
const aiProviders = {'gemini', 'openai', 'ollama', 'dial', 'anthropic'};

/// Static model catalog per provider, served by `ai_list_models`.
///
/// Intentionally static (no API call): it mirrors the well-known model names
/// each provider exposes so agents can pick a model without probing.
const Map<String, List<String>> aiModels = {
  'gemini': ['gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-2.0-flash'],
  'openai': ['gpt-3.5-turbo', 'gpt-4', 'gpt-4o', 'gpt-4o-mini'],
  'ollama': ['llama2', 'llama3', 'mistral'],
  'dial': ['gpt-3.5-turbo', 'gpt-4'],
  'anthropic': ['claude-3-haiku', 'claude-3-opus', 'claude-3-sonnet'],
};

/// Returns all AI MCP tool definitions.
List<ToolDefinition> aiTools() => [
      _aiChatTool(),
      ...aiChatTools(),
      _aiChatWithHistoryTool(),
      _aiChatWithSystemPromptTool(),
      _aiCompleteTool(),
      _aiEmbedTool(),
      _aiSummarizeTool(),
      _aiListModelsTool(),
      _aiGenerateImageTool(),
    ];

/// Returns the per-provider chat tool definitions: `<provider>_ai_chat`.
///
/// Java exposes one @MCPTool per provider (`GeminiJSAIClient.chat` →
/// `gemini_ai_chat`, `OpenAIClient.chat` → `openai_ai_chat`, …, for
/// gemini/openai/anthropic/ollama/dial/bedrock) and the dmtools-agents
/// `aiChat.js` helper resolves `globalThis[provider + '_ai_chat']`
/// dynamically, falling through to the next provider when a global is
/// missing. The generic `ai_chat` tool cannot satisfy that lookup, so the
/// catalog mirrors the Java per-provider names 1:1.
List<ToolDefinition> aiChatTools() => [
      _providerAiChatTool(
        'gemini_ai_chat',
        'Send a text message to Gemini AI and get response',
      ),
      _providerAiChatTool(
        'openai_ai_chat',
        'Send a text message to OpenAI and get response',
      ),
      _providerAiChatTool(
        'anthropic_ai_chat',
        'Send a text message to Anthropic Claude AI and get response',
      ),
      _providerAiChatTool(
        'ollama_ai_chat',
        'Send a text message to Ollama AI and get response',
      ),
      _providerAiChatTool(
        'dial_ai_chat',
        'Send a text message to Dial AI and get response',
      ),
      _providerAiChatTool(
        'bedrock_ai_chat',
        'Send a text message to AWS Bedrock AI and get response',
      ),
    ];

/// Builds one per-provider `*_ai_chat` tool definition.
///
/// All six Java provider tools share the same shape: a single required
/// `message` string (`@MCPParam(name = "message")` in every Java client).
ToolDefinition _providerAiChatTool(String name, String description) =>
    ToolDefinition(
      name: name,
      description: description,
      integration: 'ai',
      category: 'chat',
      params: [
        ToolParam(
          name: 'message',
          description: 'Text message to send to AI',
        ),
      ],
    );

/// Single-turn chat tool: `ai_chat`.
ToolDefinition _aiChatTool() => ToolDefinition(
      name: 'ai_chat',
      description: 'Send a single-turn chat prompt to an AI provider '
          '(gemini, openai, ollama, dial, or anthropic) and return the '
          'response text',
      integration: 'ai',
      category: 'chat',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
        ToolParam(
          name: 'model',
          description: 'The model name to use (e.g. gemini-1.5-flash)',
        ),
        ToolParam(
          name: 'prompt',
          description: 'The user prompt text',
        ),
        ToolParam(
          name: 'system_prompt',
          description: 'Optional system prompt (gemini, openai only)',
          required: false,
        ),
      ],
    );

/// Multi-turn chat tool: `ai_chat_with_history`.
ToolDefinition _aiChatWithHistoryTool() => ToolDefinition(
      name: 'ai_chat_with_history',
      description: 'Send a multi-turn chat with a message history to an AI '
          'provider (gemini, openai, ollama, dial, or anthropic) and return '
          'the response text',
      integration: 'ai',
      category: 'chat',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
        ToolParam(
          name: 'model',
          description: 'The model name to use',
        ),
        ToolParam(
          name: 'messages',
          description: 'Array of {role, content} message pairs',
          type: 'array',
        ),
        ToolParam(
          name: 'system_prompt',
          description: 'Optional system prompt',
          required: false,
        ),
      ],
    );

/// Single-turn chat tool that always separates the system prompt:
/// `ai_chat_with_system_prompt`.
///
/// Unlike [ai_chat], where the system prompt applies only to gemini and
/// openai, this tool forwards the system prompt to every provider.
ToolDefinition _aiChatWithSystemPromptTool() => ToolDefinition(
      name: 'ai_chat_with_system_prompt',
      description: 'Send a single-turn chat prompt with an explicit system '
          'prompt to an AI provider (gemini, openai, ollama, dial, or '
          'anthropic); the system prompt is always separated and applied '
          'for every provider',
      integration: 'ai',
      category: 'chat',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
        ToolParam(
          name: 'model',
          description: 'The model name to use (e.g. gpt-4)',
        ),
        ToolParam(
          name: 'prompt',
          description: 'The user prompt text',
        ),
        ToolParam(
          name: 'system_prompt',
          description: 'The system prompt; always separated and applied',
        ),
      ],
    );

/// Low-level completion tool: `ai_complete`.
ToolDefinition _aiCompleteTool() => ToolDefinition(
      name: 'ai_complete',
      description: 'Send a low-level single-turn completion to an AI provider '
          '(gemini, openai, ollama, dial, or anthropic) with explicit control '
          'over the response token limit and temperature',
      integration: 'ai',
      category: 'completion',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
        ToolParam(
          name: 'model',
          description: 'The model name to use',
        ),
        ToolParam(
          name: 'prompt',
          description: 'The prompt text',
        ),
        ToolParam(
          name: 'max_tokens',
          description: 'Maximum number of tokens to generate',
          type: 'number',
        ),
        ToolParam(
          name: 'temperature',
          description: 'Optional sampling temperature (0.0-2.0)',
          required: false,
          type: 'number',
        ),
      ],
    );

/// Embedding tool: `ai_embed`.
ToolDefinition _aiEmbedTool() => ToolDefinition(
      name: 'ai_embed',
      description: 'Generate an embedding vector for text using an AI provider '
          '(gemini, openai, ollama, or dial) and return the vector as a JSON '
          'array of numbers',
      integration: 'ai',
      category: 'embedding',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, or dial (anthropic is '
              'not supported)',
        ),
        ToolParam(
          name: 'model',
          description: 'The embedding model name (e.g. text-embedding-3-small)',
        ),
        ToolParam(
          name: 'text',
          description: 'The text to embed',
        ),
      ],
    );

/// Summarization tool: `ai_summarize`.
ToolDefinition _aiSummarizeTool() => ToolDefinition(
      name: 'ai_summarize',
      description: 'Summarize text using an AI provider (gemini, openai, '
          'ollama, dial, or anthropic) and return the summary',
      integration: 'ai',
      category: 'summarize',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
        ToolParam(
          name: 'model',
          description: 'The model name to use',
        ),
        ToolParam(
          name: 'text',
          description: 'The text to summarize',
        ),
      ],
    );

/// Model-catalog tool: `ai_list_models`.
ToolDefinition _aiListModelsTool() => ToolDefinition(
      name: 'ai_list_models',
      description: 'List available models for an AI provider (gemini, openai, '
          'ollama, dial, or anthropic) from a static catalog; no API call',
      integration: 'ai',
      category: 'models',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
      ],
    );

/// Image-generation stub tool: `ai_generate_image`.
ToolDefinition _aiGenerateImageTool() => ToolDefinition(
      name: 'ai_generate_image',
      description: 'Generate an image from a text prompt using an AI provider '
          '(stub — returns a placeholder descriptor, no image is produced)',
      integration: 'ai',
      category: 'image',
      params: [
        ToolParam(
          name: 'provider',
          description:
              'AI provider: gemini, openai, ollama, dial, or anthropic',
        ),
        ToolParam(name: 'model', description: 'The image model name to use'),
        ToolParam(name: 'prompt', description: 'The text prompt for the image'),
      ],
    );

/// Executes AI MCP tools by dispatching to the appropriate provider client.
class AiToolExecutor {
  final GeminiClient _gemini;
  final OpenAIClient _openai;
  final OllamaClient _ollama;
  final DialClient _dial;
  final AnthropicClient _anthropic;

  /// Creates an executor bound to the five provider clients.
  AiToolExecutor({
    required GeminiClient gemini,
    required OpenAIClient openai,
    required OllamaClient ollama,
    required DialClient dial,
    required AnthropicClient anthropic,
  })  : _gemini = gemini,
        _openai = openai,
        _ollama = ollama,
        _dial = dial,
        _anthropic = anthropic;

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown AI tool name.
  Future<String> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown AI tool: $toolName');
    }
    return handler(args);
  }

  late final Map<String, Future<String> Function(Map<String, dynamic>)>
      _handlers = {
    'ai_chat': (a) => _executeSingleTurn(a, systemAlwaysApplied: false),
    'ai_chat_with_history': _executeChatWithHistory,
    'ai_chat_with_system_prompt': (a) =>
        _executeSingleTurn(a, systemAlwaysApplied: true),
    'ai_complete': _executeComplete,
    'ai_embed': _executeEmbed,
    'ai_summarize': _executeSummarize,
    'ai_list_models': _executeListModels,
    'ai_generate_image': _executeGenerateImage,
  };

  /// Resolves a provider name to its client, throwing for unknown providers.
  AiChatClient _clientFor(String provider) {
    switch (provider) {
      case 'gemini':
        return _gemini;
      case 'openai':
        return _openai;
      case 'ollama':
        return _ollama;
      case 'dial':
        return _dial;
      case 'anthropic':
        return _anthropic;
      default:
        throw ArgumentError('Unknown AI provider: $provider');
    }
  }

  /// Providers whose single-turn `ai_chat` honors the optional system prompt.
  static const Set<String> _singleTurnSystemProviders = {'gemini', 'openai'};

  /// Dispatches a single-turn chat call (`ai_chat` and
  /// `ai_chat_with_system_prompt`).
  ///
  /// When [systemAlwaysApplied] is false (plain `ai_chat`) the system prompt
  /// only applies to gemini and openai; when true it is forwarded to every
  /// provider.
  Future<String> _executeSingleTurn(
    Map<String, dynamic> args, {
    required bool systemAlwaysApplied,
  }) {
    final provider = (args['provider'] as String).toLowerCase();
    final applies =
        systemAlwaysApplied || _singleTurnSystemProviders.contains(provider);
    return _clientFor(provider).chat(
      args['model'] as String,
      args['prompt'] as String,
      applies ? args['system_prompt'] as String? : null,
    );
  }

  /// Dispatches a low-level `ai_complete` call with explicit token control.
  Future<String> _executeComplete(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    final model = args['model'] as String;
    final prompt = args['prompt'] as String;
    final maxTokens = (args['max_tokens'] as num).toInt();
    final temperature = (args['temperature'] as num?)?.toDouble();
    return _clientFor(provider).complete(model, prompt, maxTokens, temperature);
  }

  /// Dispatches an `ai_embed` call, returning the embedding JSON array.
  Future<String> _executeEmbed(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    return _clientFor(provider)
        .embed(args['model'] as String, args['text'] as String);
  }

  /// System prompt prepended to every `ai_summarize` request.
  static const String summarizePrompt =
      'Summarize the following text concisely, capturing the key points.';

  /// Dispatches an `ai_summarize` call as a single-turn chat with a fixed
  /// summarization system prompt.
  Future<String> _executeSummarize(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    return _clientFor(provider)
        .chat(args['model'] as String, args['text'] as String, summarizePrompt);
  }

  /// Dispatches a multi-turn `ai_chat_with_history` call.
  ///
  /// All five providers accept the message list plus an optional system
  /// prompt, each serialized in its native request format.
  Future<String> _executeChatWithHistory(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    final model = args['model'] as String;
    final messages = _parseMessages(args['messages']);
    final systemPrompt = args['system_prompt'] as String?;
    return _clientFor(provider).chatWithMessages(model, messages, systemPrompt);
  }

  /// Dispatches an `ai_list_models` call, returning the static model list for
  /// the provider as a JSON array string (no network call).
  ///
  /// Throws [ArgumentError] for an unknown provider.
  Future<String> _executeListModels(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    final models = aiModels[provider];
    if (models == null) {
      throw ArgumentError('Unknown AI provider: $provider');
    }
    return Future.value(jsonEncode(models));
  }

  /// Image-generation stub: validates the provider and returns a placeholder
  /// descriptor as a JSON string (no image is produced).
  ///
  /// Throws [ArgumentError] for an unknown provider.
  Future<String> _executeGenerateImage(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    if (!aiProviders.contains(provider)) {
      throw ArgumentError('Unknown AI provider: $provider');
    }
    return Future.value(jsonEncode({
      'status': 'stub',
      'provider': provider,
      'model': args['model'],
      'prompt': args['prompt'],
      'message': 'Image generation is not yet implemented',
    }));
  }

  /// Coerces a raw `messages` argument into typed `{role, content}` pairs.
  static List<Map<String, String>> _parseMessages(dynamic raw) {
    final list = raw as List? ?? const [];
    return list
        .map((m) => m as Map<String, dynamic>)
        .map((m) => {
              'role': (m['role'] ?? 'user') as String,
              'content': (m['content'] ?? '') as String,
            })
        .toList();
  }
}
