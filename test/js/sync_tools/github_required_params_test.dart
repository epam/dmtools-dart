import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/github_sync_tools.dart';
import 'package:dmtools/src/js/sync_tools/sync_required_params.dart';
import 'package:test/test.dart';

/// Required-parameter validation for [GitHubSyncTools] — Java
/// MCPToolProcessor parity (P6-VCS-16): the generated Java executors throw
/// `IllegalArgumentException("Required parameter 'x' is missing")` before
/// the client is touched, checked in declaration order, with @MCPParam
/// aliases (`threadId`, `filePath`…) resolving to the primary name.
void main() {
  _missingParamOrderTests();
  _aliasAndAcceptedNameTests();
}

/// Java declaration-order errors and the validation-before-config
/// contract.
void _missingParamOrderTests() {
  group('GitHubSyncTools required-param validation (Java order)', () {
    const tools = GitHubSyncTools();

    setUp(() => PropertyReader.setOverrides({'SOURCE_GITHUB_TOKEN': ''}));
    tearDown(PropertyReader.clearOverrides);

    String run(String tool, Map<String, dynamic> args) =>
        tools.handlers[tool]!(args);

    test('every required param missing reports the first in Java order', () {
      expect(
        jsonDecode(run('github_add_pr_comment', {})),
        {'error': "Required parameter 'workspace' is missing"},
      );
    });

    test('a later missing param is reported by name', () {
      expect(
        jsonDecode(run('github_add_pr_comment',
            {'workspace': 'o', 'repository': 'r', 'pullRequestId': '7'})),
        {'error': "Required parameter 'text' is missing"},
      );
    });

    test('multi-param tools validate the whole chain (2+ checks)', () {
      expect(
        jsonDecode(run('github_dismiss_pr_review',
            {'workspace': 'o', 'pullRequestId': '7', 'reviewId': '1'})),
        {'error': "Required parameter 'repository' is missing"},
      );
      expect(
        jsonDecode(run('github_dismiss_pr_review', {
          'workspace': 'o',
          'repository': 'r',
          'pullRequestId': '7',
          'reviewId': '1',
        })),
        {'error': "Required parameter 'message' is missing"},
      );
    });

    test('Java casing is echoed verbatim (pullRequestID)', () {
      expect(
        jsonDecode(run('github_get_pr_diff',
            {'workspace': 'o', 'repository': 'r', 'nothing': 'x'})),
        {'error': "Required parameter 'pullRequestID' is missing"},
      );
    });

    test('validation fires before the not-configured error', () {
      // Java validates args in the generated executor before the client
      // is touched, so the param error wins even when unconfigured.
      expect(
        jsonDecode(run('github_get_pr', {})),
        {'error': "Required parameter 'workspace' is missing"},
      );
    });
  });
}

/// @MCPParam aliases and the Dart-side accepted spellings that keep every
/// working call serving.
void _aliasAndAcceptedNameTests() {
  group('GitHubSyncTools required-param validation (aliases)', () {
    const tools = GitHubSyncTools();

    setUp(() => PropertyReader.setOverrides({'SOURCE_GITHUB_TOKEN': ''}));
    tearDown(PropertyReader.clearOverrides);

    String run(String tool, Map<String, dynamic> args) =>
        tools.handlers[tool]!(args);

    test('existing Dart-side names still satisfy the check', () {
      // The Dart handler reads pullRequestId; only the error TEXT is
      // Java's — no working call may start failing.
      expect(
        run('github_get_pr_diff',
            {'workspace': 'o', 'repository': 'r', 'pullRequestId': '7'}),
        isNot(contains('Required parameter')),
      );
    });

    test('aliases satisfy the check (threadId → inReplyToId)', () {
      expect(
        run('github_reply_to_pr_thread', {
          'workspace': 'o',
          'repository': 'r',
          'pullRequestId': '7',
          'threadId': '1',
          'text': 'hi',
        }),
        isNot(contains('Required parameter')),
      );
    });

    test('tools without Java-required params are unaffected', () {
      expect(
        run('github_list_branches', {}),
        isNot(contains('Required parameter')),
      );
    });

    test('table covers only registered handlers', () {
      for (final name in kGithubRequiredParams.keys) {
        expect(tools.handlers, contains(name), reason: name);
      }
    });
  });
}
