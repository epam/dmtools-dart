import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'teams_test_support.dart';

/// Tests for the [teamsTools] catalog and [TeamsToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    teamsTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('teamsTools catalog', () {
    final tools = teamsTools();

    test('registers the five tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'teams_test',
        'teams_send_message',
        'teams_list_chats',
        'teams_get_chat_messages',
        'teams_send_email',
      ]);
    });

    test('every tool belongs to the teams integration', () {
      expect(tools.every((t) => t.integration == 'teams'), isTrue);
    });
  });

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
}
