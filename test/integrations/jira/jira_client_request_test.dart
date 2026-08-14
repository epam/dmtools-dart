import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Ad-hoc request tests: executeRequest — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  executeRequestTests();
  requestExecutorDispatchTests();
}

/// `jira_execute_request` — GET any Jira REST path.
void executeRequestTests() {
  group('JiraClient.executeRequest', () {
    test('GETs the given path and returns the decoded map', () async {
      final f = mockJira(
          (o) => routeByPath({'/serverInfo': '{"version":"10.0"}'}, o));
      final result = await f.client.executeRequest('serverInfo');
      expect(result['version'], '10.0');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, endsWith('/serverInfo'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.executeRequest('serverInfo'), isEmpty);
    });
  });
}

/// [JiraToolExecutor.execute] routes ad-hoc request tool names correctly.
void requestExecutorDispatchTests() {
  group('JiraToolExecutor.execute (ad-hoc requests)', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_execute_request', () async {
      await executor.execute('jira_execute_request', {'url': 'serverInfo'});
      expect(spy.calls, ['executeRequest:serverInfo']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyJiraClient extends JiraClient {
  _SpyJiraClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> executeRequest(String url) {
    calls.add('executeRequest:$url');
    return super.executeRequest(url);
  }
}
