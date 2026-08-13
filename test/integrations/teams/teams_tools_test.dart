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

    test('registers the three tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'teams_test',
        'teams_send_message',
        'teams_list_chats',
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
}
