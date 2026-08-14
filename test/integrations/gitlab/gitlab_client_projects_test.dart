import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab project tools: project details and CI/CD variables — client method
/// coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getProjectDetailsTests();
  getProjectVariablesTests();
  projectExecutorDispatchTests();
}

/// Canned project-details body.
const _projectBody = '{"id":1,"name":"My Project","path_with_namespace":"g/p"}';

/// Canned project-variables body.
const _variablesBody = '[{"key":"VAR","value":"x"},{"key":"CI","value":"1"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_get_project_details` — GET /projects/{id}.
void getProjectDetailsTests() {
  group('GitlabClient.getProjectDetails', () {
    test('GETs the project by id', () async {
      final f =
          mockGitlab((o) => routeByPath({'/projects/1': _projectBody}, o));
      final project = await f.client.getProjectDetails('1');
      expect(project?['name'], 'My Project');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1'),
      );
    });

    test('URL-encodes a group/project path', () async {
      final f =
          mockGitlab((o) => routeByPath({'/projects/g%2Fp': _projectBody}, o));
      await f.client.getProjectDetails('g/p');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/g%2Fp'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/projects/1': '[]'}, o));
      expect(await f.client.getProjectDetails('1'), isNull);
    });
  });
}

/// `gitlab_get_project_variables` — GET /projects/{id}/variables.
void getProjectVariablesTests() {
  group('GitlabClient.getProjectVariables', () {
    test('returns the decoded variables list', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/variables': _variablesBody}, o),
      );
      final vars = await f.client.getProjectVariables('1');
      expect(vars.map((v) => v['key']).toList(), ['VAR', 'CI']);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/variables'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/variables': '{}'}, o));
      expect(await f.client.getProjectVariables('1'), isEmpty);
    });
  });
}

/// [GitlabToolExecutor.execute] routes each project tool name.
void projectExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (projects)', () {
    test('gitlab_get_project_details routes project', () async {
      final f = _executor(
        (o) => routeByPath({'/projects/1': _projectBody}, o),
      );
      await f.executor.execute('gitlab_get_project_details', {'project': '1'});
      expect(f.adapter.calls.single.path, endsWith('/projects/1'));
    });

    test('gitlab_get_project_variables routes project', () async {
      final f = _executor(
        (o) => routeByPath({'/variables': _variablesBody}, o),
      );
      await f.executor
          .execute('gitlab_get_project_variables', {'project': '1'});
      expect(
        f.adapter.calls.single.path,
        endsWith('/projects/1/variables'),
      );
    });
  });
}
