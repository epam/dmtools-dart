import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Tests for the [githubTools] catalog and [GithubToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogOrderTests();
  catalogParamTests();
  executorRoutingTests();
  executorMutationTests();
  executorEdgeCaseTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    githubTools().firstWhere((t) => t.name == name);

/// Expected tool names in declaration order.
const _githubToolNames = [
  'github_test',
  'github_get_repo',
  'github_get_tree',
  'github_get_pr',
  'github_list_prs',
  'github_create_pr',
  'github_merge_pr',
  'github_close_pr',
  'github_reopen_pr',
  'github_get_pr_diff',
  'github_get_pr_files',
  'github_update_pr',
  'github_request_reviewers',
  'github_create_review',
  'github_dismiss_review',
  'github_create_comment',
  'github_get_issue',
  'github_create_issue',
  'github_close_issue',
  'github_add_labels',
  'github_remove_label',
  'github_list_branches',
  'github_create_branch',
  'github_delete_branch',
  'github_get_file_content',
  'github_update_file',
  'github_list_releases',
  'github_get_release',
  'github_create_release',
  'github_get_commit',
  'github_list_commits',
  'github_get_workflow_runs',
  'github_rerun_workflow',
  'github_get_check_runs',
];

/// Serves `[]` for the PR-list GET (expects a JSON array), `{}` otherwise.
String _spyRouter(RequestOptions o) {
  if (o.method == 'GET' && o.path.endsWith('/pulls')) return '[]';
  return '{}';
}

/// Catalog shape: tool count, order, integration, and the PR tool params.
void catalogOrderTests() {
  group('githubTools catalog', () {
    final tools = githubTools();

    test('registers the thirty-four tools in declaration order', () {
      expect(tools.map((t) => t.name), _githubToolNames);
    });

    test('every tool belongs to the github integration', () {
      expect(tools.every((t) => t.integration == 'github'), isTrue);
    });
  });

  group('github_get_pr', () {
    final tool = toolNamed('github_get_pr');

    test('declares required owner, repo, number', () {
      expect(tool.params.map((p) => p.name), ['owner', 'repo', 'number']);
      expect(tool.params.every((p) => p.required), isTrue);
      expect(tool.params.last.type, 'number');
    });
  });

  group('github_list_prs', () {
    final tool = toolNamed('github_list_prs');

    test('makes state optional', () {
      expect(tool.params.map((p) => p.name), ['owner', 'repo', 'state']);
      expect(tool.params.last.required, isFalse);
    });
  });
}

/// Catalog shape for the comment and issue tools.
void catalogParamTests() {
  group('github_create_pr', () {
    final tool = toolNamed('github_create_pr');

    test('declares required owner, repo, title, head, base', () {
      expect(
        tool.params.map((p) => p.name),
        ['owner', 'repo', 'title', 'head', 'base'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('github_create_comment', () {
    final tool = toolNamed('github_create_comment');

    test('declares required owner, repo, number, body', () {
      expect(
        tool.params.map((p) => p.name),
        ['owner', 'repo', 'number', 'body'],
      );
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });

  group('github_get_issue', () {
    final tool = toolNamed('github_get_issue');

    test('declares required owner, repo, number', () {
      expect(tool.params.map((p) => p.name), ['owner', 'repo', 'number']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [GithubToolExecutor.execute] routes read tool names to client calls.
void executorRoutingTests() {
  late _ExecutorFixture f;

  group('GithubToolExecutor.execute', () {
    setUp(() => f = _executorFixture());

    test('routes github_test to testConnection', () async {
      await f.executor.execute('github_test', {});
      expect(f.spy.calls, ['testConnection']);
    });

    test('routes github_get_pr with owner, repo, number', () async {
      await f.executor.execute('github_get_pr', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'number': 42,
      });
      expect(f.spy.calls, ['getPr:epm:dm.ai:42']);
    });

    test('routes github_list_prs with owner, repo, state', () async {
      await f.executor.execute('github_list_prs', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'state': 'closed',
      });
      expect(f.spy.calls, ['listPrs:epm:dm.ai:closed']);
    });
  });
}

/// [GithubToolExecutor.execute] routes mutation/read tool names to client calls.
void executorMutationTests() {
  late _ExecutorFixture f;

  group('GithubToolExecutor.execute (mutations)', () {
    setUp(() => f = _executorFixture());

    test('routes github_create_comment with owner, repo, number, body',
        () async {
      await f.executor.execute('github_create_comment', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'number': 42,
        'body': 'hi',
      });
      expect(f.spy.calls, ['createComment:epm:dm.ai:42:hi']);
    });

    test('routes github_get_issue with owner, repo, number', () async {
      await f.executor.execute('github_get_issue', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'number': 7,
      });
      expect(f.spy.calls, ['getIssue:epm:dm.ai:7']);
    });

    test('routes github_create_pr with owner, repo, title, head, base',
        () async {
      await f.executor.execute('github_create_pr', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'title': 'Fix bug',
        'head': 'feature',
        'base': 'main',
      });
      expect(f.spy.calls, ['createPr:epm:dm.ai:Fix bug:feature:main']);
    });
  });
}

/// [GithubToolExecutor.execute] argument-coercion and error cases.
void executorEdgeCaseTests() {
  late _ExecutorFixture f;

  group('GithubToolExecutor.execute (edge cases)', () {
    setUp(() => f = _executorFixture());

    test('parses number from a numeric string', () async {
      await f.executor.execute('github_get_pr', {
        'owner': 'epm',
        'repo': 'dm.ai',
        'number': '42',
      });
      expect(f.spy.calls, ['getPr:epm:dm.ai:42']);
    });

    test('throws ArgumentError for an unknown tool', () {
      expect(
        () => f.executor.execute('github_no_such', {}),
        throwsArgumentError,
      );
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _ExecutorFixture = ({
  GithubToolExecutor executor,
  _SpyGithubClient spy
});

/// Builds a [_SpyGithubClient] over the mocked transport and wraps it.
_ExecutorFixture _executorFixture() {
  final spy = _SpyGithubClient(mockGithubHttp(_spyRouter).http);
  return (executor: GithubToolExecutor(spy), spy: spy);
}

/// Records every dispatched call then delegates to the real client logic.
class _SpyGithubClient extends GithubClient {
  _SpyGithubClient(super.http);

  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> testConnection() {
    calls.add('testConnection');
    return super.testConnection();
  }

  @override
  Future<Map<String, dynamic>> getPr(String owner, String repo, int number) {
    calls.add('getPr:$owner:$repo:$number');
    return super.getPr(owner, repo, number);
  }

  @override
  Future<List<Map<String, dynamic>>> listPrs(
    String owner,
    String repo, [
    String? state,
  ]) {
    calls.add('listPrs:$owner:$repo:$state');
    return super.listPrs(owner, repo, state);
  }

  @override
  Future<Map<String, dynamic>> createComment(
    String owner,
    String repo,
    int number,
    String body,
  ) {
    calls.add('createComment:$owner:$repo:$number:$body');
    return super.createComment(owner, repo, number, body);
  }

  @override
  Future<Map<String, dynamic>> getIssue(String owner, String repo, int number) {
    calls.add('getIssue:$owner:$repo:$number');
    return super.getIssue(owner, repo, number);
  }

  @override
  Future<Map<String, dynamic>> createPr(
    String owner,
    String repo,
    String title,
    String head,
    String base,
  ) {
    calls.add('createPr:$owner:$repo:$title:$head:$base');
    return super.createPr(owner, repo, title, head, base);
  }
}
