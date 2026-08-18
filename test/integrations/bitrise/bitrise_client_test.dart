import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'bitrise_test_support.dart';

/// Coverage + behavior tests for [BitriseClient] and [BitriseHttpClient].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getAppsTests();
  getBuildsTests();
  getBuildDetailTests();
  triggerBuildTests();
  triggerBuildWithParamsTests();
  abortBuildTests();
  getWorkflowsTests();
  getArtifactsTests();
  getArtifactDetailTests();
}

/// The expected Bearer token produced by the fixture's config.
const _expectedToken = 'bitrise-123';

/// [BitriseHttpClient]: URL building, headers, verbs, and config errors.
void httpClientTests() {
  group('BitriseHttpClient', () {
    test('builds /v0.1 URLs', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.buildUrl('apps'), 'https://bitrise.example.com/v0.1/apps');
    });

    test('assembles Authorization Bearer and Content-Type headers', () {
      final f = mockHttp((o) => '{}');
      expect(f.http.headers['Authorization'], 'Bearer $_expectedToken');
      expect(f.http.headers['Content-Type'], 'application/json');
    });

    test('get/post/put/delete return the response bodies', () async {
      final f = mockHttp((o) => routeByPath({
            '/get': 'GET-BODY',
            '/post': 'POST-BODY',
            '/put': 'PUT-BODY',
            '/del': 'DELETE-BODY',
          }, o));
      expect(await f.http.get('get'), 'GET-BODY');
      expect(await f.http.post('post'), 'POST-BODY');
      expect(await f.http.put('put'), 'PUT-BODY');
      expect(await f.http.delete('del'), 'DELETE-BODY');
      f.http.close();
    });

    test('throws StateError when BITRISE_TOKEN is missing', () {
      PropertyReader.clearOverrides();
      expect(() => BitriseHttpClient(PropertyReader()), throwsStateError);
    });
  });
}

/// `bitrise_test` — connectivity check via GET `apps`.
void testConnectionTests() {
  group('BitriseClient.testConnection', () {
    test('returns success with the app count', () async {
      final f = mockBitrise((o) => routeByPath({'/apps': _appsBody}, o));
      final result = await f.client.testConnection();
      expect(result['success'], isTrue);
      expect(result['message'], 'Bitrise connection successful');
      expect(result['apps'], 2);
      expect(f.adapter.calls.single.path, endsWith('/v0.1/apps'));
    });

    test('reports failure on a non-JSON body', () async {
      final f = mockBitrise((o) => 'not-json');
      final result = await f.client.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], isNotNull);
    });
  });
}

/// `bitrise_get_builds` — GET `apps/{slug}/builds`.
void getBuildsTests() {
  group('BitriseClient.getBuilds', () {
    test('returns the decoded builds object', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': _buildsBody}, o));
      final builds = await f.client.getBuilds('app-slug-1');
      expect(builds['data'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v0.1/apps/app-slug-1/builds'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': '[1, 2]'}, o));
      expect(await f.client.getBuilds('app-slug-1'), isEmpty);
    });
  });
}

/// `bitrise_trigger_build` — POST `apps/{slug}/builds`.
void triggerBuildTests() {
  group('BitriseClient.triggerBuild', () {
    test('POSTs build params and returns the decoded object', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': _triggerBody}, o));
      final result = await f.client.triggerBuild('app-slug-1');
      expect(result?['status'], 'ok');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/v0.1/apps/app-slug-1/builds'));
      expect(jsonDecode(call.data as String), {'build_params': {}});
    });

    test('returns null when the response is not an object', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': '[1]'}, o));
      expect(await f.client.triggerBuild('app-slug-1'), isNull);
    });
  });
}

/// Canned `apps` response body (an array of app objects).
const _appsBody = '[{"slug":"app-1"},{"slug":"app-2"}]';

/// Canned builds response body.
const _buildsBody = '{"data":[{"slug":"b1"},{"slug":"b2"}],"paging":{}}';

/// Canned trigger-build response body.
const _triggerBody = '{"status":"ok","build_slug":"b1"}';

/// `bitrise_get_apps` — GET `apps`.
void getAppsTests() {
  group('BitriseClient.getApps', () {
    test('returns the decoded list of apps', () async {
      final f = mockBitrise((o) => routeByPath({'/apps': _appsBody}, o));
      final apps = await f.client.getApps();
      expect(apps.map((a) => a['slug']).toList(), ['app-1', 'app-2']);
      expect(f.adapter.calls.single.path, endsWith('/v0.1/apps'));
    });

    test('returns empty list when the body is not an array', () async {
      final f = mockBitrise((o) => routeByPath({'/apps': '{"x":1}'}, o));
      expect(await f.client.getApps(), isEmpty);
    });
  });
}

/// `bitrise_get_build_detail` — GET `apps/{appSlug}/builds/{buildSlug}`.
void getBuildDetailTests() {
  group('BitriseClient.getBuildDetail', () {
    test('returns the decoded build object', () async {
      final f = mockBitrise(
        (o) => routeByPath({'/builds/build-2': _detailBody}, o),
      );
      final detail = await f.client.getBuildDetail('app-1', 'build-2');
      expect(detail?['slug'], 'build-2');
      expect(
        f.adapter.calls.single.path,
        endsWith('/v0.1/apps/app-1/builds/build-2'),
      );
    });

    test('returns null when the response is not an object', () async {
      final f = mockBitrise(
        (o) => routeByPath({'/builds/build-2': '[1]'}, o),
      );
      expect(await f.client.getBuildDetail('app-1', 'build-2'), isNull);
    });
  });
}

/// `bitrise_trigger_build_with_params` — POST `apps/{appSlug}/builds`.
void triggerBuildWithParamsTests() {
  group('BitriseClient.triggerBuildWithParams', () {
    test('POSTs workflow_id and environments in build_params', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': _triggerBody}, o));
      final result = await f.client.triggerBuildWithParams(
        'app-1',
        'primary',
        [
          {'mapped_to': 'ENV', 'value': 'prod'},
        ],
      );
      expect(result?['status'], 'ok');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/v0.1/apps/app-1/builds'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      final params = decoded['build_params'] as Map<String, dynamic>;
      expect(params['workflow_id'], 'primary');
      expect(params['environments'], [
        {'mapped_to': 'ENV', 'value': 'prod'},
      ]);
    });

    test('omits environments key when null', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': _triggerBody}, o));
      await f.client.triggerBuildWithParams('app-1', 'primary', null);
      final decoded = jsonDecode(f.adapter.calls.single.data as String);
      final params = (decoded as Map<String, dynamic>)['build_params'];
      expect(params, {'workflow_id': 'primary'});
    });

    test('returns null when the response is not an object', () async {
      final f = mockBitrise((o) => routeByPath({'/builds': '[1]'}, o));
      expect(
        await f.client.triggerBuildWithParams('app-1', 'primary', null),
        isNull,
      );
    });
  });
}

/// Canned build-detail response body.
const _detailBody = '{"slug":"build-2","status":1}';

/// `bitrise_abort_build` — POST `apps/{appSlug}/builds/{buildSlug}/abort`.
void abortBuildTests() {
  group('BitriseClient.abortBuild', () {
    test('POSTs the abort and returns the decoded object', () async {
      final f = mockBitrise((o) => routeByPath({'/abort': _abortBody}, o));
      final result = await f.client.abortBuild('app-1', 'build-2');
      expect(result?['status'], 'ok');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/v0.1/apps/app-1/builds/build-2/abort'));
    });

    test('returns null when the response is not an object', () async {
      final f = mockBitrise((o) => routeByPath({'/abort': '[1]'}, o));
      expect(await f.client.abortBuild('app-1', 'build-2'), isNull);
    });
  });
}

/// Canned abort-build response body.
const _abortBody = '{"status":"ok","build_slug":"build-2"}';

/// `bitrise_get_workflows` — GET `apps/{appSlug}/build-slots`.
void getWorkflowsTests() {
  group('BitriseClient.getWorkflows', () {
    test('returns the decoded workflows object', () async {
      final f =
          mockBitrise((o) => routeByPath({'/build-slots': _workflowsBody}, o));
      final workflows = await f.client.getWorkflows('app-1');
      expect(workflows['data'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v0.1/apps/app-1/build-slots'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockBitrise((o) => routeByPath({'/build-slots': '[1, 2]'}, o));
      expect(await f.client.getWorkflows('app-1'), isEmpty);
    });
  });
}

/// `bitrise_get_artifacts` — GET `apps/{appSlug}/builds/{buildSlug}/artifacts`.
void getArtifactsTests() {
  group('BitriseClient.getArtifacts', () {
    test('returns the decoded artifacts object', () async {
      final f = mockBitrise(
        (o) => routeByPath({'/artifacts': _artifactsBody}, o),
      );
      final artifacts = await f.client.getArtifacts('app-1', 'build-2');
      expect(artifacts['data'], isA<List>());
      expect(
        f.adapter.calls.single.path,
        endsWith('/v0.1/apps/app-1/builds/build-2/artifacts'),
      );
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockBitrise((o) => routeByPath({'/artifacts': '[1, 2]'}, o));
      expect(await f.client.getArtifacts('app-1', 'build-2'), isEmpty);
    });
  });
}

/// Canned workflows response body.
const _workflowsBody =
    '{"data":[{"workflow":"primary"},{"workflow":"deploy"}]}';

/// Canned artifacts response body.
const _artifactsBody =
    '{"data":[{"slug":"a1","title":"app.apk"},{"slug":"a2","title":"log.txt"}],'
    '"paging":{}}';

/// `bitrise_get_artifact_detail` — GET
/// `apps/{appSlug}/builds/{buildSlug}/artifacts/{artifactSlug}`.
void getArtifactDetailTests() {
  group('BitriseClient.getArtifactDetail', () {
    test('returns the decoded artifact object', () async {
      final f = mockBitrise(
        (o) => routeByPath({'/artifacts/art-1': _artifactDetailBody}, o),
      );
      final detail =
          await f.client.getArtifactDetail('app-1', 'build-2', 'art-1');
      expect(detail?['slug'], 'art-1');
      expect(detail?['title'], 'app.apk');
      expect(
        f.adapter.calls.single.path,
        endsWith('/v0.1/apps/app-1/builds/build-2/artifacts/art-1'),
      );
    });

    test('returns null when the response is not an object', () async {
      final f = mockBitrise(
        (o) => routeByPath({'/artifacts/art-1': '[1]'}, o),
      );
      expect(
        await f.client.getArtifactDetail('app-1', 'build-2', 'art-1'),
        isNull,
      );
    });
  });
}

/// Canned artifact-detail response body.
const _artifactDetailBody =
    '{"slug":"art-1","title":"app.apk","expiring":true}';
