import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'bitrise_test_support.dart';

/// Coverage + behavior tests for [BitriseClient] and [BitriseHttpClient].
void main() {
  tearDown(PropertyReader.clearOverrides);
  httpClientTests();
  testConnectionTests();
  getBuildsTests();
  triggerBuildTests();
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
