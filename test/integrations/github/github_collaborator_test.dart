import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Collaborators — add and remove — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  addCollaboratorTests();
  removeCollaboratorTests();
  executorCollaboratorTests();
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

/// Executor routing for the collaborator tools.
void executorCollaboratorTests() {
  group('GithubToolExecutor.execute (collaborators)', () {
    test('routes github_add_collaborator with permission', () async {
      final f = mockGithub(_router);
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
      final f = mockGithub(_router);
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

/// Serves the canned invitation body, `''` for deletes.
String _router(RequestOptions o) {
  if (o.method == 'DELETE') return '';
  return _invitationBody;
}

/// Canned collaboration-invitation body.
const _invitationBody = '{"id":11,"invitee":{"login":"alice"}}';
