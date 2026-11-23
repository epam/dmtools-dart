import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import '../js/echo_server_helper.dart';

/// Tests for [gitlabIssueTicketSource], [looksLikeGitlabQuery],
/// [parseGitlabIssueKeys], [TeammateJob] GitLab tracker wiring, and
/// [TicketSmartSources.fetchTicketByKey] for GitLab keys.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  _testQueryDetectionAndParsing();
  _testTicketSourceHydration();
  _testTeammateGitlabSelection();
  if (hasPython3()) {
    _testSmartSourcesGitlabFetch();
  }
}

void _testQueryDetectionAndParsing() {
  test('looksLikeGitlabQuery and parseGitlabIssueKeys recognize GitLab keys',
      () {
    expect(looksLikeGitlabQuery('gl-42'), isTrue);
    expect(looksLikeGitlabQuery('org/sub/repo#42'), isTrue);
    expect(looksLikeGitlabQuery('PROJ-123'), isFalse);
    expect(parseGitlabIssueKeys('gl-1, grp/proj#2'), ['gl-1', 'grp/proj#2']);
    expect(parseGitlabIssueKeys('is:open label:bug'), isEmpty);
  });
}

void _testTicketSourceHydration() {
  test('gitlabIssueTicketSource hydrates direct keys and search results',
      () async {
    PropertyReader.setOverrides({
      'GITLAB_TOKEN': 'glpat-x',
      'GITLAB_WORKSPACE': 'grp',
      'GITLAB_REPOSITORY': 'proj',
    });
    String? fakeExec(String tool, Map<String, dynamic> args) {
      if (tool == 'gitlab_get_issue') {
        return jsonEncode({
          'iid': 42,
          'title': 'Fix bug',
          'description': 'Body text',
          'state': 'opened',
          'references': {'full': 'grp/proj#42'},
        });
      }
      if (tool == 'gitlab_get_issue_comments') {
        return jsonEncode([
          {
            'author': {'username': 'alice'},
            'created_at': '2026-01-01T00:00:00Z',
            'body': 'Note 1',
          },
        ]);
      }
      if (tool == 'gitlab_search_issues') {
        return jsonEncode([
          {
            'iid': 9,
            'title': 'Search hit',
            'description': 'Found',
            'state': 'opened',
          },
        ]);
      }
      return null;
    }

    final single = await gitlabIssueTicketSource('gl-42', execute: fakeExec);
    expect(single, hasLength(1));
    expect(single.first['key'], 'grp/proj#42');
    expect((single.first['fields'] as Map)['summary'], 'Fix bug');

    final bare = await gitlabIssueTicketSource('#42', execute: fakeExec);
    expect(bare, hasLength(1));

    final searched =
        await gitlabIssueTicketSource('search term', execute: fakeExec);
    expect(searched, hasLength(1));
    expect(searched.first['key'], 'grp/proj#9');
  });
}

void _testTeammateGitlabSelection() {
  test('TeammateJob selects GitLab source and comment poster for gl-N query',
      () async {
    final tmp = await Directory.systemTemp.createTemp('teammate_gl_test');
    final posted = <String>[];
    try {
      PropertyReader.setOverrides({
        'DEFAULT_TRACKER': 'gitlab',
        'GITLAB_TOKEN': 'glpat-x',
        'GITLAB_WORKSPACE': 'grp',
        'GITLAB_REPOSITORY': 'proj',
      });
      final job = TeammateJob(
        params: {
          'inputJql': 'gl-12',
          'ciRunUrl': 'https://ci.example/1',
          'alwaysPostComments': true,
          'initiator': 'bob',
          'cliCommands': ['echo ok'],
        },
        workingDirectory: tmp.path,
        ticketSource: (_) async => [
          {
            'key': 'grp/proj#12',
            'fields': {'summary': 'GL issue', 'description': 'desc'},
          },
        ],
        commentPoster: (k, b) async => posted.add('$k:$b'),
      );
      final res = await job.run();
      expect(res['success'], isTrue);
      expect(posted, hasLength(2));
      expect(posted.last, contains('bob,'));
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}

void _testSmartSourcesGitlabFetch() {
  test(
      'TicketSmartSources.fetchTicketByKey fetches GitLab issue when configured',
      () async {
    final server = EchoServer();
    await server.start();
    try {
      PropertyReader.setOverrides({
        'GITLAB_BASE_PATH': 'http://127.0.0.1:${server.port}',
        'GITLAB_TOKEN': 'glpat-x',
        'GITLAB_WORKSPACE': 'grp',
        'GITLAB_REPOSITORY': 'proj',
      });
      final smart = TicketSmartSources(PropertyReader());
      expect(smart.capabilities.isGitlabConfigured, isTrue);
      final fetched = smart.fetchTicketByKey('gl-42');
      expect(fetched, isNotNull);
      expect(fetched!['key'], 'grp/proj#42');
    } finally {
      server.stop();
    }
  });
}
