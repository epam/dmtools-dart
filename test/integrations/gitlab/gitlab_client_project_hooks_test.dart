import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab project-webhook tools: list and add — [GitlabClient] methods plus
/// [GitlabToolExecutor] dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getProjectHooksTests();
  addProjectHookTests();
  projectHookExecutorDispatchTests();
}

/// Canned project-hooks body.
const _hooksBody =
    '[{"id":1,"url":"https://a.example/hook"},{"id":2,"url":"https://b.example/hook"}]';

/// Canned created project-hook body.
const _hookBody = '{"id":3,"url":"https://c.example/hook"}';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_get_project_hooks` — GET /projects/{id}/hooks.
void getProjectHooksTests() {
  group('GitlabClient.getProjectHooks', () {
    test('returns the decoded hooks list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/hooks': _hooksBody}, o),
      );
      final hooks = await f.client.getProjectHooks('1');
      expect(hooks.map((h) => h['id']).toList(), [1, 2]);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/hooks'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/hooks': '{}'}, o));
      expect(await f.client.getProjectHooks('1'), isEmpty);
    });
  });
}

/// `gitlab_add_project_hook` — POST /projects/{id}/hooks.
void addProjectHookTests() {
  group('GitlabClient.addProjectHook', () {
    test('POSTs the hook URL and returns the created hook', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/hooks': _hookBody}, o),
      );
      final hook = await f.client.addProjectHook(
        '1',
        'https://c.example/hook',
      );
      expect(hook?['id'], 3);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/api/v4/projects/1/hooks'),
      );
      expect(
        jsonDecode(call.data as String),
        {'url': 'https://c.example/hook'},
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/hooks': '[]'}, o));
      expect(await f.client.addProjectHook('1', 'https://x.example'), isNull);
    });
  });
}

/// [GitlabToolExecutor.execute] routes each project-webhook tool name.
void projectHookExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (project hooks)', () {
    test('gitlab_get_project_hooks routes project', () async {
      final f = _executor((o) => routeByPath({'/hooks': _hooksBody}, o));
      await f.executor.execute('gitlab_get_project_hooks', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/hooks'),
      );
    });

    test('gitlab_add_project_hook routes project and url', () async {
      final f = _executor((o) => routeByPath({'/hooks': _hookBody}, o));
      await f.executor.execute('gitlab_add_project_hook', {
        'project': '1',
        'url': 'https://c.example/hook',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/projects/1/hooks'));
      expect(
        jsonDecode(call.data as String),
        {'url': 'https://c.example/hook'},
      );
    });
  });
}
