import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Tests for the [gitlabTools] catalog and [GitlabToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  toolCatalogBatch4ParamTests();
  executorDispatchTests();
  batch4ExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    gitlabTools().firstWhere((t) => t.name == name);

/// Expected tool names in declaration order.
const _expectedToolOrder = [
  'gitlab_test',
  'gitlab_get_mr',
  'gitlab_list_mrs',
  'gitlab_create_mr_note',
  'gitlab_merge_mr',
  'gitlab_close_mr',
  'gitlab_get_mr_diff',
  'gitlab_approve_mr',
  'gitlab_unapprove_mr',
  'gitlab_get_mr_notes',
  'gitlab_get_mr_approvals',
  'gitlab_get_mr_discussions',
  'gitlab_trigger_mr_discussion_resolve',
  'gitlab_get_issue',
  'gitlab_create_issue',
  'gitlab_list_issues',
  'gitlab_create_branch',
  'gitlab_get_file_content',
  'gitlab_create_tag',
  'gitlab_get_tags',
  'gitlab_get_branches',
  'gitlab_get_pipelines',
  'gitlab_trigger_pipeline',
  'gitlab_get_pipeline',
  'gitlab_get_project_members',
  'gitlab_get_group_members',
  'gitlab_get_project_details',
  'gitlab_get_project_variables',
  'gitlab_get_mr_pipelines',
  'gitlab_block_mr',
  'gitlab_unblock_mr',
  'gitlab_get_project_hooks',
  'gitlab_add_project_hook',
];

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('gitlabTools catalog', () {
    final tools = gitlabTools();

    test('registers the thirty-three tools in declaration order', () {
      expect(tools.map((t) => t.name), _expectedToolOrder);
    });

    test('every tool belongs to the gitlab integration', () {
      expect(tools.every((t) => t.integration == 'gitlab'), isTrue);
    });
  });

  group('gitlab_get_mr', () {
    final tool = toolNamed('gitlab_get_mr');

    test('declares required project and number iid', () {
      expect(tool.params.map((p) => p.name), ['project', 'iid']);
      expect(tool.params.every((p) => p.required), isTrue);
      expect(tool.params.last.type, 'number');
    });
  });

  group('gitlab_list_mrs', () {
    final tool = toolNamed('gitlab_list_mrs');

    test('requires project with optional state', () {
      expect(tool.params.map((p) => p.name), ['project', 'state']);
      expect(tool.params.first.required, isTrue);
      expect(tool.params.last.required, isFalse);
    });
  });

  group('gitlab_create_mr_note', () {
    final tool = toolNamed('gitlab_create_mr_note');

    test('declares required project, number iid, and body', () {
      expect(tool.params.map((p) => p.name), ['project', 'iid', 'body']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('gitlab_get_issue', () {
    final tool = toolNamed('gitlab_get_issue');

    test('declares required project and number iid', () {
      expect(tool.params.map((p) => p.name), ['project', 'iid']);
      expect(tool.params.every((p) => p.required), isTrue);
      expect(tool.params.last.type, 'number');
    });
  });
}

/// Batch-4 catalog param tests for the new tools.
void toolCatalogBatch4ParamTests() {
  group('gitlab_get_mr_approvals', () {
    final tool = toolNamed('gitlab_get_mr_approvals');

    test('declares required project and number iid', () {
      expect(tool.params.map((p) => p.name), ['project', 'iid']);
      expect(tool.params.every((p) => p.required), isTrue);
      expect(tool.params.last.type, 'number');
    });
  });

  group('gitlab_trigger_mr_discussion_resolve', () {
    final tool = toolNamed('gitlab_trigger_mr_discussion_resolve');

    test('declares project, iid, discussion_id, and resolved', () {
      expect(
        tool.params.map((p) => p.name),
        ['project', 'iid', 'discussion_id', 'resolved'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
      expect(tool.params[1].type, 'number');
      expect(tool.params.last.type, 'boolean');
    });
  });

  group('gitlab_get_project_details', () {
    final tool = toolNamed('gitlab_get_project_details');

    test('declares a single required project param', () {
      expect(tool.params.map((p) => p.name), ['project']);
      expect(tool.params.single.required, isTrue);
      expect(tool.category, 'projects');
    });
  });
}

/// [GitlabToolExecutor.execute] routes each tool name to the right client call.
void executorDispatchTests() {
  group('GitlabToolExecutor.execute', () {
    late _SpyGitlabClient spy;
    late GitlabToolExecutor executor;

    setUp(() {
      spy = _SpyGitlabClient(mockHttp((o) => '{}').http);
      executor = GitlabToolExecutor(spy);
    });

    test('routes gitlab_test to testConnection', () async {
      await executor.execute('gitlab_test', {});
      expect(spy.calls, ['testConnection']);
    });

    test('routes gitlab_get_mr with project and iid', () async {
      await executor.execute('gitlab_get_mr', {
        'project': 'group/proj',
        'iid': 42,
      });
      expect(spy.calls, ['getMr:group/proj:42']);
    });

    test('routes gitlab_list_mrs with project and default state', () async {
      await executor.execute('gitlab_list_mrs', {'project': '1'});
      expect(spy.calls, ['listMrs:1:opened']);
    });

    test('routes gitlab_list_mrs with explicit state', () async {
      await executor
          .execute('gitlab_list_mrs', {'project': '1', 'state': 'merged'});
      expect(spy.calls, ['listMrs:1:merged']);
    });

    test('routes gitlab_create_mr_note with project, iid, and body', () async {
      await executor.execute('gitlab_create_mr_note', {
        'project': '1',
        'iid': 42,
        'body': 'hi',
      });
      expect(spy.calls, ['createMrNote:1:42:hi']);
    });

    test('routes gitlab_get_issue with project and iid', () async {
      await executor.execute('gitlab_get_issue', {
        'project': '1',
        'iid': 7,
      });
      expect(spy.calls, ['getIssue:1:7']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(() => executor.execute('gitlab_no_such', {}), throwsArgumentError);
    });
  });
}

/// Batch-4 executor dispatch tests for the new MR and project tools.
void batch4ExecutorDispatchTests() {
  group('GitlabToolExecutor.execute batch-4', () {
    late _SpyGitlabClient spy;
    late GitlabToolExecutor executor;

    setUp(() {
      spy = _SpyGitlabClient(mockHttp((o) => '{}').http);
      executor = GitlabToolExecutor(spy);
    });

    test('routes gitlab_get_mr_approvals with project and iid', () async {
      await executor.execute('gitlab_get_mr_approvals', {
        'project': '1',
        'iid': 42,
      });
      expect(spy.calls, ['getMrApprovals:1:42']);
    });

    test('routes gitlab_get_mr_discussions with project and iid', () async {
      await executor.execute('gitlab_get_mr_discussions', {
        'project': '1',
        'iid': 42,
      });
      expect(spy.calls, ['getMrDiscussions:1:42']);
    });

    test('routes triggerMrDiscussionResolve with all four params', () async {
      await executor.execute('gitlab_trigger_mr_discussion_resolve', {
        'project': '1',
        'iid': 42,
        'discussion_id': 'd1',
        'resolved': true,
      });
      expect(spy.calls, ['triggerMrDiscussionResolve:1:42:d1:true']);
    });

    test('routes gitlab_get_project_details with project', () async {
      await executor.execute('gitlab_get_project_details', {'project': '1'});
      expect(spy.calls, ['getProjectDetails:1']);
    });

    test('routes gitlab_get_project_variables with project', () async {
      await executor.execute('gitlab_get_project_variables', {'project': '1'});
      expect(spy.calls, ['getProjectVariables:1']);
    });
  });
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyGitlabClient extends GitlabClient {
  _SpyGitlabClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>?> getMr(String project, int iid) {
    calls.add('getMr:$project:$iid');
    return super.getMr(project, iid);
  }

  @override
  Future<List<Map<String, dynamic>>> listMrs(String project,
      [String state = 'opened']) {
    calls.add('listMrs:$project:$state');
    return super.listMrs(project, state);
  }

  @override
  Future<Map<String, dynamic>?> createMrNote(
    String project,
    int iid,
    String body,
  ) {
    calls.add('createMrNote:$project:$iid:$body');
    return super.createMrNote(project, iid, body);
  }

  @override
  Future<Map<String, dynamic>?> getIssue(String project, int iid) {
    calls.add('getIssue:$project:$iid');
    return super.getIssue(project, iid);
  }

  @override
  Future<Map<String, dynamic>?> getMrApprovals(String project, int iid) {
    calls.add('getMrApprovals:$project:$iid');
    return super.getMrApprovals(project, iid);
  }

  @override
  Future<List<Map<String, dynamic>>> getMrDiscussions(
    String project,
    int iid,
  ) {
    calls.add('getMrDiscussions:$project:$iid');
    return super.getMrDiscussions(project, iid);
  }

  @override
  Future<Map<String, dynamic>?> triggerMrDiscussionResolve(
    String project,
    int iid,
    String discussionId,
    bool resolved,
  ) {
    calls.add(
        'triggerMrDiscussionResolve:$project:$iid:$discussionId:$resolved');
    return super
        .triggerMrDiscussionResolve(project, iid, discussionId, resolved);
  }

  @override
  Future<Map<String, dynamic>?> getProjectDetails(String project) {
    calls.add('getProjectDetails:$project');
    return super.getProjectDetails(project);
  }

  @override
  Future<List<Map<String, dynamic>>> getProjectVariables(String project) {
    calls.add('getProjectVariables:$project');
    return super.getProjectVariables(project);
  }
}
