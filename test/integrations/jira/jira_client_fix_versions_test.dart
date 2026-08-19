import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Fix-version mutation tests: addFixVersion, removeFixVersion
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  fixVersionMutationTests();
  fixVersionsExecutorDispatchTests();
}

/// `jira_add_fix_version` / `jira_remove_fix_version` — update.fixVersions.
void fixVersionMutationTests() {
  group('JiraClient.addFixVersion', () {
    test('PUTs an add operation on fixVersions', () async {
      final f = mockJira((o) => '{}');
      await f.client.addFixVersion('PROJ-1', '2.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      expect(call.path, endsWith('/issue/PROJ-1'));
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(decoded['update'], {
        'fixVersions': [
          {
            'add': {'name': '2.0'}
          }
        ]
      });
    });
  });

  group('JiraClient.removeFixVersion', () {
    test('PUTs a remove operation on fixVersions', () async {
      final f = mockJira((o) => '{}');
      await f.client.removeFixVersion('PROJ-1', '2.0');
      final call = f.adapter.calls.single;
      expect(call.method, 'PUT');
      final decoded = jsonDecode(call.data as String) as Map<String, dynamic>;
      expect(decoded['update'], {
        'fixVersions': [
          {
            'remove': {'name': '2.0'}
          }
        ]
      });
    });
  });
}

/// [JiraToolExecutor.execute] routes fix-version tool names.
void fixVersionsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (fix versions)', () {
    test('routes jira_add_fix_version', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_add_fix_version', {
        'key': 'PROJ-1',
        'version': '2.0',
      });
      expect(f.adapter.calls.single.method, 'PUT');
      expect(f.adapter.calls.single.path, endsWith('/issue/PROJ-1'));
    });

    test('routes jira_remove_fix_version', () async {
      final f = mockJira((o) => '{}');
      await executor(f).execute('jira_remove_fix_version', {
        'key': 'PROJ-1',
        'version': '2.0',
      });
      expect(f.adapter.calls.single.method, 'PUT');
      expect(f.adapter.calls.single.path, endsWith('/issue/PROJ-1'));
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);
