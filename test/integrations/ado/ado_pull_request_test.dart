import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Pull-request tests: the `git/pullrequests` client methods, tool-catalog
/// shape, and executor routing (reviewers, update, commits, statuses).
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPullRequestReviewersTests();
  addPullRequestReviewerTests();
  updatePullRequestTests();
  getPullRequestCommitsTests();
  getPullRequestStatusesTests();
  createPullRequestStatusTests();
  prCatalogRegistrationTests();
  prCatalogParamShapeTests();
  prReviewerExecutorTests();
  prUpdateExecutorTests();
  prCommitsExecutorTests();
  prStatusExecutorTests();
}

/// The configured project injected by the fixture.
const _project = 'dmtools';

/// Canned pull-request object.
const _pr = '{"pullRequestId":7,"title":"New title"}';

/// Canned commit array.
const _commitArray = '[{"commitId":"abc"}]';

/// Canned status array.
const _statusArray = '[{"id":1,"state":"succeeded"}]';

/// Canned created status object.
const _status = '{"id":1,"state":"succeeded"}';

/// Canned reviewer array.
const _reviewerArray = '[{"id":"r1"}]';

/// Canned reviewer object.
const _reviewer = '{"id":"r1","vote":0}';

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

/// `ado_update_pull_request` — PATCH `git/pullrequests/{prId}`.
void updatePullRequestTests() {
  group('AdoClient.updatePullRequest', () {
    test('PATCHes the pull request with title and description', () async {
      final f = mockAdo((o) => routeByPath({'/pullrequests/7': _pr}, o));
      final result = await f.client.updatePullRequest(
        _project,
        7,
        'New title',
        'New desc',
      );
      expect(result['title'], 'New title');
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.headers['Content-Type'], 'application/json');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/pullrequests/7'),
      );
      expect(
        jsonDecode(call.data as String),
        {'title': 'New title', 'description': 'New desc'},
      );
    });
  });
}

/// `ado_get_pull_request_commits` — GET `git/pullrequests/{prId}/commits`.
void getPullRequestCommitsTests() {
  group('AdoClient.getPullRequestCommits', () {
    test('GETs commits and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/commits': _commitArray}, o));
      final commits = await f.client.getPullRequestCommits(_project, 7);
      expect(commits.single['commitId'], 'abc');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/pullrequests/7/commits'),
      );
    });
  });
}

/// `ado_get_pull_request_statuses` — GET `git/pullrequests/{prId}/statuses`.
void getPullRequestStatusesTests() {
  group('AdoClient.getPullRequestStatuses', () {
    test('GETs statuses and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/statuses': _statusArray}, o));
      final statuses = await f.client.getPullRequestStatuses(_project, 7);
      expect(statuses.single['state'], 'succeeded');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/pullrequests/7/statuses'),
      );
    });
  });
}

/// `ado_create_pull_request_status` — POST `git/pullrequests/{prId}/statuses`.
void createPullRequestStatusTests() {
  group('AdoClient.createPullRequestStatus', () {
    test('POSTs a status and decodes the object', () async {
      final f = mockAdo(
        (o) => o.method == 'POST' ? _status : '[]',
      );
      final result = await f.client.createPullRequestStatus(
        _project,
        7,
        'succeeded',
        'Build passed',
        'ci/build',
      );
      expect(result['state'], 'succeeded');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/git/pullrequests/7/statuses'),
      );
      expect(
        jsonDecode(call.data as String),
        {
          'state': 'succeeded',
          'description': 'Build passed',
          'context': {'name': 'ci/build'},
        },
      );
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-catalog registration for the pull-request tools.
void prCatalogRegistrationTests() {
  group('adoTools catalog (pull requests)', () {
    test('registers all six pull-request tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_get_pull_request_reviewers',
        'ado_add_pull_request_reviewer',
        'ado_update_pull_request',
        'ado_get_pull_request_commits',
        'ado_get_pull_request_statuses',
        'ado_create_pull_request_status',
      ]) {
        expect(names, contains(name));
      }
    });
  });
}

/// Tool-catalog parameter shapes for the pull-request tools.
void prCatalogParamShapeTests() {
  group('adoTools catalog (pull requests)', () {
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

    test('ado_update_pull_request declares project, prId, title, description',
        () {
      final tool = toolNamed('ado_update_pull_request');
      expect(
        tool.params.map((p) => p.name),
        ['project', 'prId', 'title', 'description'],
      );
      expect(tool.params[1].type, 'number');
    });

    test('ado_get_pull_request_commits declares project and numeric prId', () {
      final tool = toolNamed('ado_get_pull_request_commits');
      expect(tool.params.map((p) => p.name), ['project', 'prId']);
      expect(tool.params.last.type, 'number');
    });

    test('ado_get_pull_request_statuses declares project and numeric prId', () {
      final tool = toolNamed('ado_get_pull_request_statuses');
      expect(tool.params.map((p) => p.name), ['project', 'prId']);
      expect(tool.params.last.type, 'number');
    });

    test('ado_create_pull_request_status declares five params', () {
      final tool = toolNamed('ado_create_pull_request_status');
      expect(
        tool.params.map((p) => p.name),
        ['project', 'prId', 'state', 'description', 'context'],
      );
      expect(tool.params[1].type, 'number');
    });
  });
}

/// Serves `[]` for the list GETs, `{}` for mutations.
String _pullRequestRouter(RequestOptions o) => o.method == 'GET' ? '[]' : '{}';

/// [AdoToolExecutor.execute] routing for the reviewer tools.
void prReviewerExecutorTests() {
  late _PullRequestFixture f;

  group('AdoToolExecutor.execute (pull requests)', () {
    setUp(() => f = _pullRequestFixture());

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

/// [AdoToolExecutor.execute] routing for the update tool.
void prUpdateExecutorTests() {
  late _PullRequestFixture f;

  group('AdoToolExecutor.execute (pull requests)', () {
    setUp(() => f = _pullRequestFixture());

    test('routes ado_update_pull_request with numeric prId', () async {
      await f.executor.execute('ado_update_pull_request', {
        'project': 'p',
        'prId': 7,
        'title': 'New title',
        'description': 'New desc',
      });
      expect(f.spy.calls.single, 'updatePullRequest:p:7:New title:New desc');
    });
  });
}

/// [AdoToolExecutor.execute] routing for the commits tool.
void prCommitsExecutorTests() {
  late _PullRequestFixture f;

  group('AdoToolExecutor.execute (pull requests)', () {
    setUp(() => f = _pullRequestFixture());

    test('routes ado_get_pull_request_commits with numeric prId', () async {
      await f.executor.execute(
        'ado_get_pull_request_commits',
        {'project': 'p', 'prId': 7},
      );
      expect(f.spy.calls.single, 'getPullRequestCommits:p:7');
    });
  });
}

/// [AdoToolExecutor.execute] routing for the status tools.
void prStatusExecutorTests() {
  late _PullRequestFixture f;

  group('AdoToolExecutor.execute (pull requests)', () {
    setUp(() => f = _pullRequestFixture());

    test('routes ado_get_pull_request_statuses with numeric prId', () async {
      await f.executor.execute(
        'ado_get_pull_request_statuses',
        {'project': 'p', 'prId': 7},
      );
      expect(f.spy.calls.single, 'getPullRequestStatuses:p:7');
    });

    test('routes ado_create_pull_request_status with all args', () async {
      await f.executor.execute('ado_create_pull_request_status', {
        'project': 'p',
        'prId': 7,
        'state': 'succeeded',
        'description': 'Build passed',
        'context': 'ci/build',
      });
      expect(
        f.spy.calls.single,
        'createPullRequestStatus:p:7:succeeded:Build passed:ci/build',
      );
    });

    test('parses a numeric-string prId on the status tool', () async {
      await f.executor.execute(
        'ado_get_pull_request_statuses',
        {'project': 'p', 'prId': '7'},
      );
      expect(f.spy.calls.single, 'getPullRequestStatuses:p:7');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _PullRequestFixture = ({AdoToolExecutor executor, _PullRequestSpy spy});

/// Builds a [_PullRequestSpy] over the mocked transport and wraps it.
_PullRequestFixture _pullRequestFixture() {
  final spy = _PullRequestSpy(mockAdoHttp(_pullRequestRouter).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched pull-request call then delegates to the real
/// client.
class _PullRequestSpy extends AdoClient {
  _PullRequestSpy(super.http);

  final List<String> calls = [];

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

  @override
  Future<Map<String, dynamic>> updatePullRequest(
    String project,
    int prId,
    String title,
    String description,
  ) {
    calls.add('updatePullRequest:$project:$prId:$title:$description');
    return super.updatePullRequest(project, prId, title, description);
  }

  @override
  Future<List<Map<String, dynamic>>> getPullRequestCommits(
    String project,
    int prId,
  ) {
    calls.add('getPullRequestCommits:$project:$prId');
    return super.getPullRequestCommits(project, prId);
  }

  @override
  Future<List<Map<String, dynamic>>> getPullRequestStatuses(
    String project,
    int prId,
  ) {
    calls.add('getPullRequestStatuses:$project:$prId');
    return super.getPullRequestStatuses(project, prId);
  }

  @override
  Future<Map<String, dynamic>> createPullRequestStatus(
    String project,
    int prId,
    String state,
    String description,
    String context,
  ) {
    calls.add('createPullRequestStatus:$project:$prId:$state'
        ':$description:$context');
    return super.createPullRequestStatus(
      project,
      prId,
      state,
      description,
      context,
    );
  }
}
