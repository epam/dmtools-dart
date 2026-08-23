import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Tests for the [jiraTools] catalog and [JiraToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogShapeTests();
  jiraGetTicketShapeTests();
  toolCatalogParamTests();
  executorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    jiraTools().firstWhere((t) => t.name == name);

/// Expected tool names in declaration order.
const _expectedToolNames = [
  'jira_test',
  'jira_get_ticket',
  'jira_search_by_jql',
  'jira_post_comment',
  'jira_add_label',
  'jira_remove_label',
  'jira_move_to_status',
  'jira_get_comments',
  'jira_assign_ticket_to',
  'jira_update_field',
  'jira_clear_field',
  'jira_create_ticket_basic',
  'jira_create_ticket_with_json',
  'jira_get_transitions',
  'jira_delete_ticket',
  'jira_get_issue_types',
  'jira_get_fields',
  'jira_get_components',
  'jira_get_fix_versions',
  'jira_set_fix_version',
  'jira_set_priority',
  'jira_update_description',
  'jira_get_subtasks',
  'jira_create_ticket_with_parent',
  'jira_post_comment_if_not_exists',
  'jira_update_field_as_adf',
  'jira_get_all_fields_with_name',
  'jira_get_field_custom_code',
  'jira_update_all_fields_with_name',
  'jira_update_ticket',
  'jira_link_issues',
  'jira_get_issue_link_types',
  'jira_execute_request',
  'jira_get_project_details',
  'jira_get_project_statuses',
  'jira_move_to_status_with_resolution',
  'jira_get_account_by_email',
  'jira_get_user_profile',
  'jira_attach_file_to_ticket',
  'jira_download_attachment',
  'jira_clone_project',
  'jira_delete_project',
  'jira_setup_project_workflow',
  'jira_sync_project_workflow',
  'jira_copy_project_structure',
  'jira_get_project_board_config',
  'jira_get_project_issue_type_scheme',
  'jira_assign_issue_type_scheme',
  'jira_get_project_workflow_scheme',
  'jira_assign_workflow_scheme',
  'jira_create_project_issue_type',
  'jira_add_fix_version',
  'jira_remove_fix_version',
  'jira_get_my_profile',
  'jira_search_by_page',
  'jira_search_with_pagination',
  'jira_get_attachments',
  'jira_get_worklogs',
  'jira_get_watchers',
  'jira_add_watcher',
  'jira_remove_watcher',
  'jira_get_resolutions',
  'jira_get_priorities',
  'jira_get_security_levels',
  'jira_export_data',
  'jira_get_board_issues',
  'jira_get_sprints',
];

/// Catalog shape: tool count, declaration order, and integration ownership.
void toolCatalogShapeTests() {
  group('jiraTools catalog', () {
    final tools = jiraTools();

    test('registers the sixty-eight tools in declaration order', () {
      expect(tools.map((t) => t.name), _expectedToolNames);
    });

    test('every tool belongs to the jira integration', () {
      expect(tools.every((t) => t.integration == 'jira'), isTrue);
    });
  });
}

/// `jira_get_ticket` tool shape: alias and parameter declaration.
void jiraGetTicketShapeTests() {
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
}

/// Catalog params: search, comment, label, and status tool parameter shapes.
void toolCatalogParamTests() {
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
