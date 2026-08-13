/// MCP tool definitions and dispatcher for the AI integration.
///
/// The tool list ports the AI subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching provider client
/// ([GeminiClient], [OpenAIClient], or [OllamaClient]).
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'gemini_client.dart';
import 'ollama_client.dart';
import 'openai_client.dart';

/// Supported AI provider identifiers.
const aiProviders = {'gemini', 'openai', 'ollama'};

/// Returns all AI MCP tool definitions.
List<ToolDefinition> aiTools() => [_aiChatTool()];

/// Single-turn chat tool: `ai_chat`.
ToolDefinition _aiChatTool() => ToolDefinition(
      name: 'ai_chat',
      description: 'Send a single-turn chat prompt to an AI provider '
          '(gemini, openai, or ollama) and return the response text',
      integration: 'ai',
      category: 'chat',
      params: [
        ToolParam(
          name: 'provider',
          description: 'AI provider: gemini, openai, or ollama',
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

/// Executes AI MCP tools by dispatching to the appropriate provider client.
class AiToolExecutor {
  final GeminiClient _gemini;
  final OpenAIClient _openai;
  final OllamaClient _ollama;

  /// Creates an executor bound to the three provider clients.
  AiToolExecutor({
    required GeminiClient gemini,
    required OpenAIClient openai,
    required OllamaClient ollama,
  })  : _gemini = gemini,
        _openai = openai,
        _ollama = ollama;

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown AI tool name or provider.
  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    if (toolName != 'ai_chat') {
      throw ArgumentError('Unknown AI tool: $toolName');
    }
    final provider = (args['provider'] as String).toLowerCase();
    final model = args['model'] as String;
    final prompt = args['prompt'] as String;
    final systemPrompt = args['system_prompt'] as String?;
    return _dispatch(provider, model, prompt, systemPrompt);
  }

  /// Routes the chat call to the provider-specific client.
  Future<String> _dispatch(
    String provider,
    String model,
    String prompt,
    String? systemPrompt,
  ) {
    switch (provider) {
      case 'gemini':
        return _gemini.chat(model, prompt, systemPrompt);
      case 'openai':
        return _openai.chat(model, prompt, systemPrompt);
      case 'ollama':
        return _ollama.chat(model, prompt);
      default:
        throw ArgumentError('Unknown AI provider: $provider');
    }
  }
}
