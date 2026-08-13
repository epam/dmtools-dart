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
List<ToolDefinition> aiTools() => [_aiChatTool(), _aiChatWithHistoryTool()];

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
        return _executeChat(args);
      case 'ai_chat_with_history':
        return _executeChatWithHistory(args);
      default:
        throw ArgumentError('Unknown AI tool: $toolName');
    }
  }

  /// Dispatches a single-turn `ai_chat` call.
  ///
  /// The system prompt only applies to gemini and openai; ollama, dial, and
  /// anthropic ignore it in single-turn mode.
  Future<String> _executeChat(Map<String, dynamic> args) {
    final provider = (args['provider'] as String).toLowerCase();
    final model = args['model'] as String;
    final prompt = args['prompt'] as String;
    final systemPrompt = args['system_prompt'] as String?;
    switch (provider) {
      case 'gemini':
        return _gemini.chat(model, prompt, systemPrompt);
      case 'openai':
        return _openai.chat(model, prompt, systemPrompt);
      case 'ollama':
        return _ollama.chat(model, prompt);
      case 'dial':
        return _dial.chat(model, prompt);
      case 'anthropic':
        return _anthropic.chat(model, prompt);
      default:
        throw ArgumentError('Unknown AI provider: $provider');
    }
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
    switch (provider) {
      case 'gemini':
        return _gemini.chatWithMessages(model, messages, systemPrompt);
      case 'openai':
        return _openai.chatWithMessages(model, messages, systemPrompt);
      case 'ollama':
        return _ollama.chatWithMessages(model, messages, systemPrompt);
      case 'dial':
        return _dial.chatWithMessages(model, messages, systemPrompt);
      case 'anthropic':
        return _anthropic.chatWithMessages(model, messages, systemPrompt);
      default:
        throw ArgumentError('Unknown AI provider: $provider');
    }
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
