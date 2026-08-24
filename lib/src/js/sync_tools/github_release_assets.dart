/// Release-asset upload for the GitHub sync tools.
///
/// Ports Java `GitHub.uploadReleaseAsset`: validate the local file,
/// optionally delete a same-named asset (`overwrite`), then upload the
/// raw file bytes. The upload bypasses [SyncHttpClient] because asset
/// bodies are binary — curl streams the real file via
/// `--data-binary @file` instead of a UTF-8 staged string.
library;

import 'dart:io';

import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Runs the `github_upload_release_asset` flow for [args].
///
/// Returns the uploaded asset JSON, or an error JSON string.
String uploadReleaseAsset({
  required String baseUrl,
  required Map<String, String> headers,
  required Map<String, dynamic> args,
}) {
  final filePath = syncAsStr(args['filePath']);
  final file = File(filePath);
  if (!file.existsSync()) {
    return syncErr('Release asset file not found: ${file.absolute.path}');
  }
  if (FileSystemEntity.typeSync(filePath) != FileSystemEntityType.file) {
    return syncErr(
      'Release asset path must point to a file: ${file.absolute.path}',
    );
  }
  final assetName = syncIsBlank(args['assetName'])
      ? file.uri.pathSegments.last
      : syncAsStr(args['assetName']).trim();
  if (syncAsStr(args['overwrite']).toLowerCase() == 'true') {
    _deleteExistingAssetByName(
      baseUrl: baseUrl,
      headers: headers,
      release: _releaseRef(args),
      assetName: assetName,
    );
  }
  final contentType = syncIsBlank(args['contentType'])
      ? _guessContentType(assetName)
      : syncAsStr(args['contentType']).trim();
  return _uploadAssetBytes(
    baseUrl: baseUrl,
    headers: headers,
    release: _releaseRef(args),
    file: file,
    asset: (
      name: assetName,
      contentType: contentType,
      label: syncAsStr(args['label']),
    ),
  );
}

/// The `repos/{workspace}/{repository}` + release id pair from [args].
({String repoSegment, String releaseId}) _releaseRef(
  Map<String, dynamic> args,
) =>
    (repoSegment: _repoSeg(args), releaseId: syncAsStr(args['releaseId']));

/// Deletes the first asset named [assetName] on the release, if any.
void _deleteExistingAssetByName({
  required String baseUrl,
  required Map<String, String> headers,
  required ({String repoSegment, String releaseId}) release,
  required String assetName,
}) {
  final url =
      '$baseUrl/${release.repoSegment}/releases/${release.releaseId}/assets';
  final resp = SyncHttpClient.get(url, headers: headers);
  final decoded = resp.isOk ? syncTryDecode(resp.body) : null;
  if (decoded is! List) return;
  for (final asset in decoded) {
    if (asset is Map && assetName == asset['name']) {
      SyncHttpClient.delete(
        '$baseUrl/${release.repoSegment}/releases/assets/${syncAsStr(asset['id'])}',
        headers: headers,
      );
      return;
    }
  }
}

/// Uploads [asset] as a release asset via `--data-binary @file`.
///
/// The upload host is `uploads.github.com` in production; a custom base
/// path keeps its own host and gains an `/uploads` prefix so proxies and
/// tests can intercept (deviation from Java's hardcoded host, noted in
/// the porting report).
String _uploadAssetBytes({
  required String baseUrl,
  required Map<String, String> headers,
  required ({String repoSegment, String releaseId}) release,
  required File file,
  required ({String name, String contentType, String label}) asset,
}) {
  final base = baseUrl == 'https://api.github.com'
      ? 'https://uploads.github.com'
      : '$baseUrl/uploads';
  var url = '$base/${release.repoSegment}/releases/${release.releaseId}/assets'
      '?name=${Uri.encodeQueryComponent(asset.name)}';
  if (!syncIsBlank(asset.label)) {
    url += '&label=${Uri.encodeQueryComponent(asset.label.trim())}';
  }
  return syncBodyOrError(
    _curlUpload(url, {...headers, 'Content-Type': asset.contentType}, file),
  );
}

/// Runs the binary upload curl command with staged headers.
SyncHttpResponse _curlUpload(
  String url,
  Map<String, String> headers,
  File file,
) {
  final dir = Directory.systemTemp.createTempSync('dmtools_gh_upload_');
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

/// Content-type guess for common asset extensions.
String _guessContentType(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'svg' => 'image/svg+xml',
    'txt' || 'log' => 'text/plain',
    'md' => 'text/markdown',
    'json' => 'application/json',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

/// `repos/{workspace}/{repository}` URL segment from Java param names.
String _repoSeg(Map<String, dynamic> a) =>
    'repos/${syncAsStr(a['workspace'])}/${syncAsStr(a['repository'])}';
