import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Team tests: the `projects/{project}/teams` client methods,
/// tool-catalog shape, and executor routing (teams, members).
void main() {
  tearDown(PropertyReader.clearOverrides);
  getTeamsTests();
  getTeamMembersTests();
  teamCatalogTests();
  teamExecutorTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned team array.
const _teamArray = '[{"id":"t1","name":"Squad"}]';

/// Canned member array.
const _memberArray = '[{"id":"u1"}]';

/// `ado_get_teams` — GET `projects/{project}/teams` (org-scoped).
void getTeamsTests() {
  group('AdoClient.getTeams', () {
    test('GETs teams org-scoped and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/teams': _teamArray}, o));
      final teams = await f.client.getTeams(_project);
      expect(teams.single['name'], 'Squad');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/contoso/_apis/projects/dmtools/teams'));
    });
  });
}

/// `ado_get_team_members` — GET `projects/{project}/teams/{teamId}/members`.
void getTeamMembersTests() {
  group('AdoClient.getTeamMembers', () {
    test('GETs members org-scoped and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/members': _memberArray}, o));
      final members = await f.client.getTeamMembers(_project, 'abc');
      expect(members.single['id'], 'u1');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/_apis/projects/dmtools/teams/abc/members'),
      );
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the team tools.
void teamCatalogTests() {
  group('adoTools catalog (teams)', () {
    test('registers both team tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in ['ado_get_teams', 'ado_get_team_members']) {
        expect(names, contains(name));
      }
    });

    test('ado_get_team_members declares project and teamId', () {
      final tool = toolNamed('ado_get_team_members');
      expect(tool.params.map((p) => p.name), ['project', 'teamId']);
    });
  });
}

/// Serves `[]` — both team endpoints decode lists.
String _teamRouter(RequestOptions o) => '[]';

/// [AdoToolExecutor.execute] routing for the team tools.
void teamExecutorTests() {
  late _TeamFixture f;

  group('AdoToolExecutor.execute (teams)', () {
    setUp(() => f = _teamFixture());

    test('routes ado_get_teams with the project', () async {
      await f.executor.execute('ado_get_teams', {'project': 'p'});
      expect(f.spy.calls.single, 'getTeams:p');
    });

    test('routes ado_get_team_members with project and teamId', () async {
      await f.executor.execute(
        'ado_get_team_members',
        {'project': 'p', 'teamId': 't'},
      );
      expect(f.spy.calls.single, 'getTeamMembers:p:t');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _TeamFixture = ({AdoToolExecutor executor, _TeamSpy spy});

/// Builds a [_TeamSpy] over the mocked transport and wraps it.
_TeamFixture _teamFixture() {
  final spy = _TeamSpy(mockAdoHttp(_teamRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched team call then delegates to the real client.
class _TeamSpy extends AdoClient {
  _TeamSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getTeams(String project) {
    calls.add('getTeams:$project');
    return super.getTeams(project);
  }

  @override
  Future<List<Map<String, dynamic>>> getTeamMembers(
    String project,
    String teamId,
  ) {
    calls.add('getTeamMembers:$project:$teamId');
    return super.getTeamMembers(project, teamId);
  }
}
