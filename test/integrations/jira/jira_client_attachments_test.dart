import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// Attachment tests: attachFileToTicket, downloadAttachment
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  attachFileToTicketTests();
  downloadAttachmentTests();
  attachmentsExecutorDispatchTests();
}

/// `jira_attach_file_to_ticket` — POST multipart `issue/{key}/attachments`.
void attachFileToTicketTests() {
  group('JiraClient.attachFileToTicket', () {
    test('uploads a local file as multipart POST', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/dmtools_test_attach_${DateTime.now().millisecondsSinceEpoch}.txt');
      tmp.writeAsStringSync('attachment payload');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final f = mockJira((o) => '[]');
      final result =
          await f.client.attachFileToTicket('PROJ-1', 'notes.txt', tmp.path);

      final call = f.adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.path, contains('/rest/api/latest/issue/PROJ-1/attachments'));
      expect(call.headers['X-Atlassian-Token'], 'nocheck');
      expect(result, isEmpty);
    });
  });
}

/// `jira_download_attachment` — GET binary and write to local file.
void downloadAttachmentTests() {
  group('JiraClient.downloadAttachment', () {
    test('downloads bytes and writes them to filePath', () async {
      const url = 'https://jira.example.com/secure/attachment/10001/file.txt';
      final target = File(
          '${Directory.systemTemp.path}/dmtools_test_dl_${DateTime.now().millisecondsSinceEpoch}.bin');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync();
      });

      final f = mockJira((o) => 'downloaded bytes');
      await f.client.downloadAttachment(url, target.path);

      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, url);
      expect(target.existsSync(), isTrue);
      expect(target.readAsStringSync(), 'downloaded bytes');
    });
  });
}

/// [JiraToolExecutor.execute] routes attachment tool names.
void attachmentsExecutorDispatchTests() {
  group('JiraToolExecutor.execute (attachments)', () {
    test('routes jira_attach_file_to_ticket', () async {
      final tmp = _tempFile('exec');
      final f = mockJira((o) => '[]');
      await executor(f).execute('jira_attach_file_to_ticket', {
        'key': 'PROJ-1',
        'fileName': 'notes.txt',
        'filePath': tmp.path,
      });
      expect(f.adapter.calls.single.method, 'POST');
      expect(
          f.adapter.calls.single.path, contains('/issue/PROJ-1/attachments'));
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Creates a temporary file with content for attachment tests.
File _tempFile(String prefix) {
  final f = File(
      '${Directory.systemTemp.path}/dmtools_$prefix${DateTime.now().millisecondsSinceEpoch}.txt');
  f.writeAsStringSync('x');
  addTearDown(() {
    if (f.existsSync()) f.deleteSync();
  });
  return f;
}
