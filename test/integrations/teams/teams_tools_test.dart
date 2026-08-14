import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'teams_test_support.dart';

/// Tests for the [teamsTools] catalog and [TeamsToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  toolCatalogParamTests();
  chatAndTeamCatalogParamTests();
  replyToolCatalogParamTests();
  executorDispatchTests();
  chatAndTeamToolDispatchTests();
  replyToolDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    teamsTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration.
void toolCatalogTests() {
  group('teamsTools catalog', () {
    final tools = teamsTools();

    test('registers the twelve tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'teams_test',
        'teams_send_message',
        'teams_list_chats',
        'teams_get_chat_messages',
        'teams_send_email',
        'teams_get_chat_members',
        'teams_create_chat',
        'teams_get_teams',
        'teams_get_team_channels',
        'teams_send_channel_message',
        'teams_get_channel_messages',
        'teams_reply_to_message',
      ]);
    });

    test('every tool belongs to the teams integration', () {
      expect(tools.every((t) => t.integration == 'teams'), isTrue);
    });
  });
}

/// Per-tool parameter declarations for the core messaging tools.
void toolCatalogParamTests() {
  group('teams_send_message', () {
    final tool = toolNamed('teams_send_message');

    test('declares required chat_id and message', () {
      expect(tool.params.map((p) => p.name), ['chat_id', 'message']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('teams_list_chats', () {
    final tool = toolNamed('teams_list_chats');

    test('takes no parameters', () {
      expect(tool.params, isEmpty);
    });
  });

  group('teams_get_chat_messages', () {
    final tool = toolNamed('teams_get_chat_messages');

    test('declares a required chat_id', () {
      expect(tool.params.single.name, 'chat_id');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('teams_send_email', () {
    final tool = toolNamed('teams_send_email');

    test('declares required to, subject, and body', () {
      expect(tool.params.map((p) => p.name), ['to', 'subject', 'body']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Per-tool parameter declarations for the chat and team tools.
void chatAndTeamCatalogParamTests() {
  group('teams_get_chat_members', () {
    final tool = toolNamed('teams_get_chat_members');

    test('declares a required chat_id', () {
      expect(tool.params.single.name, 'chat_id');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('teams_create_chat', () {
    final tool = toolNamed('teams_create_chat');

    test('declares a required members array', () {
      expect(tool.params.single.name, 'members');
      expect(tool.params.single.required, isTrue);
      expect(tool.params.single.type, 'array');
    });
  });

  group('teams_get_teams', () {
    final tool = toolNamed('teams_get_teams');

    test('takes no parameters', () {
      expect(tool.params, isEmpty);
    });
  });

  group('teams_get_team_channels', () {
    final tool = toolNamed('teams_get_team_channels');

    test('declares a required team_id', () {
      expect(tool.params.single.name, 'team_id');
      expect(tool.params.single.required, isTrue);
    });
  });

  group('teams_send_channel_message', () {
    final tool = toolNamed('teams_send_channel_message');

    test('declares required team_id, channel_id, and message', () {
      expect(tool.params.map((p) => p.name), [
        'team_id',
        'channel_id',
        'message',
      ]);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('teams_get_channel_messages', () {
    final tool = toolNamed('teams_get_channel_messages');

    test('declares required team_id and channel_id', () {
      expect(tool.params.map((p) => p.name), ['team_id', 'channel_id']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// Per-tool parameter declarations for the reply tool.
void replyToolCatalogParamTests() {
  group('teams_reply_to_message', () {
    final tool = toolNamed('teams_reply_to_message');

    test('declares required chat_id, message_id, and body', () {
      expect(tool.params.map((p) => p.name), ['chat_id', 'message_id', 'body']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [TeamsToolExecutor.execute] routes each tool name to the right client call.
void executorDispatchTests() {
  group('TeamsToolExecutor.execute', () {
    late _SpyTeamsClient spy;
    late TeamsToolExecutor executor;

    setUp(() {
      spy = _SpyTeamsClient(mockHttp((o) => '{}').http);
      executor = TeamsToolExecutor(spy);
    });

    test('routes teams_test to testConnection', () async {
      await executor.execute('teams_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes teams_send_message with chat_id and message', () async {
      await executor.execute(
        'teams_send_message',
        {'chat_id': 'c1', 'message': 'hi'},
      );
      expect(spy.calls, ['sendMessage:c1:hi']);
    });

    test('routes teams_list_chats', () async {
      await executor.execute('teams_list_chats', {});
      expect(spy.calls, ['listChats']);
    });

    test('routes teams_get_chat_messages with chat_id', () async {
      await executor.execute('teams_get_chat_messages', {'chat_id': 'c1'});
      expect(spy.calls, ['getChatMessages:c1']);
    });

    test('routes teams_send_email with to, subject, and body', () async {
      await executor.execute(
        'teams_send_email',
        {'to': 'a@x.com', 'subject': 'Hi', 'body': 'text'},
      );
      expect(spy.calls, ['sendEmail:a@x.com:Hi:text']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => executor.execute('teams_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// Dispatch tests for the chat and team tools.
void chatAndTeamToolDispatchTests() {
  group('TeamsToolExecutor.execute chat/team tools', () {
    late _SpyTeamsClient spy;
    late TeamsToolExecutor executor;

    setUp(() {
      spy = _SpyTeamsClient(mockHttp((o) => '{}').http);
      executor = TeamsToolExecutor(spy);
    });

    test('routes teams_get_chat_members with chat_id', () async {
      await executor.execute('teams_get_chat_members', {'chat_id': 'c1'});
      expect(spy.calls, ['getChatMembers:c1']);
    });

    test('routes teams_create_chat with the members list', () async {
      await executor.execute(
        'teams_create_chat',
        {
          'members': ['u1', 'u2']
        },
      );
      expect(spy.calls, ['createChat:u1,u2']);
    });

    test('routes teams_get_teams', () async {
      await executor.execute('teams_get_teams', {});
      expect(spy.calls, ['getTeams']);
    });

    test('routes teams_get_team_channels with team_id', () async {
      await executor.execute('teams_get_team_channels', {'team_id': 't1'});
      expect(spy.calls, ['getTeamChannels:t1']);
    });

    test('routes teams_send_channel_message with team, channel, message',
        () async {
      await executor.execute(
        'teams_send_channel_message',
        {'team_id': 't1', 'channel_id': 'ch1', 'message': 'hi'},
      );
      expect(spy.calls, ['sendChannelMessage:t1:ch1:hi']);
    });

    test('routes teams_get_channel_messages with team and channel', () async {
      await executor.execute(
        'teams_get_channel_messages',
        {'team_id': 't1', 'channel_id': 'ch1'},
      );
      expect(spy.calls, ['getChannelMessages:t1:ch1']);
    });
  });
}

/// Dispatch tests for the reply tool.
void replyToolDispatchTests() {
  group('TeamsToolExecutor.execute reply tool', () {
    late _SpyTeamsClient spy;
    late TeamsToolExecutor executor;

    setUp(() {
      spy = _SpyTeamsClient(mockHttp((o) => '{}').http);
      executor = TeamsToolExecutor(spy);
    });

    test('routes teams_reply_to_message with chat, message, body', () async {
      await executor.execute(
        'teams_reply_to_message',
        {'chat_id': 'c1', 'message_id': 'm1', 'body': 'hi'},
      );
      expect(spy.calls, ['replyToMessage:c1:m1:hi']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyTeamsClient extends TeamsClient {
  _SpyTeamsClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>> sendMessage(String chatId, String message) {
    calls.add('sendMessage:$chatId:$message');
    return super.sendMessage(chatId, message);
  }

  @override
  Future<Map<String, dynamic>> listChats() {
    calls.add('listChats');
    return super.listChats();
  }

  @override
  Future<Map<String, dynamic>> getChatMessages(String chatId) {
    calls.add('getChatMessages:$chatId');
    return super.getChatMessages(chatId);
  }

  @override
  Future<Map<String, dynamic>> sendEmail(
    String to,
    String subject,
    String body,
  ) {
    calls.add('sendEmail:$to:$subject:$body');
    return super.sendEmail(to, subject, body);
  }

  @override
  Future<Map<String, dynamic>> getChatMembers(String chatId) {
    calls.add('getChatMembers:$chatId');
    return super.getChatMembers(chatId);
  }

  @override
  Future<Map<String, dynamic>> createChat(List<String> members) {
    calls.add('createChat:${members.join(',')}');
    return super.createChat(members);
  }

  @override
  Future<Map<String, dynamic>> getTeams() {
    calls.add('getTeams');
    return super.getTeams();
  }

  @override
  Future<Map<String, dynamic>> getTeamChannels(String teamId) {
    calls.add('getTeamChannels:$teamId');
    return super.getTeamChannels(teamId);
  }

  @override
  Future<Map<String, dynamic>> sendChannelMessage(
    String teamId,
    String channelId,
    String message,
  ) {
    calls.add('sendChannelMessage:$teamId:$channelId:$message');
    return super.sendChannelMessage(teamId, channelId, message);
  }

  @override
  Future<Map<String, dynamic>> getChannelMessages(
    String teamId,
    String channelId,
  ) {
    calls.add('getChannelMessages:$teamId:$channelId');
    return super.getChannelMessages(teamId, channelId);
  }

  @override
  Future<Map<String, dynamic>> replyToMessage(
    String chatId,
    String messageId,
    String body,
  ) {
    calls.add('replyToMessage:$chatId:$messageId:$body');
    return super.replyToMessage(chatId, messageId, body);
  }
}
