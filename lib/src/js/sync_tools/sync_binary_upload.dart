/// Shared curl-based binary upload for the sync tools.
///
/// [SyncHttpClient] only carries `String` bodies, so raw file uploads run
/// curl directly: `--data-binary @file` with the headers staged in a temp
/// file (never in argv), 10s connect / 60s total timeouts.
library;

import 'dart:io';

import '../sync_http_client.dart';

/// POSTs the raw bytes of [file] to [url] with [headers]; [tempPrefix]
/// names the staging directory.
SyncHttpResponse syncCurlUpload(
  String url,
  Map<String, String> headers,
  File file, {
  String tempPrefix = 'dmtools_upload_',
}) {
  final dir = Directory.systemTemp.createTempSync(tempPrefix);
  try {
    final headerFile = File('${dir.path}/headers')
      ..writeAsStringSync(
        SyncHttpClient.renderHeaderFile(headers),
        flush: true,
      );
    final result = Process.runSync('curl', [
      '-s',
      '-X',
      'POST',
      '-w',
      '\n%{http_code}',
      '--connect-timeout',
      '10',
      '--max-time',
      '60',
      '-H',
      '@${headerFile.path}',
      '--data-binary',
      '@${file.path}',
      url,
    ]);
    return SyncHttpClient.parseResponse(result);
  } finally {
    dir.deleteSync(recursive: true);
  }
}
