/// Release-asset tooling for the GitLab sync tools.
///
/// Ports the Java `GitLab` release surface (`getOrCreateRelease`,
/// `uploadReleaseAsset`, `downloadReleaseAsset`, dmtools-core): releases are
/// found by tag across paginated `projects/{id}/releases`, assets are stored
/// in the Generic Package Registry (`packages/generic/{name}/{version}/…`)
/// and attached to the release as `package` asset links. The binary transfer
/// bypasses [SyncHttpClient] — curl streams the real file via
/// `--data-binary @file` instead of a UTF-8 staged string.
library;

import 'dart:convert';
import 'dart:io';

import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Connection info for the release-asset helper flows.
typedef GitlabReleaseConn = ({String baseUrl, Map<String, String> headers});

/// Runs the `gitlab_get_or_create_release` flow for [args]: find by tag,
/// else create (resolving the project's default branch as the `ref`).
String gitlabGetOrCreateRelease({
  required String baseUrl,
  required Map<String, String> headers,
  required Map<String, dynamic> args,
}) {
  final tagName = syncAsStr(args['tagName']);
  final conn = (baseUrl: baseUrl, headers: headers);
  final existing = _findReleaseByTag(conn: conn, args: args, tagName: tagName);
  if (existing != null) return jsonEncode(existing);
  final body = _releasePayload(conn: conn, args: args, tagName: tagName);
  final url = '$baseUrl/projects/${gitlabEncodedProjectArg(args)}/releases';
  return syncPostJson(headers, url, jsonEncode(body));
}

/// Runs the `gitlab_upload_release_asset` flow for [args]: PUT the file to
/// the Generic Package Registry, then attach it to the release as an asset
/// link (with the optional `overwrite` pre-delete of a same-named asset).
String gitlabUploadReleaseAsset({
  required String baseUrl,
  required Map<String, String> headers,
  required Map<String, dynamic> args,
}) {
  final file = File(syncAsStr(args['filePath']));
  if (!file.existsSync()) {
    return syncErr('Release asset file not found: ${file.absolute.path}');
  }
  final tagName = syncAsStr(args['tagName']);
  final assetName = _resolveAssetName(args, file);
  final packageName = _resolvePackageName(args);
  final packageVersion = _sanitizePackageComponent(tagName);
  final conn = (baseUrl: baseUrl, headers: headers);
  if (syncAsStr(args['overwrite']).toLowerCase() == 'true') {
    _deleteExistingAssetByName(
      conn: conn,
      args: args,
      tagName: tagName,
      packageName: packageName,
      packageVersion: packageVersion,
      assetName: assetName,
    );
  }
  final upload = _uploadAssetFile(
    conn: conn,
    args: args,
    file: file,
    assetName: assetName,
    packageName: packageName,
    packageVersion: packageVersion,
  );
  if (upload.resp.statusCode == 0) {
    return syncErr('HTTP request failed: ${upload.resp.body}');
  }
  return _postReleaseLink(
    conn: (baseUrl: baseUrl, headers: headers),
    args: args,
    tagName: tagName,
    assetName: assetName,
    uploadUrl: upload.url,
    packageName: packageName,
  );
}

/// Runs the `gitlab_download_release_asset` flow for [args]: download a
/// Generic Package Registry file to a local path; returns the local path.
String gitlabDownloadReleaseAsset({
  required String baseUrl,
  required Map<String, String> headers,
  required Map<String, dynamic> args,
}) {
  final tagName = syncAsStr(args['tagName']);
  final packageName = _resolvePackageName(args);
  final packageVersion = _sanitizePackageComponent(tagName);
  final url = '$baseUrl/projects/${gitlabEncodedProjectArg(args)}'
      '/packages/generic/$packageName/$packageVersion'
      '/${_encodePathSegment(syncAsStr(args['assetName']))}';
  final target = File(syncAsStr(args['targetFilePath']));
  target.parent.createSync(recursive: true);
  final resp =
      syncCurlStaged('GET', url, headers: headers, outputFile: target.path);
  if (resp.statusCode == 0) return syncErr('HTTP request failed: ${resp.body}');
  return target.path;
}

/// Builds the release-create payload, resolving the default branch as the
/// `ref` when no `targetCommitish` was supplied.
Map<String, dynamic> _releasePayload({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required String tagName,
}) {
  final releaseName = syncAsStr(args['releaseName']);
  final targetCommitish = syncAsStr(args['targetCommitish']);
  final payload = <String, dynamic>{
    'tag_name': tagName,
    'name': syncIsBlank(releaseName) ? tagName : releaseName.trim(),
    'ref': syncIsBlank(targetCommitish)
        ? _resolveDefaultBranch(conn: conn, args: args)
        : targetCommitish.trim(),
  };
  final body = syncAsStr(args['body']);
  if (!syncIsBlank(body)) payload['description'] = body;
  return payload;
}

/// Finds a release with [tagName] across paginated `projects/{id}/releases`.
Map<String, dynamic>? _findReleaseByTag({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required String tagName,
}) {
  for (final release in gitlabFetchAllPages(
    conn.baseUrl,
    conn.headers,
    'projects/${gitlabEncodedProjectArg(args)}/releases',
  )) {
    if (release is Map && release['tag_name'] == tagName) {
      return Map<String, dynamic>.from(release);
    }
  }
  return null;
}

/// Resolves the project's default branch for release creation; `"main"` on
/// any failure (Java `resolveDefaultBranch`).
String _resolveDefaultBranch({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
}) {
  final url = '${conn.baseUrl}/projects/${gitlabEncodedProjectArg(args)}';
  final decoded = syncTryDecode(
      syncBodyOrError(SyncHttpClient.get(url, headers: conn.headers)));
  if (decoded is Map) {
    final branch = syncAsStr(decoded['default_branch']);
    if (branch.isNotEmpty) return branch;
  }
  return 'main';
}

/// PUTs the asset file into the Generic Package Registry; returns the
/// response plus the upload URL used.
({SyncHttpResponse resp, String url}) _uploadAssetFile({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required File file,
  required String assetName,
  required String packageName,
  required String packageVersion,
}) {
  final contentType = _detectContentType(file, syncAsStr(args['contentType']));
  final url = '${conn.baseUrl}/projects/${gitlabEncodedProjectArg(args)}'
      '/packages/generic/$packageName/$packageVersion'
      '/${_encodePathSegment(assetName)}';
  return (
    resp: syncCurlStaged(
      'PUT',
      url,
      headers: {...conn.headers, 'Content-Type': contentType},
      dataBinaryFile: file.path,
    ),
    url: url,
  );
}

/// POSTs the release asset link after a successful package upload.
String _postReleaseLink({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required String tagName,
  required String assetName,
  required String uploadUrl,
  required String packageName,
}) {
  final packageVersion = _sanitizePackageComponent(tagName);
  final linksUrl = '${conn.baseUrl}/projects/${gitlabEncodedProjectArg(args)}'
      '/releases/${_encodePathSegment(tagName)}/assets/links';
  return syncPostJson(
    conn.headers,
    linksUrl,
    jsonEncode({
      'name': assetName,
      'url': uploadUrl,
      'direct_asset_path': '/$packageName/$packageVersion/$assetName',
      'link_type': 'package',
    }),
  );
}

/// Resolves the asset name: explicit `assetName` or the local file name.
String _resolveAssetName(Map<String, dynamic> args, File file) =>
    syncIsBlank(syncAsStr(args['assetName']))
        ? file.uri.pathSegments.last
        : syncAsStr(args['assetName']).trim();

/// Resolves the package registry name: explicit `packageName` or
/// `release-assets` (the Java default).
String _resolvePackageName(Map<String, dynamic> args) {
  final explicit = syncAsStr(args['packageName']);
  return _sanitizePackageComponent(
    syncIsBlank(explicit) ? 'release-assets' : explicit.trim(),
  );
}

/// Deletes a same-named release link and generic package file (Java
/// `deleteExistingAssetByName`). Best effort: missing links/packages are
/// ignored.
void _deleteExistingAssetByName({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required String tagName,
  required String packageName,
  required String packageVersion,
  required String assetName,
}) {
  _deleteReleaseLinkByName(
    conn: conn,
    args: args,
    tagName: tagName,
    assetName: assetName,
  );
  final packageId = _findGenericPackageId(
    conn: conn,
    args: args,
    packageName: packageName,
    packageVersion: packageVersion,
  );
  if (packageId != null) {
    SyncHttpClient.delete(
      '${conn.baseUrl}/projects/${gitlabEncodedProjectArg(args)}'
      '/packages/$packageId',
      headers: conn.headers,
    );
  }
}

/// Deletes the release link named [assetName], if one exists.
void _deleteReleaseLinkByName({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required String tagName,
  required String assetName,
}) {
  final linksUrl = '${conn.baseUrl}/projects/${gitlabEncodedProjectArg(args)}'
      '/releases/${_encodePathSegment(tagName)}/assets/links';
  final links = syncTryDecode(
    syncBodyOrError(SyncHttpClient.get(linksUrl, headers: conn.headers)),
  );
  if (links is! List) return;
  for (final link in links) {
    if (link is Map && link['name'] == assetName) {
      SyncHttpClient.delete('$linksUrl/${link['id']}', headers: conn.headers);
      break;
    }
  }
}

/// Finds the generic package id for the release-assets package, or `null`.
String? _findGenericPackageId({
  required GitlabReleaseConn conn,
  required Map<String, dynamic> args,
  required String packageName,
  required String packageVersion,
}) {
  final url =
      '${conn.baseUrl}/projects/${gitlabEncodedProjectArg(args)}/packages'
      '?package_type=generic&package_name=$packageName'
      '&package_version=$packageVersion';
  final packages = syncTryDecode(
    syncBodyOrError(SyncHttpClient.get(url, headers: conn.headers)),
  );
  if (packages is! List) return null;
  for (final pkg in packages) {
    if (_matchesPackage(pkg, packageName, packageVersion)) {
      return '${pkg['id']}';
    }
  }
  return null;
}

/// Whether [pkg] carries the expected generic-package [name] and [version].
bool _matchesPackage(dynamic pkg, String name, String version) =>
    pkg is Map && pkg['name'] == name && pkg['version'] == version;

/// Detects the asset content type: explicit value, then the file extension
/// (a small name-based map mirroring the Java
/// `URLConnection.guessContentTypeFromName` fallback), then
/// `application/octet-stream` (Java `resolveAssetContentType`).
String _detectContentType(File file, String explicitType) {
  if (!syncIsBlank(explicitType)) return explicitType.trim();
  final extension = file.path.split('.').last.toLowerCase();
  return _contentTypesByExtension[extension] ?? 'application/octet-stream';
}

/// Common asset extensions → MIME types (the release-assets file kinds the
/// agent scripts upload: images, archives, documents, text).
const _contentTypesByExtension = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'svg': 'image/svg+xml',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'tar': 'application/x-tar',
  'json': 'application/json',
  'xml': 'application/xml',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'html': 'text/html',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
};

/// Collects all pages of a GitLab array endpoint via `per_page`/`page`,
/// until a short page or [maxResults] (ports the Java `fetchAllPages`).
List<dynamic> gitlabFetchAllPages(
  String baseUrl,
  Map<String, String> headers,
  String path, {
  int perPage = 100,
  int? maxResults,
}) {
  final all = <dynamic>[];
  var page = 1;
  final separator = path.contains('?') ? '&' : '?';
  while (maxResults == null || all.length < maxResults) {
    final url = '$baseUrl/$path${separator}per_page=$perPage&page=$page';
    final decoded = syncTryDecode(
      syncBodyOrError(SyncHttpClient.get(url, headers: headers)),
    );
    if (decoded is! List) break;
    _appendUpTo(all, decoded, maxResults);
    if (decoded.length < perPage) break;
    page++;
  }
  return all;
}

/// Appends one [page] of items to [all], stopping at [maxResults].
void _appendUpTo(List<dynamic> all, List page, int? maxResults) {
  for (final item in page) {
    if (maxResults != null && all.length >= maxResults) break;
    all.add(item);
  }
}

/// URL-encodes the project argument: Java `workspace`/`repository` pair or
/// the legacy `project` value, as a `group%2Frepo` path segment.
String gitlabEncodedProjectArg(Map<String, dynamic> args) =>
    Uri.encodeComponent(_gitlabProjectArg(args));

/// Resolves the project string (`workspace/repository` or legacy `project`).
String _gitlabProjectArg(Map<String, dynamic> args) {
  final workspace = syncAsStr(args['workspace']);
  if (workspace.isNotEmpty)
    return '$workspace/${syncAsStr(args['repository'])}';
  return syncAsStr(args['project']);
}

/// Sanitizes a package name/version segment: only `[A-Za-z0-9_.+-]` are
/// legal in the Generic Package Registry; everything else becomes `-`.
String _sanitizePackageComponent(String value) {
  final sanitized = value.trim().replaceAll(RegExp('[^A-Za-z0-9_.+-]'), '-');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}

/// URL-encodes a single path segment (space as `%20`, like Java
/// `urlEncodePathSegment`).
String _encodePathSegment(String value) => Uri.encodeComponent(value);
