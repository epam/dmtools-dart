import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:dmtools/src/js/sync_tools/gitlab_sync_tools.dart';
import 'package:dmtools/src/js/sync_tools/sync_required_params.dart';
import 'package:test/test.dart';

/// gh-380 AC5 — GitLab sync-surface catalog/runtime coherence.
///
/// The required-param table is the catalog that listed
/// `gitlab_list_project_jobs` as plausible while the runtime answered
/// 'Unsupported GitLab tool' — the exact phantom trap behind CM-3626
/// (mocks stubbed the call; production surfaced it). This gate blocks
/// the same regression: every `gitlab_*` name the catalog declares must
/// resolve to a live [GitLabSyncTools] handler, and the dispatcher must
/// route the gh-380 names to a handler (the unconfigured-config envelope
/// proves a route — 'Unsupported <tool>' would mean a phantom).
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  group('GitLab catalog/runtime coherence (gh-380 AC5)', () {
    test('every declared gitlab_* name has a live sync handler', () {
      final handlers = const GitLabSyncTools().handlers;
      final phantoms = kGitlabRequiredParams.keys
          .where((name) => !handlers.containsKey(name))
          .toList()
        ..sort();
      expect(
        phantoms,
        isEmpty,
        reason: 'kGitlabRequiredParams declares names the runtime rejects '
            "with 'Unsupported GitLab tool' — the CM-3626 phantom trap. "
            'Implement the sync executor or drop the row: '
            '${phantoms.join(', ')}',
      );
    });

    test('dispatcher routes gitlab_list_project_jobs (not Unsupported)', () {
      final dispatcher = SyncToolDispatcher(PropertyReader());
      final result = dispatcher.execute('gitlab_list_project_jobs', {
        'workspace': 'g',
        'repository': 'r',
      })!;
      expect(
        jsonDecode(result),
        {'error': 'GitLab not configured'},
        reason: 'the config-missing envelope proves the route exists; '
            "an 'Unsupported GitLab tool' answer would mean a phantom",
      );
    });

    test(
        'dispatcher routes gitlab_get_pipelines/gitlab_get_pipeline '
        '(not Unsupported)', () {
      final dispatcher = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(dispatcher.execute('gitlab_get_pipelines', {
          'workspace': 'g',
          'repository': 'r',
        })!),
        {'error': 'GitLab not configured'},
      );
      expect(
        jsonDecode(dispatcher.execute('gitlab_get_pipeline', {
          'workspace': 'g',
          'repository': 'r',
          'pipelineId': '7',
        })!),
        {'error': 'GitLab not configured'},
      );
    });
  });
}
