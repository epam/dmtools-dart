import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab repository tools: branches (create/list), tags (create/list), and
/// file content — client method coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  createBranchTests();
  getBranchesTests();
  createTagTests();
  getTagsTests();
  getFileContentTests();
  branchCreateExecutorDispatchTests();
  fileContentExecutorDispatchTests();
  tagExecutorDispatchTests();
  branchListExecutorDispatchTests();
}

/// Canned branch body.
const _branchBody = '{"name":"feature","ref":"main"}';

/// Canned branch-list body.
const _branchesBody = '[{"name":"main"},{"name":"feature"}]';

/// Canned tag body.
const _tagBody = '{"name":"v1.0","ref":"abc123"}';

/// Canned tag-list body.
const _tagsBody = '[{"name":"v1.0"},{"name":"v1.1"}]';

/// Canned file body (base64 content omitted for brevity).
const _fileBody = '{"file_name":"main.dart","ref":"main"}';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_create_branch` — POST /repository/branches.
void createBranchTests() {
  group('GitlabClient.createBranch', () {
    test('POSTs branch and ref to the branches endpoint', () async {
      final f = mockGitlab((o) => routeByPath({'/branches': _branchBody}, o));
      final branch = await f.client.createBranch('1', 'feature', 'main');
      expect(branch?['name'], 'feature');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/repository/branches'));
      expect(
        jsonDecode(call.data as String),
        {'branch': 'feature', 'ref': 'main'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/branches': '[]'}, o));
      expect(await f.client.createBranch('1', 'f', 'main'), isNull);
    });
  });
}

/// `gitlab_get_branches` — GET /repository/branches.
void getBranchesTests() {
  group('GitlabClient.getBranches', () {
    test('returns the decoded branch list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/repository/branches': _branchesBody}, o),
      );
      final branches = await f.client.getBranches('1');
      expect(branches.map((b) => b['name']).toList(), ['main', 'feature']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/repository/branches'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/repository/branches': '{}'}, o),
      );
      expect(await f.client.getBranches('1'), isEmpty);
    });
  });
}

/// `gitlab_create_tag` — POST /repository/tags.
void createTagTests() {
  group('GitlabClient.createTag', () {
    test('POSTs tag_name and ref to the tags endpoint', () async {
      final f =
          mockGitlab((o) => routeByPath({'/repository/tags': _tagBody}, o));
      final tag = await f.client.createTag('1', 'v1.0', 'main');
      expect(tag?['name'], 'v1.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/repository/tags'));
      expect(
        jsonDecode(call.data as String),
        {'tag_name': 'v1.0', 'ref': 'main'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/repository/tags': '[]'}, o));
      expect(await f.client.createTag('1', 'v1.0', 'main'), isNull);
    });
  });
}

/// `gitlab_get_tags` — GET /repository/tags.
void getTagsTests() {
  group('GitlabClient.getTags', () {
    test('returns the decoded tag list', () async {
      final f =
          mockGitlab((o) => routeByPath({'/repository/tags': _tagsBody}, o));
      final tags = await f.client.getTags('1');
      expect(tags.map((t) => t['name']).toList(), ['v1.0', 'v1.1']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/repository/tags'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/repository/tags': '{}'}, o));
      expect(await f.client.getTags('1'), isEmpty);
    });
  });
}

/// `gitlab_get_file_content` — GET /repository/files/{encodedPath}.
void getFileContentTests() {
  group('GitlabClient.getFileContent', () {
    test('GETs the URL-encoded file path', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      final file = await f.client.getFileContent('1', 'src/main.dart');
      expect(file?['file_name'], 'main.dart');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/repository/files/src%2Fmain.dart'),
      );
    });

    test('sends ref as a query parameter when provided', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      await f.client.getFileContent('1', 'src/main.dart', 'develop');
      expect(f.adapter.calls.single.queryParameters['ref'], 'develop');
    });

    test('omits the ref query parameter when not provided', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      await f.client.getFileContent('1', 'src/main.dart');
      expect(
        f.adapter.calls.single.queryParameters.containsKey('ref'),
        isFalse,
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/files/src%2Fmain.dart': '[]'}, o),
      );
      expect(await f.client.getFileContent('1', 'src/main.dart'), isNull);
    });
  });
}

/// [GitlabToolExecutor.execute] routes the branch-create tool.
void branchCreateExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (repository)', () {
    test('gitlab_create_branch routes branch and ref', () async {
      final f = _executor((o) => routeByPath({'/branches': _branchBody}, o));
      await f.executor.execute('gitlab_create_branch', {
        'project': '1',
        'branch': 'feat',
        'ref': 'main',
      });
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'branch': 'feat', 'ref': 'main'},
      );
    });
  });
}

/// [GitlabToolExecutor.execute] routes the file-content tool.
void fileContentExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (repository)', () {
    test('gitlab_get_file_content routes file_path', () async {
      final f = _executor(
        (o) => routeByPath({'/files/src%2Fmain.dart': _fileBody}, o),
      );
      await f.executor.execute('gitlab_get_file_content', {
        'project': '1',
        'file_path': 'src/main.dart',
      });
      expect(
        f.adapter.calls.single.path,
        endsWith('/repository/files/src%2Fmain.dart'),
      );
    });
  });
}

/// [GitlabToolExecutor.execute] routes the tag tools.
void tagExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (repository)', () {
    test('gitlab_create_tag routes tag_name and ref', () async {
      final f =
          _executor((o) => routeByPath({'/repository/tags': _tagBody}, o));
      await f.executor.execute('gitlab_create_tag', {
        'project': '1',
        'tag_name': 'v1.0',
        'ref': 'main',
      });
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'tag_name': 'v1.0', 'ref': 'main'},
      );
    });

    test('gitlab_get_tags routes project', () async {
      final f =
          _executor((o) => routeByPath({'/repository/tags': _tagsBody}, o));
      await f.executor.execute('gitlab_get_tags', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/repository/tags'),
      );
    });
  });
}

/// [GitlabToolExecutor.execute] routes the branch-list tool.
void branchListExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (repository)', () {
    test('gitlab_get_branches routes project', () async {
      final f = _executor(
        (o) => routeByPath({'/repository/branches': _branchesBody}, o),
      );
      await f.executor.execute('gitlab_get_branches', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/repository/branches'),
      );
    });
  });
}
