import 'package:dio/dio.dart' show RequestOptions;
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// CODEOWNERS file access — [GithubClient] methods plus
/// [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getCodeownersTests();
  executorCodeownersTests();
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

/// Executor routing for the CODEOWNERS tool.
void executorCodeownersTests() {
  group('GithubToolExecutor.execute (codeowners)', () {
    test('routes github_get_codeowners', () async {
      final f = mockGithub(_router);
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

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Serves the canned CODEOWNERS body for every request.
String _router(RequestOptions o) => _codeownersBody;

/// Canned CODEOWNERS file body.
const _codeownersBody =
    '{"name":"CODEOWNERS","path":".github/CODEOWNERS","encoding":"base64"}';
