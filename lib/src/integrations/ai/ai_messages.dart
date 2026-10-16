/// Shared helpers for AI provider message handling.
///
/// Used by the OpenAI-compatible provider clients ([OpenAIClient], [DialClient],
/// [OllamaClient]) that accept a `system` role inside their `messages` array,
/// so the prepend logic lives in one place rather than being triplicated.
library;

/// A chat message history: ordered `{role, content}` pairs.
typedef ChatMessages = List<Map<String, String>>;

/// Prepends a `system` message to [messages] when [systemPrompt] is
/// non-empty; otherwise returns [messages] unchanged.
List<Map<String, String>> withSystemMessage(
  List<Map<String, String>> messages,
  String? systemPrompt,
) =>
    (systemPrompt == null || systemPrompt.isEmpty)
        ? messages
        : [
            {'role': 'system', 'content': systemPrompt},
            ...messages,
          ];

/// A single-message list wrapping [prompt] as a `user` turn.
List<Map<String, String>> userMessages(String prompt) => [
      {'role': 'user', 'content': prompt},
    ];
