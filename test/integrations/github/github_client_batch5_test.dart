import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Batch 5: workflow catalog (list/enable/disable), CODEOWNERS, and
/// collaborator tools — [GithubClient] methods plus [GithubToolExecutor]
/// routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getWorkflowsTests();
  enableWorkflowTests();
  disableWorkflowTests();
  getCodeownersTests();
  addCollaboratorTests();
  removeCollaboratorTests();
  executorWorkflowCatalogTests();
  executorCodeownersTests();
  executorCollaboratorTests();
}

/// `github_get_workflows` — GET `/repos/{owner}/{repo}/actions/workflows`.
void getWorkflowsTests() {
  group('GithubClient.getWorkflows', () {
    test('GETs the workflows catalog', () async {
      final f = mockGithub(
        (o) => routeByPath({'/actions/workflows': _workflowsBody}, o),
      );
      final workflows = await f.client.getWorkflows('epm', 'dm.ai');
      expect(workflows['total_count'], 1);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/actions/workflows'),
      );
    });
  });
}

/// `github_enable_workflow` — PUT `.../actions/workflows/{id}/enable`.
void enableWorkflowTests() {
  group('GithubClient.enableWorkflow', () {
    test('PUTs enable and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/enable': ''}, o));
      expect(await f.client.enableWorkflow('epm', 'dm.ai', 7), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/enable'),
      );
    });
  });
}

/// `github_disable_workflow` — PUT `.../actions/workflows/{id}/disable`.
void disableWorkflowTests() {
  group('GithubClient.disableWorkflow', () {
    test('PUTs disable and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/disable': ''}, o));
      expect(await f.client.disableWorkflow('epm', 'dm.ai', 7), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/disable'),
      );
    });
  });
}

/// `github_get_codeowners` — GET `.../contents/.github/CODEOWNERS`.
void getCodeownersTests() {
  group('GithubClient.getCodeowners', () {
    test('GETs the CODEOWNERS file via the contents API', () async {
      final f = mockGithub(
        (o) => routeByPath({'.github/CODEOWNERS': _codeownersBody}, o),
      );
      final file = await f.client.getCodeowners('epm', 'dm.ai');
      expect(file['name'], 'CODEOWNERS');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/contents/.github/CODEOWNERS'),
      );
    });
  });
}

/// `github_add_collaborator` — PUT `.../collaborators/{username}`.
void addCollaboratorTests() {
  group('GithubClient.addCollaborator', () {
    test('PUTs the permission level', () async {
      final f = mockGithub(
        (o) => routeByPath({'/collaborators/alice': _invitationBody}, o),
      );
      final invite = await f.client.addCollaborator(
        'epm',
        'dm.ai',
        'alice',
        'push',
      );
      expect(invite['id'], 11);
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/collaborators/alice'),
      );
      expect(jsonDecode(call.data as String), {'permission': 'push'});
    });
  });
}

/// `github_remove_collaborator` — DELETE `.../collaborators/{username}`.
void removeCollaboratorTests() {
  group('GithubClient.removeCollaborator', () {
    test('DELETEs the collaborator and returns {} on 204', () async {
      final f = mockGithub((o) => routeByPath({'/collaborators/alice': ''}, o));
      expect(
        await f.client.removeCollaborator('epm', 'dm.ai', 'alice'),
        isEmpty,
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/collaborators/alice'),
      );
    });
  });
}

/// Executor routing for the workflow-catalog tools.
void executorWorkflowCatalogTests() {
  group('GithubToolExecutor.execute (batch 5: workflows)', () {
    test('routes github_get_workflows', () async {
      final f = mockGithub(_batch5Router);
      await GithubToolExecutor(f.client).execute(
        'github_get_workflows',
        _repoArgs,
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/workflows'),
      );
    });

    test('routes github_enable_workflow with a coerced workflow_id', () async {
      final f = mockGithub(_batch5Router);
      await GithubToolExecutor(f.client).execute(
        'github_enable_workflow',
        {..._repoArgs, 'workflow_id': '7'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/enable'),
      );
    });

    test('routes github_disable_workflow', () async {
      final f = mockGithub(_batch5Router);
      await GithubToolExecutor(f.client).execute(
        'github_disable_workflow',
        {..._repoArgs, 'workflow_id': 7},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/actions/workflows/7/disable'),
      );
    });
  });
}

/// Executor routing for the CODEOWNERS tool.
void executorCodeownersTests() {
  group('GithubToolExecutor.execute (batch 5: codeowners)', () {
    test('routes github_get_codeowners', () async {
      final f = mockGithub(_batch5Router);
      await GithubToolExecutor(f.client).execute(
        'github_get_codeowners',
        _repoArgs,
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/contents/.github/CODEOWNERS'),
      );
    });
  });
}

/// Executor routing for the collaborator tools.
void executorCollaboratorTests() {
  group('GithubToolExecutor.execute (batch 5: collaborators)', () {
    test('routes github_add_collaborator with permission', () async {
      final f = mockGithub(_batch5Router);
      await GithubToolExecutor(f.client).execute(
        'github_add_collaborator',
        {
          ..._repoArgs,
          'username': 'bob',
          'permission': 'admin',
        },
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/collaborators/bob'),
      );
      expect(jsonDecode(call.data as String), {'permission': 'admin'});
    });

    test('routes github_remove_collaborator', () async {
      final f = mockGithub(_batch5Router);
      await GithubToolExecutor(f.client).execute(
        'github_remove_collaborator',
        {..._repoArgs, 'username': 'bob'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/collaborators/bob'),
      );
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves canned bodies by path/method for the batch-5 endpoints.
String _batch5Router(RequestOptions o) {
  if (o.path.endsWith('/actions/workflows')) return _workflowsBody;
  if (o.path.endsWith('.github/CODEOWNERS')) return _codeownersBody;
  if (o.path.endsWith('/enable') || o.path.endsWith('/disable')) return '';
  if (o.path.endsWith('/collaborators/alice') ||
      o.path.endsWith('/collaborators/bob')) {
    if (o.method == 'DELETE') return '';
    return _invitationBody;
  }
  return _workflowsBody;
}

/// Canned workflows-catalog body.
const _workflowsBody = '{"total_count":1,"workflows":[{"id":7,"name":"CI"}]}';

/// Canned CODEOWNERS file body.
const _codeownersBody =
    '{"name":"CODEOWNERS","path":".github/CODEOWNERS","encoding":"base64"}';

/// Canned collaboration-invitation body.
const _invitationBody = '{"id":11,"invitee":{"login":"alice"}}';
