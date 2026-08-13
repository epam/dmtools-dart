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
}
