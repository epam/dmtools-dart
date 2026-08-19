import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Releases — list, get by tag, and create — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  listReleasesTests();
  getReleaseTests();
  createReleaseTests();
  executorReleaseTests();
}

/// `github_list_releases` — GET `/repos/{owner}/{repo}/releases`.
void listReleasesTests() {
  group('GithubClient.listReleases', () {
    test('GETs the release list', () async {
      final f = mockGithub(
        (o) => routeByPath({'/releases': _releaseListBody}, o),
      );
      final releases = await f.client.listReleases('epm', 'dm.ai');
      expect(releases.map((r) => r['tag_name']).toList(), ['v1.0.0', 'v0.9.0']);
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, endsWith('/repos/epm/dm.ai/releases'));
    });
  });
}

/// `github_get_release` — GET `/repos/{owner}/{repo}/releases/tags/{tag}`.
void getReleaseTests() {
  group('GithubClient.getRelease', () {
    test('GETs the release by tag', () async {
      final f = mockGithub(
        (o) => routeByPath({'/tags/v1.0.0': _releaseBody}, o),
      );
      final release = await f.client.getRelease('epm', 'dm.ai', 'v1.0.0');
      expect(release['tag_name'], 'v1.0.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'GET');
      expect(
        call.path,
        endsWith('/repos/epm/dm.ai/releases/tags/v1.0.0'),
      );
    });
  });
}

/// `github_create_release` — POST `/repos/{owner}/{repo}/releases`.
void createReleaseTests() {
  group('GithubClient.createRelease', () {
    test('POSTs tag_name only when no body is given', () async {
      final f = mockGithub((o) => routeByPath({'/releases': _releaseBody}, o));
      final result = await f.client.createRelease('epm', 'dm.ai', 'v1.0.0');
      expect(result['tag_name'], 'v1.0.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/releases'));
      expect(jsonDecode(call.data as String), {'tag_name': 'v1.0.0'});
    });

    test('includes the description body when provided', () async {
      final f = mockGithub((o) => routeByPath({'/releases': _releaseBody}, o));
      await f.client.createRelease('epm', 'dm.ai', 'v1.0.0', 'Ship it');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'tag_name': 'v1.0.0',
        'body': 'Ship it',
      });
    });
  });
}

/// Executor routing for the release tools.
void executorReleaseTests() {
  group('GithubToolExecutor.execute (releases)', () {
    test('routes github_list_releases', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client)
          .execute('github_list_releases', _repoArgs);
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/releases'),
      );
    });

    test('routes github_get_release with tag', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_get_release',
        {..._repoArgs, 'tag': 'v1.0.0'},
      );
      expect(
        f.adapter.calls.single.path,
        endsWith('/repos/epm/dm.ai/releases/tags/v1.0.0'),
      );
    });

    test('routes github_create_release with tag_name and body', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute('github_create_release', {
        ..._repoArgs,
        'tag_name': 'v1.0.0',
        'body': 'Ship it',
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {
        'tag_name': 'v1.0.0',
        'body': 'Ship it',
      });
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves `[]` for the release-list endpoint and `{}` otherwise.
String _router(RequestOptions o) {
  if (o.method == 'GET' && o.path.endsWith('/releases')) return '[]';
  return '{}';
}

/// Canned release-list body.
const _releaseListBody = '[{"tag_name":"v1.0.0"},{"tag_name":"v0.9.0"}]';

/// Canned release body.
const _releaseBody = '{"tag_name":"v1.0.0","name":"v1.0.0"}';
