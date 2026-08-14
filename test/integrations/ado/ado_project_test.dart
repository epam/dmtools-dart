import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Project tests: the org-scoped `projects` client methods, tool-catalog
/// shape, and executor routing (details, properties).
void main() {
  tearDown(PropertyReader.clearOverrides);
  getProjectPropertiesTests();
  getProjectDetailsTests();
  projectCatalogTests();
  projectExecutorTests();
}

/// Canned project-property array.
const _propArray = '[{"name":"key","value":"v"}]';

/// Canned project object.
const _projectObj = '{"id":"proj-1","name":"dmtools","state":"wellFormed"}';

/// `ado_get_project_properties` — GET `projects/{projectId}/properties`.
void getProjectPropertiesTests() {
  group('AdoClient.getProjectProperties', () {
    test('GETs properties org-scoped and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/properties': _propArray}, o));
      final props = await f.client.getProjectProperties('proj-1');
      expect(props.single['name'], 'key');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/_apis/projects/proj-1/properties'));
    });
  });
}

/// `ado_get_project_details` — GET `projects/{projectId}` (org-scoped).
void getProjectDetailsTests() {
  group('AdoClient.getProjectDetails', () {
    test('GETs the project object org-scoped', () async {
      final f =
          mockAdo((o) => routeByPath({'/projects/proj-1': _projectObj}, o));
      final result = await f.client.getProjectDetails('proj-1');
      expect(result['name'], 'dmtools');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/_apis/projects/proj-1'));
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the project tools.
void projectCatalogTests() {
  group('adoTools catalog (projects)', () {
    test('registers both project tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_get_project_details',
        'ado_get_project_properties',
      ]) {
        expect(names, contains(name));
      }
    });

    test('ado_get_project_properties declares projectId', () {
      final tool = toolNamed('ado_get_project_properties');
      expect(tool.params.single.name, 'projectId');
    });

    test('ado_get_project_details declares projectId', () {
      final tool = toolNamed('ado_get_project_details');
      expect(tool.params.single.name, 'projectId');
    });
  });
}

/// Serves a property list for the properties endpoint, an object otherwise.
String _projectRouter(RequestOptions o) =>
    o.path.endsWith('/properties') ? _propArray : _projectObj;

/// [AdoToolExecutor.execute] routing for the project tools.
void projectExecutorTests() {
  late _ProjectFixture f;

  group('AdoToolExecutor.execute (projects)', () {
    setUp(() => f = _projectFixture());

    test('routes ado_get_project_properties with projectId', () async {
      await f.executor.execute(
        'ado_get_project_properties',
        {'projectId': 'proj-1'},
      );
      expect(f.spy.calls.single, 'getProjectProperties:proj-1');
    });

    test('routes ado_get_project_details with projectId', () async {
      await f.executor.execute(
        'ado_get_project_details',
        {'projectId': 'proj-1'},
      );
      expect(f.spy.calls.single, 'getProjectDetails:proj-1');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _ProjectFixture = ({AdoToolExecutor executor, _ProjectSpy spy});

/// Builds a [_ProjectSpy] over the mocked transport and wraps it.
_ProjectFixture _projectFixture() {
  final spy = _ProjectSpy(mockAdoHttp(_projectRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched project call then delegates to the real client.
class _ProjectSpy extends AdoClient {
  _ProjectSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getProjectProperties(String projectId) {
    calls.add('getProjectProperties:$projectId');
    return super.getProjectProperties(projectId);
  }

  @override
  Future<Map<String, dynamic>> getProjectDetails(String projectId) {
    calls.add('getProjectDetails:$projectId');
    return super.getProjectDetails(projectId);
  }
}
