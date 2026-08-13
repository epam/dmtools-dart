import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Tests for the [jiraTools] catalog and [JiraToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    jiraTools().firstWhere((t) => t.name == name);

/// Catalog shape: tool count, order, integration, params, aliases.
void toolCatalogTests() {
  group('jiraTools catalog', () {
    final tools = jiraTools();

    test('registers the seven tools in declaration order', () {
      expect(tools.map((t) => t.name), [
        'jira_test',
        'jira_get_ticket',
        'jira_search_by_jql',
        'jira_post_comment',
        'jira_add_label',
        'jira_remove_label',
        'jira_move_to_status',
      ]);
    });

    test('every tool belongs to the jira integration', () {
      expect(tools.every((t) => t.integration == 'jira'), isTrue);
    });
  });

  group('jira_get_ticket', () {
    final tool = toolNamed('jira_get_ticket');

    test('exposes the tracker_get_ticket alias', () {
      expect(tool.aliases, ['tracker_get_ticket']);
    });

    test('declares required key and optional array fields', () {
      expect(tool.params.map((p) => p.name), ['key', 'fields']);
      expect(tool.params.first.required, isTrue);
      expect(tool.params.last.required, isFalse);
      expect(tool.params.last.type, 'array');
    });
  });

  test('jira_search_by_jql requires jql with optional array fields', () {
    final tool = toolNamed('jira_search_by_jql');
    expect(tool.category, 'search');
    expect(tool.params.map((p) => p.name), ['jql', 'fields']);
    expect(tool.params.first.required, isTrue);
    expect(tool.params.last.type, 'array');
  });

  test('comment/label/status tools each take two required params', () {
    const expected = {
      'jira_post_comment': ['key', 'comment'],
      'jira_add_label': ['key', 'label'],
      'jira_remove_label': ['key', 'label'],
      'jira_move_to_status': ['key', 'status'],
    };
    for (final entry in expected.entries) {
      final tool = toolNamed(entry.key);
      expect(tool.params.map((p) => p.name).toList(), entry.value,
          reason: entry.key);
      expect(tool.params.every((p) => p.required), isTrue, reason: entry.key);
    }
  });
}

/// [JiraToolExecutor.execute] routes each tool name to the right client call.
void executorDispatchTests() {
  group('JiraToolExecutor.execute', () {
    late _SpyJiraClient spy;
    late JiraToolExecutor executor;

    setUp(() {
      spy = _SpyJiraClient(mockHttp((o) => '{}').http);
      executor = JiraToolExecutor(spy);
    });

    test('routes jira_test to testConnection', () async {
      await executor.execute('jira_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes jira_get_ticket with key and fields', () async {
      await executor.execute('jira_get_ticket', {
        'key': 'PROJ-1',
        'fields': ['summary'],
      });
      expect(spy.calls, ['getTicket:PROJ-1:[summary]']);
    });

    test('routes jira_search_by_jql with jql', () async {
      await executor.execute('jira_search_by_jql', {'jql': 'project = X'});
      expect(spy.calls, ['searchByJql:project = X']);
    });

    test('routes jira_post_comment with key and comment', () async {
      await executor.execute('jira_post_comment', {
        'key': 'PROJ-1',
        'comment': 'hi',
      });
      expect(spy.calls, ['postComment:PROJ-1:hi']);
    });

    test('routes jira_add_label and jira_remove_label', () async {
      await executor.execute('jira_add_label', {'key': 'PROJ-1', 'label': 'b'});
      expect(spy.calls, ['addLabel:PROJ-1:b']);
      spy.calls.clear();
      await executor
          .execute('jira_remove_label', {'key': 'PROJ-1', 'label': 'b'});
      expect(spy.calls, ['removeLabel:PROJ-1:b']);
    });

    test('routes jira_move_to_status with key and status', () async {
      await executor
          .execute('jira_move_to_status', {'key': 'PROJ-1', 'status': 'Done'});
      expect(spy.calls, ['moveToStatus:PROJ-1:Done']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(() => executor.execute('jira_no_such', {}), throwsArgumentError);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyJiraClient extends JiraClient {
  _SpyJiraClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>?> getTicket(String key, [List<String>? fields]) {
    calls.add('getTicket:$key:$fields');
    return super.getTicket(key, fields);
  }

  @override
  Future<List<Map<String, dynamic>>> searchByJql(String jql,
      [List<String>? fields]) {
    calls.add('searchByJql:$jql');
    return super.searchByJql(jql, fields);
  }

  @override
  Future<void> postComment(String key, String comment) {
    calls.add('postComment:$key:$comment');
    return super.postComment(key, comment);
  }

  @override
  Future<void> addLabel(String key, String label) {
    calls.add('addLabel:$key:$label');
    return super.addLabel(key, label);
  }

  @override
  Future<void> removeLabel(String key, String label) {
    calls.add('removeLabel:$key:$label');
    return super.removeLabel(key, label);
  }

  @override
  Future<String> moveToStatus(String key, String statusName) {
    calls.add('moveToStatus:$key:$statusName');
    return super.moveToStatus(key, statusName);
  }
}
