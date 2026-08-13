import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Batch-3 tests: the eight ADO client/tools added after batch 2
/// (work-item revisions, teams, team members, project properties,
/// repo branches, commits, pull-request reviewers).
void main() {
  tearDown(PropertyReader.clearOverrides);
  getWorkItemRevisionsTests();
  getTeamsTests();
  getTeamMembersTests();
  getProjectPropertiesTests();
  getRepoBranchesTests();
  getCommitsTests();
  getPullRequestReviewersTests();
  addPullRequestReviewerTests();
  batch3CatalogTests();
  batch3ExecutorTests();
  batch3ExecutorReviewTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned revision array.
const _revArray = '[{"rev":1},{"rev":2}]';

/// Canned team array.
const _teamArray = '[{"id":"t1","name":"Squad"}]';

/// Canned member array.
const _memberArray = '[{"id":"u1"}]';

/// Canned project-property array.
const _propArray = '[{"name":"key","value":"v"}]';

/// Canned branch-stat array.
const _branchArray = '[{"name":"main"}]';

/// Canned commit array.
const _commitArray = '[{"commitId":"abc"}]';

/// Canned reviewer array.
const _reviewerArray = '[{"id":"r1"}]';

/// Canned reviewer object.
const _reviewer = '{"id":"r1","vote":0}';

/// `ado_get_work_item_revisions` — GET `wit/workitems/{id}/revisions`.
void getWorkItemRevisionsTests() {
  group('AdoClient.getWorkItemRevisions', () {
    test('GETs revisions and decodes the list', () async {
      final f = mockAdo(
        (o) => routeByPath({'/workitems/42/revisions': _revArray}, o),
      );
      final revs = await f.client.getWorkItemRevisions(42);
      expect(revs.map((r) => r['rev']).toList(), [1, 2]);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/wit/workitems/42/revisions'),
      );
    });
  });
}

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

/// `ado_get_repo_branches` — GET `git/repositories/{repoId}/stats/branches`.
void getRepoBranchesTests() {
  group('AdoClient.getRepoBranches', () {
    test('GETs branch stats and decodes the list', () async {
      final f = mockAdo(
        (o) => routeByPath({'/stats/branches': _branchArray}, o),
      );
      final branches = await f.client.getRepoBranches(_project, 'repo-1');
      expect(branches.single['name'], 'main');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith(
            '/contoso/dmtools/_apis/git/repositories/repo-1/stats/branches'),
      );
    });
  });
}

/// `ado_get_commits` — POST commitsbatch with criteria, else GET commits.
void getCommitsTests() {
  group('AdoClient.getCommits', () {
    test('GETs commits when no search criteria are given', () async {
      final f = mockAdo((o) => routeByPath({'/commits': _commitArray}, o));
      final commits = await f.client.getCommits(_project, 'repo-1');
      expect(commits.single['commitId'], 'abc');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/repositories/repo-1/commits'),
      );
    });

    test('POSTs commitsbatch with the criteria as the body', () async {
      final f = mockAdo((o) => routeByPath({'/commitsbatch': _commitArray}, o));
      await f.client.getCommits(
        _project,
        'repo-1',
        <String, dynamic>{'fromDate': '2024-01-01'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith(
          '/contoso/dmtools/_apis/git/repositories/repo-1/commitsbatch',
        ),
      );
      expect(jsonDecode(call.data as String), {'fromDate': '2024-01-01'});
    });
  });
}

/// `ado_get_pull_request_reviewers` — GET
/// `git/pullrequests/{prId}/reviewers`.
void getPullRequestReviewersTests() {
  group('AdoClient.getPullRequestReviewers', () {
    test('GETs reviewers and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/reviewers': _reviewerArray}, o));
      final reviewers = await f.client.getPullRequestReviewers(_project, 7);
      expect(reviewers.single['id'], 'r1');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/pullrequests/7/reviewers'),
      );
    });
  });
}

/// `ado_add_pull_request_reviewer` — PUT
/// `git/pullrequests/{prId}/reviewers/{reviewerId}`.
void addPullRequestReviewerTests() {
  group('AdoClient.addPullRequestReviewer', () {
    test('PUTs the reviewer endpoint and decodes the object', () async {
      final f = mockAdo((o) => routeByPath({'/guid-9': _reviewer}, o));
      final result =
          await f.client.addPullRequestReviewer(_project, 7, 'guid-9');
      expect(result['id'], 'r1');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/pullrequests/7/reviewers/guid-9'),
      );
      expect(call.queryParameters['api-version'], '7.0');
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the batch-3 tools.
void batch3CatalogTests() {
  group('adoTools catalog (batch 3)', () {
    test('registers all eight batch-3 tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_get_work_item_revisions',
        'ado_get_teams',
        'ado_get_team_members',
        'ado_get_project_properties',
        'ado_get_repo_branches',
        'ado_get_commits',
        'ado_get_pull_request_reviewers',
        'ado_add_pull_request_reviewer',
      ]) {
        expect(names, contains(name));
      }
    });

    test('ado_get_work_item_revisions declares a numeric id', () {
      final tool = toolNamed('ado_get_work_item_revisions');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.type, 'number');
    });

    test('ado_get_team_members declares project and teamId', () {
      final tool = toolNamed('ado_get_team_members');
      expect(tool.params.map((p) => p.name), ['project', 'teamId']);
    });

    test('ado_get_project_properties declares projectId', () {
      final tool = toolNamed('ado_get_project_properties');
      expect(tool.params.single.name, 'projectId');
    });

    test('ado_get_commits makes searchCriteria an optional object', () {
      final tool = toolNamed('ado_get_commits');
      expect(
        tool.params.map((p) => p.name),
        ['project', 'repoId', 'searchCriteria'],
      );
      final criteria = tool.params.last;
      expect(criteria.type, 'object');
      expect(criteria.required, isFalse);
    });

    test('ado_get_pull_request_reviewers declares a numeric prId', () {
      final tool = toolNamed('ado_get_pull_request_reviewers');
      expect(tool.params.map((p) => p.name), ['project', 'prId']);
      expect(tool.params.last.type, 'number');
    });

    test('ado_add_pull_request_reviewer declares prId and reviewerId', () {
      final tool = toolNamed('ado_add_pull_request_reviewer');
      expect(
        tool.params.map((p) => p.name),
        ['project', 'prId', 'reviewerId'],
      );
    });
  });
}

/// Serves `[]` for list endpoints, `{}` for the single PUT reviewer.
String _batch3Router(RequestOptions o) => o.method == 'PUT' ? '{}' : '[]';

/// [AdoToolExecutor.execute] routing for the batch-3 tools.
void batch3ExecutorTests() {
  late _Batch3Fixture f;

  group('AdoToolExecutor.execute (batch 3)', () {
    setUp(() => f = _batch3Fixture());

    test('routes ado_get_work_item_revisions with id', () async {
      await f.executor.execute('ado_get_work_item_revisions', {'id': 42});
      expect(f.spy.calls.single, 'getWorkItemRevisions:42');
    });

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

    test('routes ado_get_project_properties with projectId', () async {
      await f.executor.execute(
        'ado_get_project_properties',
        {'projectId': 'proj-1'},
      );
      expect(f.spy.calls.single, 'getProjectProperties:proj-1');
    });

    test('routes ado_get_repo_branches with project and repoId', () async {
      await f.executor.execute(
        'ado_get_repo_branches',
        {'project': 'p', 'repoId': 'r'},
      );
      expect(f.spy.calls.single, 'getRepoBranches:p:r');
    });
  });
}

/// [AdoToolExecutor.execute] routing for batch-3 commit and reviewer tools.
void batch3ExecutorReviewTests() {
  late _Batch3Fixture f;

  group('AdoToolExecutor.execute (batch 3: commits & reviewers)', () {
    setUp(() => f = _batch3Fixture());

    test('routes ado_get_commits without searchCriteria', () async {
      await f.executor
          .execute('ado_get_commits', {'project': 'p', 'repoId': 'r'});
      expect(f.spy.calls.single, 'getCommits:p:r:null');
    });

    test('routes ado_get_commits with searchCriteria map', () async {
      await f.executor.execute('ado_get_commits', {
        'project': 'p',
        'repoId': 'r',
        'searchCriteria': <String, dynamic>{'fromDate': '2024-01-01'},
      });
      expect(f.spy.calls.single, 'getCommits:p:r:{fromDate: 2024-01-01}');
    });

    test('routes ado_get_pull_request_reviewers with numeric prId', () async {
      await f.executor.execute(
        'ado_get_pull_request_reviewers',
        {'project': 'p', 'prId': 7},
      );
      expect(f.spy.calls.single, 'getPullRequestReviewers:p:7');
    });

    test('parses a numeric-string prId', () async {
      await f.executor.execute(
        'ado_get_pull_request_reviewers',
        {'project': 'p', 'prId': '7'},
      );
      expect(f.spy.calls.single, 'getPullRequestReviewers:p:7');
    });

    test('routes ado_add_pull_request_reviewer with prId and reviewerId',
        () async {
      await f.executor.execute('ado_add_pull_request_reviewer', {
        'project': 'p',
        'prId': 7,
        'reviewerId': 'guid-9',
      });
      expect(f.spy.calls.single, 'addPullRequestReviewer:p:7:guid-9');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _Batch3Fixture = ({AdoToolExecutor executor, _Batch3Spy spy});

/// Builds a [_Batch3Spy] over the mocked transport and wraps it.
_Batch3Fixture _batch3Fixture() {
  final spy = _Batch3Spy(mockAdoHttp(_batch3Router).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched batch-3 call then delegates to the real client.
class _Batch3Spy extends AdoClient {
  _Batch3Spy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getWorkItemRevisions(int id) {
    calls.add('getWorkItemRevisions:$id');
    return super.getWorkItemRevisions(id);
  }

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

  @override
  Future<List<Map<String, dynamic>>> getProjectProperties(String projectId) {
    calls.add('getProjectProperties:$projectId');
    return super.getProjectProperties(projectId);
  }

  @override
  Future<List<Map<String, dynamic>>> getRepoBranches(
    String project,
    String repoId,
  ) {
    calls.add('getRepoBranches:$project:$repoId');
    return super.getRepoBranches(project, repoId);
  }

  @override
  Future<List<Map<String, dynamic>>> getCommits(
    String project,
    String repoId, [
    Map<String, dynamic>? searchCriteria,
  ]) {
    calls.add('getCommits:$project:$repoId:$searchCriteria');
    return super.getCommits(project, repoId, searchCriteria);
  }

  @override
  Future<List<Map<String, dynamic>>> getPullRequestReviewers(
    String project,
    int prId,
  ) {
    calls.add('getPullRequestReviewers:$project:$prId');
    return super.getPullRequestReviewers(project, prId);
  }

  @override
  Future<Map<String, dynamic>> addPullRequestReviewer(
    String project,
    int prId,
    String reviewerId,
  ) {
    calls.add('addPullRequestReviewer:$project:$prId:$reviewerId');
    return super.addPullRequestReviewer(project, prId, reviewerId);
  }
}
