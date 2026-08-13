import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'teams_test_support.dart';

/// Coverage + behavior tests for [TeamsClient] and [TeamsHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  sendMessageTests();
  listChatsTests();
  getChatMessagesTests();
  sendEmailTests();
  getChatMembersTests();
  createChatTests();
  getTeamsTests();
}

/// The expected Bearer token produced by the fixture's config.
const _expectedToken = 'teams-access-123';

/// [TeamsHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('TeamsHttpClient', () {
    test('builds Graph v1.0 URLs', () {
      final f = mockHttp((o) => '{}');
      expect(
        f.http.buildUrl('me'),
        'https://graph.microsoft.com/v1.0/me',
      );
    });

    test('assembles Authorization Bearer and Content-Type headers', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.headers['Authorization'], 'Bearer $_expectedToken');
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/post/put/delete return the response bodies', () async {
      final f = mockHttp(
        (o) => routeByPath(
          {
            '/get': 'GET-BODY',
            '/post': 'POST-BODY',
            '/put': 'PUT-BODY',
            '/delete': 'DELETE-BODY',
          },
          o,
        ),
      );
      expect(await f.http.get('get'), 'GET-BODY');
      expect(await f.http.post('post'), 'POST-BODY');
      expect(await f.http.put('put'), 'PUT-BODY');
      expect(await f.http.delete('delete'), 'DELETE-BODY');
      f.http.close();
    });

    test('throws StateError when no Teams token is configured', () {
      PropertyReader.clearOverrides();
      expect(() => TeamsHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `teams_test` — connectivity check via GET `me`.
void testConnectionTests() {
  group('TeamsClient.testConnection', () {
    test('returns success with the display name', () async {
      final f = mockTeams((o) => routeByPath({'/me': _meBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Teams connection successful');
      expect(result['user'], 'Ada Lovelace');
      expect(f.adapter.calls.single.path, endsWith('/v1.0/me'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockTeams((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `teams_send_message` — POST `chats/{chatId}/messages`.
void sendMessageTests() {
  group('TeamsClient.sendMessage', () {
    test('POSTs the message body and returns the decoded object', () async {
      final f = mockTeams(
        (o) => routeByPath({'/messages': _sentMessageBody}, o),
      );
      final result = await f.client.sendMessage('chat-1', 'hello');
      expect(result['id'], 'msg-1');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/v1.0/chats/chat-1/messages'));
      expect(
        jsonDecode(call.data as String),
        {
          'body': {'content': 'hello'},
        },
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockTeams((o) => routeByPath({'/messages': '[1, 2]'}, o));
      expect(await f.client.sendMessage('chat-1', 'hi'), isEmpty);
    });
  });
}

/// `teams_list_chats` — GET `me/chats`.
void listChatsTests() {
  group('TeamsClient.listChats', () {
    test('returns the decoded chats object', () async {
      final f = mockTeams((o) => routeByPath({'/chats': _chatsBody}, o));
      final chats = await f.client.listChats();
      expect(chats['value'], isA<List>());
      expect(f.adapter.calls.single.path, endsWith('/v1.0/me/chats'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockTeams((o) => routeByPath({'/chats': '[1]'}, o));
      expect(await f.client.listChats(), isEmpty);
    });
  });
}

/// `teams_get_chat_messages` — GET `chats/{chatId}/messages`.
void getChatMessagesTests() {
  group('TeamsClient.getChatMessages', () {
    test('returns the decoded messages object', () async {
      final f =
          mockTeams((o) => routeByPath({'/messages': _chatMessagesBody}, o));
      final messages = await f.client.getChatMessages('chat-1');
      expect(messages['value'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v1.0/chats/chat-1/messages'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockTeams((o) => routeByPath({'/messages': '[1]'}, o));
      expect(await f.client.getChatMessages('chat-1'), isEmpty);
    });
  });
}

/// `teams_send_email` — POST `me/sendMail`.
void sendEmailTests() {
  group('TeamsClient.sendEmail', () {
    test('POSTs the email payload and returns success', () async {
      final f = mockTeams((o) => '{}');
      final result =
          await f.client.sendEmail('ada@x.com', 'Hello', 'Body text');
      expect(result['success'], isTrue);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/v1.0/me/sendMail'));
      final payload = jsonDecode(call.data as String) as Map<String, dynamic>;
      final message = payload['message'] as Map<String, dynamic>;
      expect(message['subject'], 'Hello');
      expect(
        (message['toRecipients'] as List).first['emailAddress']['address'],
        'ada@x.com',
      );
    });
  });
}

/// `teams_get_chat_members` — GET `chats/{chatId}/members`.
void getChatMembersTests() {
  group('TeamsClient.getChatMembers', () {
    test('returns the decoded members object', () async {
      final f = mockTeams((o) => routeByPath({'/members': _membersBody}, o));
      final members = await f.client.getChatMembers('chat-1');
      expect(members['value'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v1.0/chats/chat-1/members'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockTeams((o) => routeByPath({'/members': '[1]'}, o));
      expect(await f.client.getChatMembers('chat-1'), isEmpty);
    });
  });
}

/// `teams_create_chat` — POST `chats`.
void createChatTests() {
  group('TeamsClient.createChat', () {
    test('POSTs a one-on-one chat payload and returns the decoded chat',
        () async {
      final f = mockTeams((o) => routeByPath({'/chats': _chatBody}, o));
      final chat = await f.client.createChat(['user-1']);
      expect(chat['id'], 'chat-9');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/v1.0/chats'));
      expect(
        jsonDecode(call.data as String),
        {
          'chatType': 'oneOnOne',
          'members': [
            {
              '@odata.type': '#microsoft.graph.aadUserConversationMember',
              'roles': ['owner'],
              'user@odata.bind':
                  "https://graph.microsoft.com/v1.0/users('user-1')",
            },
          ],
        },
      );
    });

    test('creates a group chat with a member entry per id', () async {
      final f = mockTeams((o) => routeByPath({'/chats': _chatBody}, o));
      await f.client.createChat(['user-1', 'user-2']);
      final payload = jsonDecode(f.adapter.calls.single.data as String)
          as Map<String, dynamic>;
      expect(payload['chatType'], 'group');
      final members = payload['members'] as List;
      expect(members.length, 2);
      expect(
        (members.last as Map<String, dynamic>)['user@odata.bind'],
        "https://graph.microsoft.com/v1.0/users('user-2')",
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockTeams((o) => routeByPath({'/chats': '[1]'}, o));
      expect(await f.client.createChat(['user-1']), isEmpty);
    });
  });
}

/// `teams_get_teams` — GET `me/joinedTeams`.
void getTeamsTests() {
  group('TeamsClient.getTeams', () {
    test('returns the decoded joined teams object', () async {
      final f = mockTeams((o) => routeByPath({'/joinedTeams': _teamsBody}, o));
      final teams = await f.client.getTeams();
      expect(teams['value'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v1.0/me/joinedTeams'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockTeams((o) => routeByPath({'/joinedTeams': '[1]'}, o));
      expect(await f.client.getTeams(), isEmpty);
    });
  });
}

/// Canned `me` response body (the authenticated user profile).
const _meBody =
    '{"displayName":"Ada Lovelace","userPrincipalName":"ada@x.com"}';

/// Canned send-message response body.
const _sentMessageBody = '{"id":"msg-1","body":{"content":"hello"}}';

/// Canned chats response body.
const _chatsBody = '{"@odata.context":"ctx","value":[{"id":"c1"},{"id":"c2"}]}';

/// Canned chat-messages response body.
const _chatMessagesBody =
    '{"value":[{"id":"m1","body":{"content":"hi"}},{"id":"m2","body":'
    '{"content":"yo"}}]}';

/// Canned chat-members response body.
const _membersBody =
    '{"value":[{"userId":"u1","displayName":"Ada"},{"userId":"u2"}]}';

/// Canned create-chat response body.
const _chatBody = '{"id":"chat-9","chatType":"oneOnOne"}';

/// Canned joined-teams response body.
const _teamsBody = '{"value":[{"id":"t1","displayName":"Team A"}]}';
