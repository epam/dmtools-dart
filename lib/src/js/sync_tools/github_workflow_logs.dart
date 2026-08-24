/// Workflow-run log fetching for the GitHub sync tools.
///
/// Ports Java `GitHubWorkflowUtils.downloadWorkflowRunLogs`: GitHub's
/// `actions/runs/{id}/logs` endpoint answers 302 with a pre-signed
/// archive URL; the ZIP is downloaded and every `.txt` entry is
/// concatenated with `--- name ---` separators.
///
/// These calls bypass [SyncHttpClient] (curl subprocess) because they
/// need response headers (the `Location` redirect) and raw binary
/// stdout — both outside the string-only [SyncHttpClient] contract.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../sync_http_client.dart';

/// Fetches and extracts the workflow-run log archive for [runId].
///
/// Returns the concatenated `.txt` entries, or a JSON error string on
/// failure (mirrors the executor error contract).
String fetchWorkflowRunLogs({
  required String baseUrl,
  required Map<String, String> headers,
  required String repoSegment,
  required String runId,
}) {
  final url = '$baseUrl/$repoSegment/actions/runs/$runId/logs';
  final zipUrl = _resolveRedirect(url, headers);
  if (zipUrl == null) {
    return _err('Expected redirect (301/302) fetching workflow run logs');
  }
  final zip = _downloadBytes(zipUrl);
  if (zip == null) return _err('Failed downloading workflow run logs');
  return _extractZipTextEntries(zip);
}

/// Follows one redirect hop for [url], returning the `Location` target.
///
/// Only `https://` targets are accepted (Java's SSRF guard), with an
/// exception for loopback hosts so self-hosted proxies and tests work.
String? _resolveRedirect(String url, Map<String, String> headers) {
  final dir = Directory.systemTemp.createTempSync('dmtools_gh_redir_');
  try {
    final dump = File('${dir.path}/headers');
    final headerFile = File('${dir.path}/request_headers')
      ..writeAsStringSync(SyncHttpClient.renderHeaderFile(headers),
          flush: true);
    final result = Process.runSync('curl', [
      '-s',
      '-D',
      dump.path,
      '-w',
      '\n%{http_code}',
      '--connect-timeout',
      '10',
      '--max-time',
      '60',
      '-H',
      '@${headerFile.path}',
      url,
    ]);
    final resp = SyncHttpClient.parseResponse(result);
    if (resp.statusCode != 301 && resp.statusCode != 302) return null;
    final location = _headerValue(dump.readAsStringSync(), 'location');
    if (location == null || location.isEmpty) return null;
    return _isAllowedRedirectTarget(location) ? location : null;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Whether [location] is an acceptable redirect target.
bool _isAllowedRedirectTarget(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  return uri.scheme == 'https' ||
      uri.host == '127.0.0.1' ||
      uri.host == 'localhost';
}

/// Case-insensitive header lookup in a curl `-D` dump.
String? _headerValue(String dump, String name) {
  for (final line in dump.split('\n')) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    if (line.substring(0, idx).trim().toLowerCase() == name) {
      return line.substring(idx + 1).trim();
    }
  }
  return null;
}

/// Downloads raw bytes from [url]; `null` on a non-2xx response.
///
/// stdout is left undecoded (binary-safe); the `-w` status line is the
/// trailing bytes after the last newline.
List<int>? _downloadBytes(String url) {
  final result = Process.runSync(
    'curl',
    [
      '-s',
      '-w',
      '\n%{http_code}',
      '--connect-timeout',
      '10',
      '--max-time',
      '60',
      url,
    ],
    stdoutEncoding: null,
  );
  final bytes = (result.stdout as List<dynamic>).cast<int>();
  final lastNewline = bytes.lastIndexOf(10);
  if (lastNewline < 0) return null;
  final status =
      int.tryParse(String.fromCharCodes(bytes.sublist(lastNewline + 1)));
  if (status == null || status < 200 || status >= 300) return null;
  return bytes.sublist(0, lastNewline);
}

/// Extracts every `.txt` entry from [zip] bytes and concatenates them
/// with `--- name ---` separators (Java `downloadWorkflowRunLogs`).
String _extractZipTextEntries(List<int> zip) {
  final buffer = Uint8List.fromList(zip);
  final entries = _zipEntries(buffer);
  final parts = <String>[];
  for (final entry in entries) {
    if (!entry.name.endsWith('.txt')) continue;
    final bytes = _zipEntryBytes(buffer, entry);
    parts.add(
      '--- ${entry.name} ---\n\n${utf8.decode(bytes, allowMalformed: true)}',
    );
  }
  return parts.join('\n\n');
}

/// One ZIP central-directory entry.
class _ZipEntry {
  const _ZipEntry(this.name, this.method, this.compSize, this.localOffset);

  final String name;
  final int method;
  final int compSize;
  final int localOffset;
}

/// ZIP central-directory file-header signature (`PK\x01\x02`).
const _zipCentralDirSignature = 0x02014b50;

/// ZIP End-of-Central-Directory signature (`PK\x05\x06`).
const _zipEocdSignature = 0x06054b50;

/// Reads the central directory of [zip].
List<_ZipEntry> _zipEntries(Uint8List zip) {
  final eocd = _findEocd(zip);
  if (eocd < 0) return const [];
  final count = _u16(zip, eocd + 10);
  var offset = _u32(zip, eocd + 16);
  final entries = <_ZipEntry>[];
  for (var i = 0; i < count; i++) {
    if (offset + 46 > zip.length ||
        _u32(zip, offset) != _zipCentralDirSignature) {
      break;
    }
    final method = _u16(zip, offset + 10);
    final compSize = _u32(zip, offset + 20);
    final nameLen = _u16(zip, offset + 28);
    final extraLen = _u16(zip, offset + 30);
    final commentLen = _u16(zip, offset + 32);
    final localOffset = _u32(zip, offset + 42);
    final name = utf8.decode(zip.sublist(offset + 46, offset + 46 + nameLen));
    entries.add(_ZipEntry(name, method, compSize, localOffset));
    offset += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

/// Locates the End of Central Directory record, or `-1`.
int _findEocd(Uint8List zip) {
  final start = (zip.length - 22 - 65535).clamp(0, zip.length);
  for (var i = zip.length - 22; i >= start; i--) {
    if (_u32(zip, i) == _zipEocdSignature) return i;
  }
  return -1;
}

/// Inflates one entry's data (stored or deflate).
List<int> _zipEntryBytes(Uint8List zip, _ZipEntry entry) {
  final header = entry.localOffset;
  final nameLen = _u16(zip, header + 26);
  final extraLen = _u16(zip, header + 28);
  final dataStart = header + 30 + nameLen + extraLen;
  final data = zip.sublist(dataStart, dataStart + entry.compSize);
  if (entry.method == 0) return data;
  return ZLibCodec(raw: true).decode(data);
}

/// Little-endian u16 at [offset].
int _u16(Uint8List b, int offset) => b[offset] | (b[offset + 1] << 8);

/// Little-endian u32 at [offset].
int _u32(Uint8List b, int offset) =>
    b[offset] |
    (b[offset + 1] << 8) |
    (b[offset + 2] << 16) |
    (b[offset + 3] << 24);

/// Encodes a JSON error result string.
String _err(String message) => jsonEncode({'error': message});
