import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

/// Issues and labels — create, close, add labels, remove label —
/// [GithubClient] methods plus [GithubToolExecutor] routing.
void main() {
  tearDown(PropertyReader.clearOverrides);
  createIssueTests();
  closeIssueTests();
  addLabelsTests();
  removeLabelTests();
  executorIssueTests();
}

/// `github_create_issue` — POST `/repos/{owner}/{repo}/issues`.
void createIssueTests() {
  group('GithubClient.createIssue', () {
    test('POSTs title only when no body is given', () async {
      final f = mockGithub((o) => routeByPath({'/issues': _issueBody}, o));
      final result = await f.client.createIssue('epm', 'dm.ai', 'Bug');
      expect(result['number'], 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues'));
      expect(jsonDecode(call.data as String), {'title': 'Bug'});
    });

    test('includes the description body when provided', () async {
      final f = mockGithub((o) => routeByPath({'/issues': _issueBody}, o));
      await f.client.createIssue('epm', 'dm.ai', 'Bug', 'Steps to repro');
      expect(jsonDecode(f.adapter.calls.single.data as String), {
        'title': 'Bug',
        'body': 'Steps to repro',
      });
    });
  });
}

/// `github_close_issue` — PATCH `/repos/{owner}/{repo}/issues/{number}`.
void closeIssueTests() {
  group('GithubClient.closeIssue', () {
    test('PATCHes state closed', () async {
      final f = mockGithub((o) => routeByPath({'/issues/7': _issueBody}, o));
      await f.client.closeIssue('epm', 'dm.ai', 7);
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7'));
      expect(jsonDecode(call.data as String), {'state': 'closed'});
    });
  });
}

/// `github_add_labels` — POST `/repos/{owner}/{repo}/issues/{number}/labels`.
void addLabelsTests() {
  group('GithubClient.addLabels', () {
    test('POSTs the label set', () async {
      final f = mockGithub(
        (o) => routeByPath({'/labels': _labelListBody}, o),
      );
      final result = await f.client.addLabels(
        'epm',
        'dm.ai',
        7,
        ['bug', 'p2'],
      );
      expect(result.map((l) => l['name']).toList(), ['bug', 'p2']);
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels'));
      expect(jsonDecode(call.data as String), {
        'labels': ['bug', 'p2']
      });
    });
  });
}

/// `github_remove_label` — DELETE
/// `/repos/{owner}/{repo}/issues/{number}/labels/{label}`.
void removeLabelTests() {
  group('GithubClient.removeLabel', () {
    test('DELETEs the label and returns {} on an empty body', () async {
      final f = mockGithub((o) => routeByPath({'/labels/bug': ''}, o));
      expect(await f.client.removeLabel('epm', 'dm.ai', 7, 'bug'), isEmpty);
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels/bug'));
    });

    test('decodes a non-empty response body', () async {
      final f = mockGithub(
        (o) => routeByPath({'/labels/bug': _labelBody}, o),
      );
      expect(await f.client.removeLabel('epm', 'dm.ai', 7, 'bug'),
          jsonDecode(_labelBody));
    });
  });
}

/// Executor routing for the issue mutation and label tools.
void executorIssueTests() {
  group('GithubToolExecutor.execute (issues and labels)', () {
    test('routes github_create_issue', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_create_issue',
        {..._repoArgs, 'title': 'Bug'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {'title': 'Bug'});
    });

    test('routes github_close_issue with a coerced number', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client)
          .execute('github_close_issue', _issueArgs('7'));
      final call = f.adapter.calls.single;
      expect(call.method, 'PATCH');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7'));
      expect(jsonDecode(call.data as String), {'state': 'closed'});
    });

    test('routes github_add_labels with a cast label list', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute('github_add_labels', {
        ..._issueArgs(7),
        'labels': ['bug', 'p2'],
      });
      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(jsonDecode(call.data as String), {
        'labels': ['bug', 'p2']
      });
    });

    test('routes github_remove_label with a coerced number', () async {
      final f = mockGithub(_router);
      await GithubToolExecutor(f.client).execute(
        'github_remove_label',
        {..._issueArgs('7'), 'label': 'bug'},
      );
      final call = f.adapter.calls.single;
      expect(call.method, 'DELETE');
      expect(call.path, endsWith('/repos/epm/dm.ai/issues/7/labels/bug'));
    });
  });
}

/// Shared owner/repo arguments for executor tests.
const _repoArgs = {'owner': 'epm', 'repo': 'dm.ai'};

/// Issue tool arguments with a [number] value.
Map<String, dynamic> _issueArgs(Object number) =>
    {..._repoArgs, 'number': number};

/// Serves `[]` for label endpoints, `''` for deletes, `{}` otherwise.
String _router(RequestOptions o) {
  // POST /issues/{n}/labels returns the resulting label array.
  if (o.path.endsWith('/labels')) return '[]';
  if (o.method == 'DELETE') return '';
  return '{}';
}

/// Canned issue body.
const _issueBody = '{"number":7,"title":"Bug"}';

/// Canned label-list body.
const _labelListBody = '[{"name":"bug"},{"name":"p2"}]';

/// Canned single-label body.
const _labelBody = '{"name":"bug"}';
