import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Watcher coverage: `confluence_get_watchers` — client method, tool
/// definition, and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getWatchersTests();
  watcherToolDefinitionTests();
  watcherExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_watchers` — GET `content/{contentId}/notification`.
void getWatchersTests() {
  group('ConfluenceClient.getWatchers', () {
    test('returns the watcher results', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/notification': _watchersBody}, o),
      );
      final watchers = await f.client.getWatchers('42');
      expect(watchers, hasLength(1));
      expect(watchers.single['username'], 'alice');
      expect(
        f.adapter.calls.single.path,
        endsWith('/content/42/notification'),
      );
    });
  });
}

/// Tool-definition shape for the watcher tools.
void watcherToolDefinitionTests() {
  group('confluence tool definitions (watchers)', () {
    test('confluence_get_watchers requires contentId', () {
      final tool = toolNamed('confluence_get_watchers');
      expect(tool.category, 'watchers');
      expect(tool.params.single.name, 'contentId');
      expect(tool.params.single.required, isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each watcher tool name.
void watcherExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (watchers)', () {
    test('routes confluence_get_watchers', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_watchers',
        {'contentId': '42'},
      );
      expect(f.client.calls, ['getWatchers:42']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _WatchersSpy client}) _makeExecutor() {
  final client = _WatchersSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned watchers response body.
final _watchersBody = jsonEncode({
  'results': [
    {'username': 'alice'},
  ],
});

/// Spy that records every watcher call then delegates to the real client.
class _WatchersSpy extends ConfluenceClient {
  _WatchersSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getWatchers(String contentId) {
    calls.add('getWatchers:$contentId');
    return super.getWatchers(contentId);
  }
}
