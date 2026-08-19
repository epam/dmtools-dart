import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// User coverage: `confluence_get_user_by_key` — client method, tool
/// definition, and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getUserByKeyTests();
  userToolDefinitionTests();
  userExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_user_by_key` — GET `user?key={key}`.
void getUserByKeyTests() {
  group('ConfluenceClient.getUserByKey', () {
    test('GETs the user with the key query parameter', () async {
      final f = mockConfluence((o) => routeByPath({'/user': _userBody}, o));
      final user = await f.client.getUserByKey('abc123');
      expect(user['username'], 'alice');
      final call = f.adapter.calls.single;
      expect(call.path, endsWith('/user'));
      expect(call.queryParameters['key'], 'abc123');
    });
  });
}

/// Tool-definition shape for the user tools.
void userToolDefinitionTests() {
  group('confluence tool definitions (users)', () {
    test('confluence_get_user_by_key requires key', () {
      final tool = toolNamed('confluence_get_user_by_key');
      expect(tool.category, 'users');
      expect(tool.params.single.name, 'key');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each user tool name.
void userExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (users)', () {
    test('routes confluence_get_user_by_key', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_user_by_key',
        {'key': 'abc123'},
      );
      expect(f.client.calls, ['getUserByKey:abc123']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _UsersSpy client}) _makeExecutor() {
  final client = _UsersSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned user response body.
const _userBody = '{"username":"alice","key":"abc123"}';

/// Spy that records every user call then delegates to the real client.
class _UsersSpy extends ConfluenceClient {
  _UsersSpy(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> getUserByKey(String key) {
    calls.add('getUserByKey:$key');
    return super.getUserByKey(key);
  }
}
