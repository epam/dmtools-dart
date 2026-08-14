import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Build tests: the `build/builds` client methods, tool-catalog shape, and
/// executor routing (list, trigger).
void main() {
  tearDown(PropertyReader.clearOverrides);
  getBuildsTests();
  triggerBuildTests();
  buildCatalogTests();
  buildExecutorTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned build array.
const _buildArray = '[{"id":99,"status":"completed"}]';

/// Canned queued build.
const _queuedBuild = '{"id":99,"status":"queued"}';

/// `ado_get_builds` — GET `build/builds` with an optional definitions filter.
void getBuildsTests() {
  group('AdoClient.getBuilds', () {
    test('GETs builds without a definitions filter by default', () async {
      final f = mockAdo((o) => routeByPath({'/builds': _buildArray}, o));
      final builds = await f.client.getBuilds(_project);
      expect(builds.single['id'], 99);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.queryParameters.containsKey('definitions'), isFalse);
    });

    test('joins the definitions filter into the query parameter', () async {
      final f = mockAdo((o) => routeByPath({'/builds': _buildArray}, o));
      await f.client.getBuilds(_project, [3, 4]);
      expect(f.adapter.calls.single.queryParameters['definitions'], '3,4');
    });
  });
}

/// `ado_trigger_build` — POST `build/builds`.
void triggerBuildTests() {
  group('AdoClient.triggerBuild', () {
    test('POSTs the definition id body and decodes the object', () async {
      final f = mockAdo((o) => routeByPath({'/builds': _queuedBuild}, o));
      final result = await f.client.triggerBuild(7);
      expect(result['status'], 'queued');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/contoso/dmtools/_apis/build/builds'));
      expect(jsonDecode(call.data as String), {
        'definition': {'id': 7},
      });
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the build tools.
void buildCatalogTests() {
  group('adoTools catalog (builds)', () {
    test('registers both build tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in ['ado_get_builds', 'ado_trigger_build']) {
        expect(names, contains(name));
      }
    });

    test('ado_get_builds makes definitions optional', () {
      final tool = toolNamed('ado_get_builds');
      expect(tool.params.map((p) => p.name), ['project', 'definitions']);
      expect(tool.params.last.required, isFalse);
    });

    test('ado_trigger_build declares a numeric definitionId', () {
      final tool = toolNamed('ado_trigger_build');
      expect(tool.params.single.name, 'definitionId');
      expect(tool.params.single.type, 'number');
    });
  });
}

/// Serves method-aware canned bodies: POST queues a build, GET lists them.
String _buildRouter(RequestOptions o) =>
    o.method == 'POST' ? _queuedBuild : _buildArray;

/// [AdoToolExecutor.execute] routing for the build tools.
void buildExecutorTests() {
  late _BuildFixture f;

  group('AdoToolExecutor.execute (builds)', () {
    setUp(() => f = _buildFixture());

    test('routes ado_get_builds with optional definitions', () async {
      await f.executor.execute('ado_get_builds', {
        'project': 'p',
        'definitions': [3],
      });
      expect(f.spy.calls.single, 'getBuilds:p:3');
    });

    test('routes ado_get_builds without definitions', () async {
      await f.executor.execute('ado_get_builds', {'project': 'p'});
      expect(f.spy.calls.single, 'getBuilds:p:');
    });

    test('routes ado_trigger_build with a numeric definitionId', () async {
      await f.executor.execute('ado_trigger_build', {'definitionId': 7});
      expect(f.spy.calls.single, 'triggerBuild:7');
    });

    test('parses a numeric-string definitionId', () async {
      await f.executor.execute('ado_trigger_build', {'definitionId': '7'});
      expect(f.spy.calls.single, 'triggerBuild:7');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _BuildFixture = ({AdoToolExecutor executor, _BuildSpy spy});

/// Builds a [_BuildSpy] over the mocked transport and wraps it.
_BuildFixture _buildFixture() {
  final spy = _BuildSpy(mockAdoHttp(_buildRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched build call then delegates to the real client.
class _BuildSpy extends AdoClient {
  _BuildSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getBuilds(
    String project, [
    List<int>? definitions,
  ]) {
    final d = definitions?.join(',') ?? '';
    calls.add('getBuilds:$project:$d');
    return super.getBuilds(project, definitions);
  }

  @override
  Future<Map<String, dynamic>> triggerBuild(int definitionId) {
    calls.add('triggerBuild:$definitionId');
    return super.triggerBuild(definitionId);
  }
}
