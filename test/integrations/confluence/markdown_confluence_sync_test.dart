import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/integrations/confluence/markdown_confluence_sync.dart';
import 'package:test/test.dart';

/// Tests for [MarkdownConfluenceSync] against in-memory fakes — the port of
/// the Java `MarkdownConfluenceSync` directory-sync algorithm.
void main() {
  group('MarkdownConfluenceSync', () {
    setUp(() {
      _tmp = Directory.systemTemp.createTempSync('dmtools_md_sync_');
      _pageOps = FakePageOps();
      _attachments = FakeAttachments();
    });

    tearDown(() {
      _tmp.deleteSync(recursive: true);
    });

    _pageStructureTests();
    _childPageTests();
    _linkAndAttachmentTests();
  });
}

/// Shared fixtures for the sync engine tests.
late Directory _tmp;
late FakePageOps _pageOps;
late FakeAttachments _attachments;

MarkdownConfluenceSync _engine() =>
    MarkdownConfluenceSync(_attachments, _pageOps);

File _write(String relPath, String content) {
  final file = File('${_tmp.path}/$relPath');
  file.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// Page-tree structure tests: titles, nesting, placeholder bodies.
void _pageStructureTests() {
  test('root page gets the index.md body and keeps its real title', () {
    _write('index.md', '# Root Notes\n\nHello **world**.');
    _pageOps.existingRoot = {
      'id': 'root',
      'title': 'TICKET-1 Summary',
      'ancestors': [
        {'id': 'parent-9'},
      ],
    };
    final summary = _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    final rootUpdate = _pageOps.updates.last;
    expect(rootUpdate.contentId, 'root');
    expect(rootUpdate.title, 'TICKET-1 Summary');
    expect(rootUpdate.parentId, 'parent-9');
    expect(rootUpdate.body, contains('<h1>Root Notes</h1>'));
    expect(rootUpdate.body, contains('<strong>world</strong>'));
    final decoded = jsonDecode(summary) as Map<String, dynamic>;
    expect(decoded['parentId'], 'root');
    // Java builds expectedTitles before the root-title preserve, so the
    // summary's syncedPages keeps the directory basename for the index.
    expect(decoded['syncedPages'], [_tmp.path.split('/').last]);
  });

  test('markdown files become child pages titled by their h1', () {
    _write('index.md', 'Root');
    _write('analysis.md', '# Deep Analysis\n\nFindings.');
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    final created = _pageOps.created;
    expect(created.map((c) => c.title), contains('Deep Analysis'));
    final update =
        _pageOps.updates.firstWhere((u) => u.title == 'Deep Analysis');
    expect(update.parentId, 'root');
    expect(update.body, contains('Findings.'));
  });

  test('missing root lookup falls back to the directory name title', () {
    _write('notes.md', '# x');
    _pageOps.getContentThrows = true;
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    final rootUpdate = _pageOps.updates.first;
    expect(rootUpdate.title, _tmp.path.split('/').last);
    expect(rootUpdate.parentId, 'root'); // self-parent fallback
  });

  test('empty directory produces a placeholder body', () {
    final summary = _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    final rootUpdate = _pageOps.updates.last;
    expect(rootUpdate.body, startsWith('<p>'));
    expect(jsonDecode(summary), isA<Map<String, dynamic>>());
  });
}

/// Child-page creation tests (file pages and subdirectories).
void _childPageTests() {
  test('subdirectories become child pages with their index body', () {
    _write('index.md', 'Root');
    _write('specs/api.md', '# API Spec\n\nEndpoints.');
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    final specUpdate =
        _pageOps.updates.firstWhere((u) => u.title == 'API Spec');
    expect(specUpdate.body, contains('Endpoints.'));
  });
}

/// Link rewriting, attachment upload, and orphan-deletion tests.
void _linkAndAttachmentTests() {
  test('relative .md links are rewritten to page titles', () {
    _write('index.md', 'See [the analysis](analysis.md).');
    _write('analysis.md', '# Deep Analysis\n\nx');
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    // The root page update (index.md body) happens before file pages.
    final rootUpdate = _pageOps.updates.first;
    expect(
      rootUpdate.body,
      contains('<ri:page ri:content-title="Deep%20Analysis"/>'),
    );
  });

  test('external and anchor links are left untouched', () {
    _write('index.md', '[e](https://e.com) [a](#sec) [pdf](docs/r.pdf)');
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    final body = _pageOps.updates.first.body;
    expect(body, contains('href="https://e.com"'));
    expect(body, contains('href="#sec"'));
    expect(body, contains('ri:filename="r.pdf"'));
  });

  test('referenced attachments are uploaded once', () {
    _write('index.md', '![shot](shot.png)');
    _write('shot.png', 'png-bytes');
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    expect(_attachments.uploads, {
      'root': ['shot.png']
    });
  });

  test('loose non-markdown files upload and get an attachment section', () {
    _write('index.md', 'Root');
    _write('bundle.zip', 'zip-bytes');
    _engine().syncDirectory(_tmp, 'root', 'ENG', false, null);
    expect(_attachments.uploads['root'], contains('bundle.zip'));
    final rootUpdate = _pageOps.updates.last;
    expect(rootUpdate.body, contains('<h2>Attachments</h2>'));
    expect(rootUpdate.body, contains('ri:filename="bundle.zip"'));
  });

  test('deleteOrphans removes stale child pages recursively', () {
    _write('index.md', 'Root');
    _pageOps.childrenOf['root'] = [
      {'id': 'stale-1', 'title': 'Old Page'},
    ];
    final summary = _engine().syncDirectory(_tmp, 'root', 'ENG', true, null);
    expect(_pageOps.deleted, ['stale-1']);
    expect(
        (jsonDecode(summary) as Map<String, dynamic>)['deleted'], ['Old Page']);
  });
}

/// Records page CRUD calls; children/roots served from simple maps.
class FakePageOps implements ConfluencePageOperations {
  final created = <_Record>[];
  final updates = <_Record>[];
  final deleted = <String>[];
  final childrenOf = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic>? existingRoot;
  bool getContentThrows = false;
  var _nextId = 100;

  @override
  Map<String, dynamic> createPage(
    String title,
    String parentId,
    String body,
    String space,
  ) {
    created.add(_Record('${_nextId++}', title, parentId, body, space));
    return {'id': '${_nextId - 1}', 'title': title};
  }

  @override
  Map<String, dynamic> updatePage(
    String contentId,
    String title,
    String parentId,
    String body,
    String space, [
    String historyComment = '',
  ]) {
    updates.add(_Record(contentId, title, parentId, body, space));
    return {'id': contentId, 'title': title};
  }

  @override
  List<Map<String, dynamic>> getChildren(String contentId) =>
      childrenOf[contentId] ?? const [];

  @override
  String deletePage(String contentId) {
    deleted.add(contentId);
    return '';
  }

  @override
  Map<String, dynamic> getContent(String contentId) {
    if (getContentThrows) throw const SocketException('offline');
    return existingRoot ?? {'id': contentId, 'title': ''};
  }
}

/// Records attachment uploads; `pageId → names`.
class FakeAttachments implements SyncAttachmentHelper {
  final uploads = <String, List<String>>{};
  final presentOn = <String, Set<String>>{};

  @override
  List<String> listAttachmentNames(String contentId) =>
      (presentOn[contentId] ?? const {}).toList();

  @override
  void uploadAttachment(String contentId, File file) {
    final name = file.uri.pathSegments.last;
    uploads.putIfAbsent(contentId, () => []).add(name);
    presentOn.putIfAbsent(contentId, () => {}).add(name);
  }
}

/// One recorded page operation.
class _Record {
  final String contentId;
  final String title;
  final String parentId;
  final String body;
  final String space;

  const _Record(
      this.contentId, this.title, this.parentId, this.body, this.space);
}
