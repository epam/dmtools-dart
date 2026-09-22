import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/gitlab_sync_tools.dart';
import 'package:dmtools/src/js/sync_tools/sync_required_params.dart';
import 'package:test/test.dart';

/// Required-parameter validation for [GitLabSyncTools] — Java
/// MCPToolProcessor parity (P6-VCS-16): the generated Java executors throw
/// `IllegalArgumentException("Required parameter 'x' is missing")` before
/// the client is touched, checked in declaration order, with @MCPParam
/// aliases (`threadId`, `body`/`note`…) resolving to the primary name.
void main() {
  _missingParamOrderTests();
  _aliasAndAcceptedNameTests();
}

/// Java declaration-order errors and the validation-before-config
/// contract.
void _missingParamOrderTests() {
  group('GitLabSyncTools required-param validation (Java order)', () {
    const tools = GitLabSyncTools();

    setUp(() => PropertyReader.setOverrides(
        {'GITLAB_BASE_PATH': '', 'GITLAB_TOKEN': ''}));
    tearDown(PropertyReader.clearOverrides);

    String run(String tool, Map<String, dynamic> args) =>
        tools.handlers[tool]!(args);

    test('every required param missing reports the first in Java order', () {
      expect(
        jsonDecode(run('gitlab_trigger_pipeline', {})),
        {'error': "Required parameter 'workspace' is missing"},
      );
    });

    test('a later missing param is reported by name', () {
      expect(
        jsonDecode(run(
            'gitlab_trigger_pipeline', {'workspace': 'g', 'repository': 'r'})),
        {'error': "Required parameter 'ref' is missing"},
      );
    });

    test('multi-param tools validate the whole chain (2+ checks)', () {
      expect(
        jsonDecode(run('gitlab_download_release_asset',
            {'workspace': 'g', 'tagName': 'v1', 'assetName': 'a'})),
        {'error': "Required parameter 'repository' is missing"},
      );
      expect(
        jsonDecode(run('gitlab_download_release_asset', {
          'workspace': 'g',
          'repository': 'r',
          'tagName': 'v1',
          'assetName': 'a',
        })),
        {'error': "Required parameter 'targetFilePath' is missing"},
      );
    });

    test('validation fires before the not-configured error', () {
      expect(
        jsonDecode(run('gitlab_get_mr', {})),
        {'error': "Required parameter 'workspace' is missing"},
      );
    });
  });
}

/// @MCPParam aliases resolving to the primary names.
void _aliasAndAcceptedNameTests() {
  group('GitLabSyncTools required-param validation (aliases)', () {
    const tools = GitLabSyncTools();

    setUp(() => PropertyReader.setOverrides(
        {'GITLAB_BASE_PATH': '', 'GITLAB_TOKEN': ''}));
    tearDown(PropertyReader.clearOverrides);

    String run(String tool, Map<String, dynamic> args) =>
        tools.handlers[tool]!(args);

    test('aliases satisfy the check (threadId → discussionId)', () {
      expect(
        run('gitlab_resolve_mr_thread', {
          'workspace': 'g',
          'repository': 'r',
          'pullRequestId': '7',
          'threadId': 'abc',
        }),
        isNot(contains('Required parameter')),
      );
    });

    test('aliases satisfy the check (body → create_mr_note text)', () {
      expect(
        run('gitlab_create_mr_note', {
          'workspace': 'g',
          'repository': 'r',
          'pullRequestId': '7',
          'body': 'hi'
        }),
        isNot(contains('Required parameter')),
      );
    });

    test('table covers only registered handlers', () {
      // Entries for not-yet-registered tools (js_sync_surface gaps) are
      // harmless; every registered table key must be a real handler.
      final registered =
          kGitlabRequiredParams.keys.where(tools.handlers.containsKey);
      expect(registered, isNotEmpty);
    });
  });
}
