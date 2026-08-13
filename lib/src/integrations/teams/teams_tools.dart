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
      _getChatMessagesTool(),
      _sendEmailTool(),
      _getChatMembersTool(),
      _createChatTool(),
      _getTeamsTool(),
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

/// Get-chat-messages tool: `teams_get_chat_messages`.
ToolDefinition _getChatMessagesTool() => ToolDefinition(
      name: 'teams_get_chat_messages',
      description: 'Get messages from a Teams chat by chat id',
      integration: 'teams',
      category: 'messages',
      params: [
        ToolParam(
          name: 'chat_id',
          description: 'The Teams chat id',
          required: true,
        ),
      ],
    );

/// Send-email tool: `teams_send_email`.
ToolDefinition _sendEmailTool() => ToolDefinition(
      name: 'teams_send_email',
      description: 'Send an email via Microsoft Graph on behalf of the user',
      integration: 'teams',
      category: 'messages',
      params: [
        ToolParam(
          name: 'to',
          description: 'The recipient email address',
          required: true,
        ),
        ToolParam(
          name: 'subject',
          description: 'The email subject',
          required: true,
        ),
        ToolParam(
          name: 'body',
          description: 'The email body content',
          required: true,
        ),
      ],
    );

/// Get-chat-members tool: `teams_get_chat_members`.
ToolDefinition _getChatMembersTool() => ToolDefinition(
      name: 'teams_get_chat_members',
      description: 'Get the members of a Teams chat by chat id',
      integration: 'teams',
      category: 'chats',
      params: [
        ToolParam(
          name: 'chat_id',
          description: 'The Teams chat id',
          required: true,
        ),
      ],
    );

/// Create-chat tool: `teams_create_chat`.
ToolDefinition _createChatTool() => ToolDefinition(
      name: 'teams_create_chat',
      description: 'Create a Teams chat with the given member user ids',
      integration: 'teams',
      category: 'chats',
      params: [
        ToolParam(
          name: 'members',
          description: 'The member Graph user ids or UPNs for the chat',
          required: true,
          type: 'array',
        ),
      ],
    );

/// Get-teams tool: `teams_get_teams`.
ToolDefinition _getTeamsTool() => ToolDefinition(
      name: 'teams_get_teams',
      description: 'List the teams the current user has joined',
      integration: 'teams',
      category: 'teams',
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
    'teams_get_chat_messages': (a) => _client.getChatMessages(
          a['chat_id'] as String,
        ),
    'teams_send_email': (a) => _client.sendEmail(
          a['to'] as String,
          a['subject'] as String,
          a['body'] as String,
        ),
    'teams_get_chat_members': (a) => _client.getChatMembers(
          a['chat_id'] as String,
        ),
    'teams_create_chat': (a) => _client.createChat(
          (a['members'] as List).cast<String>(),
        ),
    'teams_get_teams': (_) => _client.getTeams(),
  };
}
