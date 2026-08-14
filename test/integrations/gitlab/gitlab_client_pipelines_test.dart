import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'gitlab_test_support.dart';

/// GitLab project-pipeline tools: list, trigger, and get by id — client
/// method coverage plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPipelinesTests();
  triggerPipelineTests();
  getPipelineTests();
  pipelineExecutorDispatchTests();
}

/// Canned pipeline body.
const _pipelineBody = '{"id":7,"ref":"main","status":"success"}';

/// Canned pipeline-list body.
const _pipelinesBody =
    '[{"id":7,"status":"success"},{"id":8,"status":"failed"}]';

/// Builds a [GitlabToolExecutor] over a mocked [GitlabClient].
({GitlabToolExecutor executor, RoutingAdapter adapter}) _executor(
  String Function(RequestOptions options) router,
) {
  final f = mockGitlab(router);
  return (executor: GitlabToolExecutor(f.client), adapter: f.adapter);
}

/// `gitlab_get_pipelines` — GET /pipelines.
void getPipelinesTests() {
  group('GitlabClient.getPipelines', () {
    test('returns the decoded pipeline list', () async {
      final f =
          mockGitlab((o) => routeByPath({'/pipelines': _pipelinesBody}, o));
      final pipelines = await f.client.getPipelines('1');
      expect(pipelines.map((p) => p['id']).toList(), [7, 8]);
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/pipelines'),
      );
    });

    test('returns empty when body is not an array', () async {
      final f = mockGitlab((o) => routeByPath({'/pipelines': '{}'}, o));
      expect(await f.client.getPipelines('1'), isEmpty);
    });
  });
}

/// `gitlab_trigger_pipeline` — POST /pipeline with ref.
void triggerPipelineTests() {
  group('GitlabClient.triggerPipeline', () {
    test('POSTs the ref to the pipeline trigger endpoint', () async {
      final f = mockGitlab((o) => routeByPath({'/pipeline': _pipelineBody}, o));
      final pipeline = await f.client.triggerPipeline('1', 'main');
      expect(pipeline?['id'], 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/api/v4/projects/1/pipeline'));
      expect(jsonDecode(call.data as String), {'ref': 'main'});
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/pipeline': '[]'}, o));
      expect(await f.client.triggerPipeline('1', 'main'), isNull);
    });
  });
}

/// `gitlab_get_pipeline` — GET /pipelines/{id}.
void getPipelineTests() {
  group('GitlabClient.getPipeline', () {
    test('GETs the pipeline by id', () async {
      final f = mockGitlab(
        (o) => routeByPath({'/pipelines/7': _pipelineBody}, o),
      );
      final pipeline = await f.client.getPipeline('1', 7);
      expect(pipeline?['status'], 'success');
      expect(
        f.adapter.calls.single.path,
        endsWith('/api/v4/projects/1/pipelines/7'),
      );
    });

    test('returns null when the body is not an object', () async {
      final f = mockGitlab((o) => routeByPath({'/pipelines/7': '[]'}, o));
      expect(await f.client.getPipeline('1', 7), isNull);
    });
  });
}

/// [GitlabToolExecutor.execute] routes each pipeline tool name.
void pipelineExecutorDispatchTests() {
  group('GitlabToolExecutor.execute (pipelines)', () {
    test('gitlab_get_pipelines routes project', () async {
      final f =
          _executor((o) => routeByPath({'/pipelines': _pipelinesBody}, o));
      await f.executor.execute('gitlab_get_pipelines', {'project': '1'});
      expect(f.adapter.calls.single.path, endsWith('/projects/1/pipelines'));
    });

    test('gitlab_trigger_pipeline routes project and ref', () async {
      final f = _executor((o) => routeByPath({'/pipeline': _pipelineBody}, o));
      await f.executor.execute(
        'gitlab_trigger_pipeline',
        {'project': '1', 'ref': 'main'},
      );
      expect(
        jsonDecode(f.adapter.calls.single.data as String),
        {'ref': 'main'},
      );
    });

    test('gitlab_get_pipeline routes project and pipeline_id', () async {
      final f = _executor(
        (o) => routeByPath({'/pipelines/7': _pipelineBody}, o),
      );
      await f.executor.execute(
        'gitlab_get_pipeline',
        {'project': '1', 'pipeline_id': 7},
      );
      expect(f.adapter.calls.single.path, endsWith('/projects/1/pipelines/7'));
    });
  });
}
