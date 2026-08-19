/// High-level Microsoft Teams API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a Teams MCP tool and targets the Microsoft Graph
/// chat endpoints. Transport is delegated to [TeamsHttpClient]; this layer
/// shapes requests and parses JSON into typed results.
library;

import 'dart:convert';

import 'teams_http_client.dart';

/// Teams API methods exposed to the MCP tool runtime.
class TeamsClient {
  final TeamsHttpClient _http;

  /// Creates a client backed by [_http].
  TeamsClient(this._http);

  /// URL-encodes a chat identifier for safe path-segment use.
  String _encodeId(String id) => Uri.encodeComponent(id);

  /// `teams_test` — connectivity check via GET `me`.
  ///
  /// Returns the authenticated user's display name on success, or an error
  /// map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final raw = await _http.get('me');
      final account = jsonDecode(raw);
      final displayName = account is Map<String, dynamic>
          ? (account['displayName'] ?? account['userPrincipalName'] ?? '')
          : '';
      return <String, dynamic>{
        'success': true,
        'message': 'Teams connection successful',
        'user': displayName,
      };
    } on Object catch (err) {
      return <String, dynamic>{
        'success': false,
        'message': 'Teams connection failed',
        'error': err.toString(),
      };
    }
  }

  /// `teams_send_message` — POST `chats/{chatId}/messages`.
  ///
  /// Sends [message] as the chat-message body content. Returns the decoded
  /// Graph response object, or an empty map for non-object bodies.
  Future<Map<String, dynamic>> sendMessage(
    String chatId,
    String message,
  ) async {
    final result = await _http.post(
      'chats/${_encodeId(chatId)}/messages',
      body: jsonEncode({
        'body': {'content': message},
      }),
    );
    final decoded = jsonDecode(result);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `teams_list_chats` — GET `me/chats`.
  ///
  /// Returns the decoded Graph response object (contains `value` + `@odata
  /// .context`), or an empty map for non-object bodies.
  Future<Map<String, dynamic>> listChats() async {
    final body = await _http.get('me/chats');
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `teams_get_chat_messages` — GET `chats/{chatId}/messages`.
  ///
  /// Returns the decoded Graph response object (contains `value`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getChatMessages(String chatId) async {
    final body = await _http.get('chats/${_encodeId(chatId)}/messages');
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `teams_send_email` — POST `me/sendMail`.
  ///
  /// Sends an email with [subject] and [body] to the recipient [to] on
  /// behalf of the authenticated user. Graph responds 202 with no body on
  /// success, so a success map is returned rather than a decoded payload.
  Future<Map<String, dynamic>> sendEmail(
    String to,
    String subject,
    String body,
  ) async {
    await _http.post(
      'me/sendMail',
      body: jsonEncode({
        'message': {
          'subject': subject,
          'body': {'contentType': 'Text', 'content': body},
          'toRecipients': [
            {
              'emailAddress': {'address': to},
            },
          ],
        },
      }),
    );
    return {'success': true, 'message': 'Email sent to $to'};
  }

  /// `teams_get_chat_members` — GET `chats/{chatId}/members`.
  ///
  /// Returns the decoded Graph response object (contains `value`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getChatMembers(String chatId) async {
    final body = await _http.get('chats/${_encodeId(chatId)}/members');
    return _decodeObject(body);
  }

  /// `teams_create_chat` — POST `chats`.
  ///
  /// Creates a chat with [members] (Graph user ids or UPNs). Chats with a
  /// single other member are one-on-one; more become group chats. Returns
  /// the decoded Graph chat object, or an empty map for non-object bodies.
  Future<Map<String, dynamic>> createChat(List<String> members) async {
    final result = await _http.post(
      'chats',
      body: jsonEncode({
        'chatType': members.length <= 1 ? 'oneOnOne' : 'group',
        'members': [
          for (final member in members)
            {
              '@odata.type': '#microsoft.graph.aadUserConversationMember',
              'roles': ['owner'],
              'user@odata.bind':
                  "https://graph.microsoft.com/v1.0/users('$member')",
            },
        ],
      }),
    );
    return _decodeObject(result);
  }

  /// `teams_get_teams` — GET `me/joinedTeams`.
  ///
  /// Returns the decoded Graph response object (contains `value`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getTeams() async {
    final body = await _http.get('me/joinedTeams');
    return _decodeObject(body);
  }

  /// `teams_get_team_channels` — GET `teams/{teamId}/channels`.
  ///
  /// Returns the decoded Graph response object (contains `value`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getTeamChannels(String teamId) async {
    final body = await _http.get('teams/${_encodeId(teamId)}/channels');
    return _decodeObject(body);
  }

  /// `teams_send_channel_message` — POST
  /// `teams/{teamId}/channels/{channelId}/messages`.
  ///
  /// Sends [message] as the channel-message body content. Returns the
  /// decoded Graph response object, or an empty map for non-object bodies.
  Future<Map<String, dynamic>> sendChannelMessage(
    String teamId,
    String channelId,
    String message,
  ) async {
    final result = await _http.post(
      'teams/${_encodeId(teamId)}/channels/${_encodeId(channelId)}/messages',
      body: jsonEncode({
        'body': {'content': message},
      }),
    );
    return _decodeObject(result);
  }

  /// `teams_get_channel_messages` — GET
  /// `teams/{teamId}/channels/{channelId}/messages`.
  ///
  /// Returns the decoded Graph response object (contains `value`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> getChannelMessages(
    String teamId,
    String channelId,
  ) async {
    final body = await _http.get(
      'teams/${_encodeId(teamId)}/channels/${_encodeId(channelId)}/messages',
    );
    return _decodeObject(body);
  }

  /// Decodes a Graph JSON body into a map, or returns empty for non-objects.
  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }
}
