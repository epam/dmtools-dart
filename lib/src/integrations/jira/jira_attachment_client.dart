/// Attachment extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Attachment methods on [JiraClient]: multipart upload, binary download,
/// and attachment metadata reads.
extension JiraAttachmentClient on JiraClient {
  /// `jira_attach_file_to_ticket` — POST `issue/{key}/attachments`.
  ///
  /// Uploads the file at [filePath] as a multipart form part named [fileName].
  Future<Map<String, dynamic>> attachFileToTicket(
    String key,
    String fileName,
    String filePath,
  ) async {
    final bytes = await File(filePath).readAsBytes();
    final body = await _http.postMultipart(
      'issue/$key/attachments',
      fileName: fileName,
      bytes: bytes,
    );
    return _decodeMap(body);
  }

  /// `jira_download_attachment` — GET binary from [url] and save locally.
  ///
  /// Writes the downloaded bytes to [filePath] on the local filesystem.
  Future<void> downloadAttachment(String url, String filePath) async {
    final bytes = await _http.getBytes(url);
    await File(filePath).writeAsBytes(bytes);
  }

  /// `jira_get_attachments` — reads `fields.attachment` from the ticket.
  ///
  /// Returns the attachment metadata array; an empty list when the ticket is
  /// absent or has no attachments.
  Future<List<Map<String, dynamic>>> getAttachments(String key) async {
    final ticket = await getTicket(key, ['attachment']);
    if (ticket == null) return const [];
    final fields = ticket['fields'] as Map<String, dynamic>? ?? {};
    return _castObjectList(fields['attachment'] as List? ?? const []);
  }
}
