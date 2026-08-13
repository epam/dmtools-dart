import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// Tests for the [gitlabTools] catalog and [GitlabToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  executorDispatchTests();
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
  'gitlab_get_issue',
  'gitlab_create_issue',
  'gitlab_list_issues',
  'gitlab_create_branch',
  'gitlab_get_file_content',
  'gitlab_get_project_members',
];

/// Catalog shape: tool count, order, integration, params.
void toolCatalogTests() {
  group('gitlabTools catalog', () {
    final tools = gitlabTools();

    test('registers the thirteen tools in declaration order', () {
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
}
