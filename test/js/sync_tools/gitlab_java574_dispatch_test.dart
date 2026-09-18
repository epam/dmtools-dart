/// Dispatch-level config-error coverage for the Java #574 GitLab
/// additions — split from test/js/sync_tool_dispatch_test.dart for the
/// crap4dart file-size gate.
library;

import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() => PropertyReader.testIsolation = false);

  group('SyncToolDispatcher Java #574 gitlab additions', () {
    test('gitlab_get_mr_pipelines returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('gitlab_get_mr_pipelines', {
          'workspace': 'g',
          'repository': 'r',
          'pullRequestId': 1,
        })!),
        {'error': 'GitLab not configured'},
      );
    });

    test('gitlab_list_issues returns config error', () {
      final d = SyncToolDispatcher(PropertyReader());
      expect(
        jsonDecode(d.execute('gitlab_list_issues', {
          'workspace': 'g',
          'repository': 'r',
        })!),
        {'error': 'GitLab not configured'},
      );
    });
  });
}
