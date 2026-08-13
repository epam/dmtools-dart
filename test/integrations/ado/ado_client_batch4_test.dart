import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'ado_test_support.dart';

/// Batch-4 tests: the six ADO client/tools added after batch 3
/// (PR update/commits/statuses, PR status creation, work-item comments).
void main() {
  tearDown(PropertyReader.clearOverrides);
  updatePullRequestTests();
  getPullRequestCommitsTests();
  getPullRequestStatusesTests();
  createPullRequestStatusTests();
  getWorkItemCommentsTests();
  addWorkItemCommentTests();
  batch4CatalogTests();
  batch4ExecutorPrTests();
  batch4ExecutorCommentTests();
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

/// Canned comment array.
const _commentArray = '[{"id":1,"text":"looks good"}]';

/// Canned created comment object.
const _comment = '{"id":1,"text":"nice"}';

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

/// `ado_get_work_item_comments` — GET `wit/workitems/{id}/comments`.
void getWorkItemCommentsTests() {
  group('AdoClient.getWorkItemComments', () {
    test('GETs comments and decodes the list', () async {
      final f = mockAdo((o) => routeByPath({'/comments': _commentArray}, o));
      final comments = await f.client.getWorkItemComments(42);
      expect(comments.single['text'], 'looks good');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/wit/workitems/42/comments'),
      );
    });
  });
}

/// `ado_add_work_item_comment` — POST `wit/workitems/{id}/comments`.
void addWorkItemCommentTests() {
  group('AdoClient.addWorkItemComment', () {
    test('POSTs a comment and decodes the object', () async {
      final f = mockAdo((o) => o.method == 'POST' ? _comment : '[]');
      final result = await f.client.addWorkItemComment(42, 'nice');
      expect(result['text'], 'nice');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(
        call.path,
        endsWith('/contoso/dmtools/_apis/wit/workitems/42/comments'),
      );
      expect(jsonDecode(call.data as String), {'text': 'nice'});
    });
  });
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    adoTools().firstWhere((t) => t.name == name);

/// Tool-definition shape for the batch-4 tools.
void batch4CatalogTests() {
  group('adoTools catalog (batch 4)', () {
    test('registers all six batch-4 tools', () {
      final names = adoTools().map((t) => t.name).toSet();
      for (final name in [
        'ado_update_pull_request',
        'ado_get_pull_request_commits',
        'ado_get_pull_request_statuses',
        'ado_create_pull_request_status',
        'ado_get_work_item_comments',
        'ado_add_work_item_comment',
      ]) {
        expect(names, contains(name));
      }
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

    test('ado_get_work_item_comments declares a numeric id', () {
      final tool = toolNamed('ado_get_work_item_comments');
      expect(tool.params.single.name, 'id');
      expect(tool.params.single.type, 'number');
    });

    test('ado_add_work_item_comment declares id and text', () {
      final tool = toolNamed('ado_add_work_item_comment');
      expect(tool.params.map((p) => p.name), ['id', 'text']);
    });
  });
}

/// Serves `[]` for list GETs, `{}` for POST/PATCH objects.
String _batch4Router(RequestOptions o) => o.method == 'GET' ? '[]' : '{}';

/// [AdoToolExecutor.execute] routing for the batch-4 pull-request tools.
void batch4ExecutorPrTests() {
  late _Batch4Fixture f;

  group('AdoToolExecutor.execute (batch 4: PR tools)', () {
    setUp(() => f = _batch4Fixture());

    test('routes ado_update_pull_request with numeric prId', () async {
      await f.executor.execute('ado_update_pull_request', {
        'project': 'p',
        'prId': 7,
        'title': 'New title',
        'description': 'New desc',
      });
      expect(f.spy.calls.single, 'updatePullRequest:p:7:New title:New desc');
    });

    test('routes ado_get_pull_request_commits with numeric prId', () async {
      await f.executor.execute(
        'ado_get_pull_request_commits',
        {'project': 'p', 'prId': 7},
      );
      expect(f.spy.calls.single, 'getPullRequestCommits:p:7');
    });

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

/// [AdoToolExecutor.execute] routing for the batch-4 comment tools.
void batch4ExecutorCommentTests() {
  late _Batch4Fixture f;

  group('AdoToolExecutor.execute (batch 4: comments)', () {
    setUp(() => f = _batch4Fixture());

    test('routes ado_get_work_item_comments with id', () async {
      await f.executor.execute('ado_get_work_item_comments', {'id': 42});
      expect(f.spy.calls.single, 'getWorkItemComments:42');
    });

    test('routes ado_add_work_item_comment with id and text', () async {
      await f.executor
          .execute('ado_add_work_item_comment', {'id': 42, 'text': 'nice'});
      expect(f.spy.calls.single, 'addWorkItemComment:42:nice');
    });
  });
}

/// A spy client plus the executor bound to it.
typedef _Batch4Fixture = ({AdoToolExecutor executor, _Batch4Spy spy});

/// Builds a [_Batch4Spy] over the mocked transport and wraps it.
_Batch4Fixture _batch4Fixture() {
  final spy = _Batch4Spy(mockAdoHttp(_batch4Router).http);
  return (executor: AdoToolExecutor(spy), spy: spy);
}

/// Records every dispatched batch-4 call then delegates to the real client.
class _Batch4Spy extends AdoClient {
  _Batch4Spy(super.http);

  final List<String> calls = [];

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

  @override
  Future<List<Map<String, dynamic>>> getWorkItemComments(int id) {
    calls.add('getWorkItemComments:$id');
    return super.getWorkItemComments(id);
  }

  @override
  Future<Map<String, dynamic>> addWorkItemComment(int id, String text) {
    calls.add('addWorkItemComment:$id:$text');
    return super.addWorkItemComment(id, text);
  }
}
