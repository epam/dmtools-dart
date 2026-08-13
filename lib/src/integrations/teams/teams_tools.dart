/// MCP tool definitions and dispatcher for the Teams integration.
///
/// The tool list ports the Teams subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [TeamsClient]
/// call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'teams_client.dart';

/// Returns all Teams MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> teamsTools() => [
      _testTool(),
      _sendMessageTool(),
      _listChatsTool(),
    ];

/// Connectivity-check tool: `teams_test`.
ToolDefinition _testTool() => ToolDefinition(
      name: 'teams_test',
      description: 'Test Teams connectivity by fetching the current user',
      integration: 'teams',
      category: 'system',
      params: [],
    );

/// Send-message tool: `teams_send_message`.
ToolDefinition _sendMessageTool() => ToolDefinition(
      name: 'teams_send_message',
      description: 'Send a message to a Teams chat by chat id',
      integration: 'teams',
      category: 'messages',
      params: [
        ToolParam(
          name: 'chat_id',
          description: 'The Teams chat id',
          required: true,
        ),
        ToolParam(
          name: 'message',
          description: 'The message content to send',
          required: true,
        ),
      ],
    );

/// List-chats tool: `teams_list_chats`.
ToolDefinition _listChatsTool() => ToolDefinition(
      name: 'teams_list_chats',
      description: 'List the Teams chats of the current user',
      integration: 'teams',
      category: 'messages',
      params: [],
    );

/// Executes Teams MCP tools by dispatching to [TeamsClient].
class TeamsToolExecutor {
  final TeamsClient _client;

  /// Creates an executor bound to [_client].
  TeamsToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Teams tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Teams tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'teams_test': (_) => _client.testConnection(),
    'teams_send_message': (a) => _client.sendMessage(
          a['chat_id'] as String,
          a['message'] as String,
        ),
    'teams_list_chats': (_) => _client.listChats(),
  };
}
