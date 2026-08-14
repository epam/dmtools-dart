import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'confluence_test_support.dart';

/// Attachment coverage: list page attachments and download one — plus the
/// matching tool definitions and executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getPageAttachmentsTests();
  downloadAttachmentTests();
  attachmentToolDefinitionTests();
  attachmentExecutorDispatchTests();
}

/// Looks up a registered tool by name.
ToolDefinition toolNamed(String name) =>
    confluenceTools().firstWhere((t) => t.name == name);

/// `confluence_get_page_attachments` — GET `content/{id}/child/attachment`.
void getPageAttachmentsTests() {
  group('ConfluenceClient.getPageAttachments', () {
    test('returns the attachment results', () async {
      final f = mockConfluence(
          (o) => routeByPath({'/child/attachment': _attachmentsBody}, o));
      final attachments = await f.client.getPageAttachments('42');
      expect(attachments, hasLength(1));
      expect(attachments[0]['title'], 'file.pdf');
      expect(f.adapter.calls.single.path,
          endsWith('/content/42/child/attachment'));
    });
  });
}

/// `confluence_download_attachment` — GET
/// `content/{pageId}/child/attachment/{attachmentId}/download`.
void downloadAttachmentTests() {
  group('ConfluenceClient.downloadAttachment', () {
    test('returns the raw download content', () async {
      final f = mockConfluence(
        (o) => routeByPath({'/download': _downloadBody}, o),
      );
      final content = await f.client.downloadAttachment('42', 'att-1');
      expect(content, _downloadBody);
      expect(
        f.adapter.calls.single.path,
        endsWith('/content/42/child/attachment/att-1/download'),
      );
    });
  });
}

/// Tool-definition shape for the attachment tools.
void attachmentToolDefinitionTests() {
  group('confluence tool definitions (attachments)', () {
    test('confluence_get_page_attachments requires pageId', () {
      final tool = toolNamed('confluence_get_page_attachments');
      expect(tool.category, 'attachments');
      expect(tool.params.single.name, 'pageId');
    });

    test('confluence_download_attachment requires pageId and attachmentId', () {
      final tool = toolNamed('confluence_download_attachment');
      expect(tool.category, 'attachments');
      expect(tool.params.map((p) => p.name), ['pageId', 'attachmentId']);
      expect(tool.params.every((p) => p.required), isTrue);
    });
  });
}

/// [ConfluenceToolExecutor.execute] routes each attachment tool name.
void attachmentExecutorDispatchTests() {
  group('ConfluenceToolExecutor.execute (attachments)', () {
    test('routes confluence_get_page_attachments', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_get_page_attachments',
        {'pageId': '42'},
      );
      expect(f.client.calls, ['getPageAttachments:42']);
    });

    test('routes confluence_download_attachment', () async {
      final f = _makeExecutor();
      await f.executor.execute(
        'confluence_download_attachment',
        {'pageId': '42', 'attachmentId': 'att-1'},
      );
      expect(f.client.calls, ['downloadAttachment:42:att-1']);
    });
  });
}

/// Executor + spy wired over a mock adapter returning `{}`.
({ConfluenceToolExecutor executor, _AttachmentsSpy client}) _makeExecutor() {
  final client = _AttachmentsSpy(mockHttp((o) => '{}').http);
  return (executor: ConfluenceToolExecutor(client), client: client);
}

/// Canned attachments response body.
final _attachmentsBody = jsonEncode({
  'results': [
    {'title': 'file.pdf', 'id': 'att1'},
  ],
});

/// Canned download-attachment raw content.
const _downloadBody = 'binary-content-here';

/// Spy that records every attachment call then delegates to the real client.
class _AttachmentsSpy extends ConfluenceClient {
  _AttachmentsSpy(super.http);

  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getPageAttachments(String pageId) {
    calls.add('getPageAttachments:$pageId');
    return super.getPageAttachments(pageId);
  }

  @override
  Future<String> downloadAttachment(String pageId, String attachmentId) {
    calls.add('downloadAttachment:$pageId:$attachmentId');
    return super.downloadAttachment(pageId, attachmentId);
  }
}
