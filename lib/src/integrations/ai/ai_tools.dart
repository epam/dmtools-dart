/// MCP tool definitions and dispatcher for the AI integration.
///
/// The tool list ports the AI subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching provider client
/// ([GeminiClient], [OpenAIClient], [OllamaClient], [DialClient], or
/// [AnthropicClient]).
library;

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

/// Returns all AI MCP tool definitions.
List<ToolDefinition> aiTools() => [
      _aiChatTool(),
      _aiChatWithHistoryTool(),
      _aiChatWithSystemPromptTool(),
      _aiCompleteTool(),
      _aiEmbedTool(),
      _aiSummarizeTool(),
    ];

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
  /// Throws [ArgumentError] for an unknown AI tool name or provider.
  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    switch (toolName) {
      case 'ai_chat':
        return _executeSingleTurn(args, systemAlwaysApplied: false);
      case 'ai_chat_with_history':
        return _executeChatWithHistory(args);
      case 'ai_chat_with_system_prompt':
        return _executeSingleTurn(args, systemAlwaysApplied: true);
      case 'ai_complete':
        return _executeComplete(args);
      case 'ai_embed':
        return _executeEmbed(args);
      case 'ai_summarize':
        return _executeSummarize(args);
      default:
        throw ArgumentError('Unknown AI tool: $toolName');
    }
  }

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
