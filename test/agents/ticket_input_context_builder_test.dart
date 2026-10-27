/// Tests for TicketInputContextBuilder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import '../js/echo_server_helper.dart';

void main() {
  emptyContextTests();
  fullTicketTests();
  subtaskTests();
  commentsTests();
  missingFieldsTests();
  subtaskEdgeCaseTests();
  contextPathTests();
  inputFolderNameTests();
  requestMdTests();
  jiraAttachmentsTests();
  adoAttachmentsTests();
  attachmentFilteringTests();
  attachmentResilienceTests();
  authHeadersResolutionTests();
}

// ======================================================================
// Empty context — no ticket data
// ======================================================================

void emptyContextTests() {
  group('TicketInputContextBuilder — empty context', () {
    test('creates an empty folder when ticketData is null', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        final path = builder.build('PROJ-1');
        expect(Directory(path).existsSync(), isTrue);
        expect(Directory(path).listSync(), isEmpty);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('creates nested folders when contextId has slashes', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        final path = builder.build('batch/run-42');
        expect(Directory(path).existsSync(), isTrue);
        expect(path, '${tmp.path}/input/batch/run-42');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Full ticket data
// ======================================================================

void fullTicketTests() {
  group('TicketInputContextBuilder — full ticket', () {
    test('writes ticket.md with key, summary, status, priority, description',
        () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _fullTicket());
        final md =
            File('${tmp.path}/input/PROJ-1/ticket.md').readAsStringSync();
        expect(md, contains('# PROJ-100: Implement login'));
        expect(md, contains('**Status:** In Progress'));
        expect(md, contains('**Priority:** High'));
        expect(md, contains('## Description'));
        expect(md, contains('Users need a login page'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('writes ticket.json with the raw ticket data', () {
      final tmp = _createTempDir();
      try {
        final ticket = _fullTicket();
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: ticket);
        final json =
            File('${tmp.path}/input/PROJ-1/ticket.json').readAsStringSync();
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['key'], 'PROJ-100');
        expect(decoded['fields']['summary'], 'Implement login');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('returns the context folder path', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        final path = builder.build('CTX-9', ticketData: _fullTicket());
        expect(path, '${tmp.path}/input/CTX-9');
        expect(Directory(path).existsSync(), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Subtasks
// ======================================================================

void subtaskTests() {
  group('TicketInputContextBuilder — subtasks', () {
    test('writes a markdown file per subtask', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _ticketWithSubtasks());
        final subtaskDir = Directory('${tmp.path}/input/PROJ-1/subtasks');
        expect(subtaskDir.existsSync(), isTrue);
        final files = subtaskDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(files, containsAll(['PROJ-101.md', 'PROJ-102.md']));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('subtask markdown includes key, summary, and description', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _ticketWithSubtasks());
        final md = File('${tmp.path}/input/PROJ-1/subtasks/PROJ-101.md')
            .readAsStringSync();
        expect(md, contains('# PROJ-101: Build form'));
        expect(md, contains('## Description'));
        expect(md, contains('Create the login form UI'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('creates no subtasks folder when there are none', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _fullTicket());
        expect(
          Directory('${tmp.path}/input/PROJ-1/subtasks').existsSync(),
          isFalse,
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Comments
// ======================================================================

void commentsTests() {
  group('TicketInputContextBuilder — comments', () {
    test('writes comments.md with author and body', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _ticketWithComments());
        final md =
            File('${tmp.path}/input/PROJ-1/comments.md').readAsStringSync();
        expect(md, contains('## Comments'));
        expect(md, contains('**Alice** (2024-01-15):'));
        expect(md, contains('This looks good'));
        expect(md, contains('**Bob** (2024-01-16):'));
        expect(md, contains('Needs tests'));
        // Comments are separated by horizontal rules.
        expect('---'.allMatches(md).length, greaterThanOrEqualTo(2));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('does not create comments.md when there are none', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _fullTicket());
        expect(
          File('${tmp.path}/input/PROJ-1/comments.md').existsSync(),
          isFalse,
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Missing fields — graceful handling
// ======================================================================

void missingFieldsTests() {
  group('TicketInputContextBuilder — missing fields', () {
    test('handles ticket with only a key', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: {'key': 'LONE-1'});
        final md =
            File('${tmp.path}/input/PROJ-1/ticket.md').readAsStringSync();
        expect(md, contains('# LONE-1'));
        expect(md, contains('(no description)'));
        expect(md, isNot(contains('**Status:**')));
        expect(md, isNot(contains('**Priority:**')));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('handles empty fields map', () {
      final tmp = _createTempDir();
      try {
        TicketInputContextBuilder(tmp.path).build(
          'PROJ-1',
          ticketData: <String, dynamic>{},
        );
        expect(
          File('${tmp.path}/input/PROJ-1/ticket.md').existsSync(),
          isTrue,
        );
        expect(
          File('${tmp.path}/input/PROJ-1/ticket.json').existsSync(),
          isTrue,
        );
        expect(
          File('${tmp.path}/input/PROJ-1/ticket.md').readAsStringSync(),
          contains('# Ticket'),
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

void subtaskEdgeCaseTests() {
  group('TicketInputContextBuilder — subtask edge cases', () {
    test('handles subtasks without fields', () {
      final tmp = _createTempDir();
      try {
        TicketInputContextBuilder(tmp.path).build('PROJ-1', ticketData: {
          'key': 'P-1',
          'fields': {
            'subtasks': [
              {'key': 'S-1'},
            ],
          },
        });
        final md =
            File('${tmp.path}/input/PROJ-1/subtasks/S-1.md').readAsStringSync();
        expect(md, contains('# S-1'));
        expect(md, contains('(no description)'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('handles subtask entries that are not maps', () {
      final tmp = _createTempDir();
      try {
        TicketInputContextBuilder(tmp.path).build('PROJ-1', ticketData: {
          'key': 'P-1',
          'fields': {
            'subtasks': ['not-a-map', 42],
          },
        });
        expect(
          Directory('${tmp.path}/input/PROJ-1/subtasks').existsSync(),
          isFalse,
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Context path resolution
// ======================================================================

void contextPathTests() {
  group('TicketInputContextBuilder — path resolution', () {
    test('resolves input folder under the working directory', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        final path = builder.build('PATH-1', ticketData: _fullTicket());
        expect(path, startsWith(tmp.path));
        expect(path, endsWith('input/PATH-1'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('overwrites existing ticket.md on rebuild', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _fullTicket());
        builder.build('PROJ-1', ticketData: {'key': 'CHANGED-1'});
        final md =
            File('${tmp.path}/input/PROJ-1/ticket.md').readAsStringSync();
        expect(md, contains('# CHANGED-1'));
        expect(md, isNot(contains('PROJ-100')));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('maps GitHub composite key owner/repo#N to input/gh-N', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        final path =
            builder.build('acme/widgets#42', ticketData: _fullTicket());
        expect(path, '${tmp.path}/input/gh-42');
        expect(File('$path/ticket.md').existsSync(), isTrue);
        expect(File('$path/ticket.json').existsSync(), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

void inputFolderNameTests() {
  group('TicketInputContextBuilder.toInputFolderName', () {
    test('maps composite and bare GitHub keys and preserves others', () {
      expect(
        TicketInputContextBuilder.toInputFolderName('acme/widgets#42'),
        'gh-42',
      );
      expect(
        TicketInputContextBuilder.toInputFolderName('#7'),
        'gh-7',
      );
      expect(
        TicketInputContextBuilder.toInputFolderName('PROJ-123'),
        'PROJ-123',
      );
      expect(
        TicketInputContextBuilder.toInputFolderName('batch/run-42'),
        'batch/run-42',
      );
    });
  });
}

// ======================================================================
// request.md parity & ADO fields
// ======================================================================

void requestMdTests() {
  group('TicketInputContextBuilder — request.md and ADO markdown', () {
    test('writes request.md matching ticket.md content', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(tmp.path);
        builder.build('PROJ-1', ticketData: _fullTicket());
        final ticketMd =
            File('${tmp.path}/input/PROJ-1/ticket.md').readAsStringSync();
        final requestMd =
            File('${tmp.path}/input/PROJ-1/request.md').readAsStringSync();
        expect(requestMd, equals(ticketMd));
        expect(requestMd, contains('# PROJ-100: Implement login'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('formats ADO System.* fields into ticket.md and request.md', () {
      final tmp = _createTempDir();
      try {
        TicketInputContextBuilder(tmp.path).build('1234', ticketData: {
          'id': 1234,
          'fields': {
            'System.Title': 'Fix crash on launch',
            'System.State': 'Active',
            'Microsoft.VSTS.Common.Priority': 1,
            'Microsoft.VSTS.TCM.ReproSteps': 'Open app and tap login',
          },
        });
        final req =
            File('${tmp.path}/input/1234/request.md').readAsStringSync();
        expect(req, contains('# 1234: Fix crash on launch'));
        expect(req, contains('**Status:** Active'));
        expect(req, contains('**Priority:** 1'));
        expect(req, contains('Open app and tap login'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Jira & generic attachment downloading
// ======================================================================

void jiraAttachmentsTests() {
  group('TicketInputContextBuilder — Jira attachments', () {
    test('downloads Jira fields.attachment and sanitizes filenames', () {
      final tmp = _createTempDir();
      final requestedUrls = <String>[];
      try {
        final builder = TicketInputContextBuilder(
          tmp.path,
          attachmentDownloader: (url) {
            requestedUrls.add(url);
            return utf8.encode('content-for-$url');
          },
        );
        builder.build('PROJ-1', ticketData: {
          'key': 'PROJ-1',
          'fields': {
            'summary': 'Bug with logs',
            'attachment': [
              {
                'filename': 'screenshot.png',
                'content': 'https://jira.example.com/secure/attachment/1/s.png',
              },
              {
                'name': r'sub/dir\charles.har',
                'url': 'https://jira.example.com/secure/attachment/2/c.har',
              },
            ],
          },
        });
        expect(requestedUrls, hasLength(2));
        final dir = '${tmp.path}/input/PROJ-1';
        expect(
          File('$dir/screenshot.png').readAsStringSync(),
          'content-for-https://jira.example.com/secure/attachment/1/s.png',
        );
        expect(
          File('$dir/sub_dir_charles.har').readAsStringSync(),
          'content-for-https://jira.example.com/secure/attachment/2/c.har',
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// ADO attachment downloading (relations + embedded HTML images)
// ======================================================================

void adoAttachmentsTests() {
  group('TicketInputContextBuilder — ADO attachments', () {
    test('downloads ADO AttachedFile relations and embedded HTML images', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(
          tmp.path,
          attachmentDownloader: (url) => utf8.encode('ado:$url'),
        );
        builder.build('99', ticketData: _adoTicketWithAttachments());
        final dir = '${tmp.path}/input/99';
        expect(File('$dir/trace.log').existsSync(), isTrue);
        expect(File('$dir/from_query.png').existsSync(), isTrue);
        expect(File('$dir/fallback-id').existsSync(), isTrue);
        expect(File('$dir/inline.png').existsSync(), isTrue);
        expect(File('$dir/attachment_emb-42.png').existsSync(), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Attachment filtering (includeAttachments, skipAll, skipVideo)
// ======================================================================

void attachmentFilteringTests() {
  group('TicketInputContextBuilder — attachment filtering', () {
    test('skips all attachments when skipAllAttachments or !includeAttachments',
        () {
      final tmp = _createTempDir();
      var calls = 0;
      try {
        final builder = TicketInputContextBuilder(
          tmp.path,
          attachmentDownloader: (_) {
            calls++;
            return [1, 2, 3];
          },
        );
        final ticket = {
          'key': 'PROJ-1',
          'fields': {
            'attachment': [
              {'filename': 'a.png', 'content': 'https://example.com/a.png'},
            ],
          },
        };
        builder.build('P-1', ticketData: ticket, skipAllAttachments: true);
        builder.build('P-2', ticketData: ticket, includeAttachments: false);
        expect(calls, 0);
        expect(File('${tmp.path}/input/P-1/a.png').existsSync(), isFalse);
        expect(File('${tmp.path}/input/P-2/a.png').existsSync(), isFalse);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('skips video files when skipVideoAttachments is true', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(
          tmp.path,
          skipVideoAttachments: true,
          attachmentDownloader: (_) => [42],
        );
        builder.build('PROJ-1', ticketData: {
          'key': 'PROJ-1',
          'fields': {
            'attachment': [
              {'filename': 'demo.MP4', 'content': 'https://example.com/1'},
              {'filename': 'clip.mov', 'content': 'https://example.com/2'},
              {'filename': 'screen.png', 'content': 'https://example.com/3'},
            ],
          },
        });
        final dir = '${tmp.path}/input/PROJ-1';
        expect(File('$dir/demo.MP4').existsSync(), isFalse);
        expect(File('$dir/clip.mov').existsSync(), isFalse);
        expect(File('$dir/screen.png').existsSync(), isTrue);
        expect(TicketInputContextBuilder.isVideoFile(null), isFalse);
        expect(TicketInputContextBuilder.isVideoFile('a.webm'), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Error resilience
// ======================================================================

void attachmentResilienceTests() {
  group('TicketInputContextBuilder — error resilience', () {
    test('continues when an attachment download throws or returns null', () {
      final tmp = _createTempDir();
      try {
        final builder = TicketInputContextBuilder(
          tmp.path,
          attachmentDownloader: (url) {
            if (url.contains('throw')) throw StateError('network down');
            if (url.contains('null')) return null;
            return utf8.encode('ok');
          },
        );
        builder.build('PROJ-1', ticketData: {
          'key': 'PROJ-1',
          'attachments': [
            {'name': 'bad1.png', 'url': 'https://example.com/throw'},
            {'name': 'bad2.png', 'url': 'https://example.com/null'},
            {'name': '', 'url': 'https://example.com/empty'},
            {'name': 'good.png', 'url': 'https://example.com/good'},
          ],
        });
        final dir = '${tmp.path}/input/PROJ-1';
        expect(File('$dir/bad1.png').existsSync(), isFalse);
        expect(File('$dir/bad2.png').existsSync(), isFalse);
        expect(File('$dir/good.png').readAsStringSync(), 'ok');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Auth header resolution
// ======================================================================

void authHeadersResolutionTests() {
  group('TicketInputContextBuilder.resolveAuthHeadersForUrl', () {
    test('resolves Jira and ADO auth headers for matching hosts', () async {
      await PropertyReader.runWithOverrides(
        {
          'JIRA_BASE_PATH': 'https://jira.acme.com',
          'JIRA_LOGIN_PASS_TOKEN': 'jtok',
          'JIRA_AUTH_TYPE': 'Bearer',
          'ADO_PAT_TOKEN': 'adopat',
        },
        () async {
          final reader = PropertyReader();
          final jiraHeaders =
              TicketInputContextBuilder.resolveAuthHeadersForUrl(
            'https://jira.acme.com/secure/attachment/1/a.png',
            reader,
          );
          expect(jiraHeaders?['Authorization'], 'Bearer jtok');
          expect(jiraHeaders?['X-Atlassian-Token'], 'nocheck');

          final adoHeaders = TicketInputContextBuilder.resolveAuthHeadersForUrl(
            'https://dev.azure.com/org/proj/_apis/wit/attachments/1',
            reader,
          );
          expect(
            adoHeaders?['Authorization'],
            'Basic ${base64Encode(utf8.encode(':adopat'))}',
          );

          final other = TicketInputContextBuilder.resolveAuthHeadersForUrl(
            'https://unrelated.example.org/file.png',
            reader,
          );
          expect(other, isNull);
        },
      );
    });

    test('default HTTP downloader fetches 200 and skips 404', () async {
      if (!hasPython3()) return;
      final server = EchoServer();
      await server.start();
      final tmp = _createTempDir();
      try {
        final base = 'http://127.0.0.1:${server.port}';
        TicketInputContextBuilder(tmp.path).build('PROJ-HTTP', ticketData: {
          'key': 'PROJ-HTTP',
          'fields': {
            'attachment': [
              {
                'filename': 'shot.png',
                'content': '$base/download/attachments/1/shot.png',
              },
              {
                'filename': 'missing.html',
                'content': '$base/dt-html/missing',
              },
            ],
          },
        });
        final dir = '${tmp.path}/input/PROJ-HTTP';
        expect(File('$dir/shot.png').readAsStringSync(), 'PNG-fixture-bytes');
        expect(File('$dir/missing.html').existsSync(), isFalse);
      } finally {
        server.stop();
        tmp.deleteSync(recursive: true);
      }
    });
  });
}

// ======================================================================
// Fixtures
// ======================================================================

/// A complete Jira-style ticket with status, priority, and description.
Map<String, dynamic> _fullTicket() => {
      'key': 'PROJ-100',
      'fields': {
        'summary': 'Implement login',
        'description': 'Users need a login page with OAuth2.',
        'status': {'name': 'In Progress'},
        'priority': {'name': 'High'},
      },
    };

/// A ticket with two subtasks.
Map<String, dynamic> _ticketWithSubtasks() => {
      'key': 'PROJ-100',
      'fields': {
        'summary': 'Implement login',
        'description': 'Users need a login page.',
        'subtasks': [
          {
            'key': 'PROJ-101',
            'fields': {
              'summary': 'Build form',
              'description': 'Create the login form UI',
              'status': {'name': 'To Do'},
            },
          },
          {
            'key': 'PROJ-102',
            'fields': {
              'summary': 'Add OAuth2',
              'description': 'Wire up the OAuth2 flow',
            },
          },
        ],
      },
    };

/// A ticket with comments under the Jira `fields.comment.comments` structure.
Map<String, dynamic> _ticketWithComments() => {
      'key': 'PROJ-100',
      'fields': {
        'summary': 'Implement login',
        'description': 'Login page.',
        'comment': {
          'comments': [
            {
              'body': 'This looks good',
              'author': {'name': 'Alice'},
              'created': '2024-01-15',
            },
            {
              'body': 'Needs tests',
              'author': {'name': 'Bob'},
              'created': '2024-01-16',
            },
          ],
        },
      },
    };

/// An ADO work item with relation attachments and embedded HTML images.
Map<String, dynamic> _adoTicketWithAttachments() => {
      'id': 99,
      'fields': {
        'System.Title': 'ADO bug',
        'System.Description': '<p>See <img src="https://dev.azure.com/o/p/'
            '_apis/wit/attachments/1?fileName=inline.png&amp;download=true">'
            ' and <img src="https://dev.azure.com/o/p/_apis/wit/attachments/'
            'emb-42?api-version=7.0"></p>',
      },
      'relations': [
        {
          'rel': 'System.LinkTypes.Hierarchy-Reverse',
          'url': 'https://dev.azure.com/o/p/_apis/wit/workItems/1',
        },
        {
          'rel': 'AttachedFile',
          'url': 'https://dev.azure.com/o/p/_apis/wit/attachments/a1',
          'attributes': {'name': 'trace.log'},
        },
        {
          'rel': 'AttachedFile',
          'url': 'https://dev.azure.com/o/p/_apis/wit/attachments/a2'
              '?fileName=from_query.png',
        },
        {
          'rel': 'AttachedFile',
          'url': 'https://dev.azure.com/o/p/_apis/wit/attachments/fallback-id'
              '?api-version=7.0',
        },
      ],
    };

/// Creates a unique temporary directory.
Directory _createTempDir() {
  return Directory.systemTemp.createTempSync('ticket_ctx_test_');
}
