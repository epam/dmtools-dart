/// Resolves a versioned agent pack (a local `.zip` file or an HTTPS URL) to an
/// unpacked, verified, cached directory that `dmtools run` can execute from.
///
/// Dart port of the Java `AgentPackResolver` (dm.ai #579); the pack format is
/// produced by `AgentPackCompiler` (dm.ai #595).
///
/// Pipeline: detect pack → download (URL only; `SOURCE_GITHUB_TOKEN` for
/// github.com) → verify SHA-256 against the sibling `.sha256` asset (a missing
/// sidecar skips verification with a loud warning, per the Java reference) →
/// validate the manifest `agent`/`version` (strict charset — they build the
/// cache path) → unpack into a staging dir on the cache's own filesystem and
/// atomically rename into `~/.dmtools/packs/<agent>-<version>/` with zip-slip
/// protection (no absolute paths, no `..` escapes, no symlink entries, per-file
/// and total size caps) → verify every unpacked file against the manifest's
/// per-file sha256 inventory (unlisted zip entries and manifest-listed files
/// absent from the zip are both rejected) → cache-hit short-circuit → return
/// the entry config inside the cache (the entry name is containment-checked
/// against the pack root). Encrypted zips are rejected with a dedicated error.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../js/sync_http_client.dart';

/// The outcome of resolving a pack: the unpacked root and the entry config.
class ResolvedPack {
  /// Creates a resolved pack handle.
  const ResolvedPack({
    required this.packRoot,
    required this.entryFile,
    required this.agent,
    required this.version,
  });

  /// The unpacked pack cache directory.
  final Directory packRoot;

  /// The entry config file inside the cache.
  final File entryFile;

  /// The agent name from the manifest.
  final String agent;

  /// The pack version from the manifest.
  final String version;
}

/// Thrown when pack resolution fails (download, verification, zip-slip, ...).
class AgentPackException implements Exception {
  /// Creates an exception with [message].
  const AgentPackException(this.message);

  /// The failure description.
  final String message;

  @override
  String toString() => 'AgentPackException: $message';
}

/// Agent pack resolver — see the library doc for the pipeline.
class AgentPackResolver {
  /// Creates a resolver; [packsRoot] defaults to `~/.dmtools/packs`.
  AgentPackResolver({Directory? packsRoot})
      : _packsRoot =
            packsRoot ?? Directory(p.join(_home(), '.dmtools', 'packs'));

  final Directory _packsRoot;

  /// Per-file unpack size cap (64 MiB).
  static const int maxFileBytes = 64 * 1024 * 1024;

  /// Total unpack size cap (512 MiB).
  static const int maxTotalBytes = 512 * 1024 * 1024;

  static String _home() =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  /// True when [runArg] names a pack: a `.zip` path that exists, or an
  /// `http(s)://…​.zip` URL, with an optional `#entry.json` suffix.
  bool isPack(String? runArg) {
    if (runArg == null) return false;
    final base = stripEntry(runArg);
    if (base.startsWith('http://') || base.startsWith('https://')) {
      return base.toLowerCase().endsWith('.zip');
    }
    return base.toLowerCase().endsWith('.zip') && File(base).existsSync();
  }

  /// Resolves [runArg] to a cached, verified pack.
  ///
  /// [githubToken] authorizes private GitHub release downloads.
  /// Throws [AgentPackException] on download/verification/unpack failures.
  ResolvedPack resolve(String runArg, {String? githubToken}) {
    final entryOverride = entryOverrideOf(runArg);
    final base = stripEntry(runArg);

    final zipFile = _obtainZip(base, githubToken);
    try {
      final manifest = _readManifest(zipFile);
      final agent = _manifestString(manifest, 'agent');
      final version = _manifestString(manifest, 'version');
      _validateManifestIdentity(agent, version);

      final packRoot = Directory(p.join(_packsRoot.path, '$agent-$version'));
      _unpackAndVerify(zipFile, manifest, packRoot);

      final entryName =
          entryOverride ?? _manifestString(manifest, 'defaultEntry');
      _validateEntryName(entryName, packRoot);
      final entryFile = File(p.join(packRoot.path, entryName));
      if (!entryFile.existsSync()) {
        throw AgentPackException(
            "Entry '$entryName' not found in pack $agent-$version. "
            "manifest.json defaultEntry: ${manifest['defaultEntry']}");
      }
      return ResolvedPack(
          packRoot: packRoot,
          entryFile: entryFile,
          agent: agent,
          version: version);
    } finally {
      // Clean up a downloaded temp zip (local files are left in place).
      if (base.startsWith('http') && zipFile.existsSync()) zipFile.deleteSync();
    }
  }

  // ------------------------------------------------------------------
  // Argument parsing
  // ------------------------------------------------------------------

  /// Splits off an optional `#entry.json` override.
  static String stripEntry(String runArg) {
    final hash = runArg.indexOf('#');
    return hash >= 0 ? runArg.substring(0, hash) : runArg;
  }

  /// The `#entry.json` override, or `null`.
  static String? entryOverrideOf(String runArg) {
    final hash = runArg.indexOf('#');
    return hash >= 0 ? runArg.substring(hash + 1) : null;
  }

  // ------------------------------------------------------------------
  // Download (URL) / read (file)
  // ------------------------------------------------------------------

  File _obtainZip(String base, String? githubToken) {
    if (base.startsWith('http://') || base.startsWith('https://')) {
      return _download(base, githubToken);
    }
    final file = File(base);
    if (!file.existsSync()) {
      throw AgentPackException('Pack file not found: $base');
    }
    return file;
  }

  File _download(String urlString, String? githubToken) {
    final headers = <String, String>{'Accept': 'application/octet-stream'};
    if (githubToken != null && Uri.parse(urlString).host == 'github.com') {
      headers['Authorization'] = 'Bearer $githubToken';
    }
    final response = SyncHttpClient.get(urlString, headers: headers);
    if (response.statusCode != 200) {
      throw AgentPackException(
          'Failed to download pack: HTTP ${response.statusCode} for $urlString');
    }
    final tmp = File(
        '${Directory.systemTemp.path}/dmtools-pack-${DateTime.now().microsecondsSinceEpoch}.zip');
    tmp.writeAsBytesSync(response.bodyBytes);
    _verifyDownloadedSha256(tmp, urlString, githubToken);
    return tmp;
  }

  /// Verifies the downloaded zip against the sibling `.sha256` asset.
  void _verifyDownloadedSha256(
      File zipFile, String zipUrl, String? githubToken) {
    final headers = <String, String>{'Accept': 'application/octet-stream'};
    if (githubToken != null && Uri.parse(zipUrl).host == 'github.com') {
      headers['Authorization'] = 'Bearer $githubToken';
    }
    final response = SyncHttpClient.get('$zipUrl.sha256', headers: headers);
    if (response.statusCode != 200) {
      // Java parity (AgentPackResolver logs a warning): an absent sidecar
      // means "no checksum published" — verification is skipped, not failed,
      // but the skip is announced loudly so it shows up in run logs.
      stderr.writeln('WARNING: no .sha256 checksum asset for $zipUrl '
          '(HTTP ${response.statusCode}) — skipping download integrity check');
      return;
    }
    final expected = response.body.trim().split(RegExp(r'\s+')).first;
    final actual = sha256.convert(zipFile.readAsBytesSync()).toString();
    if (expected.toLowerCase() != actual) {
      zipFile.deleteSync();
      throw AgentPackException(
          'SHA-256 mismatch for $zipUrl (expected $expected, got $actual)');
    }
  }

  // ------------------------------------------------------------------
  // Manifest
  // ------------------------------------------------------------------

  Map<String, dynamic> _readManifest(File zipFile) {
    final bytes = zipFile.readAsBytesSync();
    _rejectIfEncrypted(bytes, zipFile);
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestEntry = _findEntry(archive, 'manifest.json');
    if (manifestEntry == null) {
      throw AgentPackException(
          'Pack has no manifest.json: ${p.basename(zipFile.path)}');
    }
    final manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>))
        as Map<String, dynamic>;
    if (!manifest.containsKey('agent') ||
        !manifest.containsKey('version') ||
        !manifest.containsKey('defaultEntry')) {
      throw const AgentPackException(
          'manifest.json missing required keys (agent/version/defaultEntry)');
    }
    return manifest;
  }

  /// Reads a manifest string key, failing with a clean [AgentPackException]
  /// (not a bare `TypeError`) when the value is missing or not a string.
  static String _manifestString(Map<String, dynamic> manifest, String key) {
    final value = manifest[key];
    if (value is! String) {
      throw AgentPackException('manifest.json "$key" must be a string '
          '(got ${value.runtimeType})');
    }
    return value;
  }

  /// Allowed charset for manifest `agent`/`version` — these untrusted strings
  /// build the cache path, so slashes and dot-only segments are refused
  /// (cache-path traversal guard; also shields the recursive delete).
  static final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9._-]+$');

  /// A segment made only of dots (`.` / `..` / `...`) is a traversal vector.
  static final RegExp _dotsOnly = RegExp(r'^\.+$');

  /// Rejects unsafe manifest `agent`/`version` values BEFORE any cache path
  /// is built from them.
  void _validateManifestIdentity(String agent, String version) {
    for (final pair in {'agent': agent, 'version': version}.entries) {
      final value = pair.value;
      if (value.isEmpty ||
          !_safeSegment.hasMatch(value) ||
          _dotsOnly.hasMatch(value)) {
        throw AgentPackException('Unsafe manifest ${pair.key}: "$value" '
            '(allowed: [A-Za-z0-9._-], no dot-only segments)');
      }
    }
  }

  /// Containment-checks an entry-config name (a `#entry` CLI override or the
  /// manifest `defaultEntry`) against [packRoot], so a hostile or careless
  /// value cannot point the run at a file outside the unpacked pack.
  void _validateEntryName(String entryName, Directory packRoot) {
    final root = p.normalize(packRoot.absolute.path);
    final target = p.normalize(p.join(root, entryName));
    if (p.isAbsolute(entryName) || !p.isWithin(root, target)) {
      throw AgentPackException('Entry escapes the pack root: $entryName');
    }
  }

  /// AC6: encrypted zips are rejected with a dedicated error. The archive
  /// package does not surface an `isEncrypted` flag, so walk the central
  /// directory (located via the End Of Central Directory record) and check
  /// each header's general-purpose bit flag (bit 0 = encrypted). Walking real
  /// headers — instead of scanning raw bytes for the signature — avoids
  /// false positives from stored payloads that merely contain "PK\x01\x02".
  void _rejectIfEncrypted(List<int> zipBytes, File zipFile) {
    for (final flags in _centralDirectoryFlags(zipBytes)) {
      if (flags & 0x0001 != 0) {
        throw AgentPackException(
            'Encrypted agent packs are not supported yet: ${p.basename(zipFile.path)} '
            '(encryption support is a planned future hook)');
      }
    }
  }

  /// Yields the general-purpose bit flag of every central-directory header.
  /// Yields nothing when the EOCD record or a header signature is missing —
  /// a corrupt zip then fails in the decoder with its own error.
  Iterable<int> _centralDirectoryFlags(List<int> bytes) sync* {
    final eocd = _findEocd(bytes);
    if (eocd < 0) return;
    final count = _uint16(bytes, eocd + 10);
    var offset = _uint32(bytes, eocd + 16);
    for (var i = 0; i < count && offset + 46 <= bytes.length; i++) {
      if (_uint32(bytes, offset) != _centralHeaderSignature) return;
      yield _uint16(bytes, offset + 8);
      offset += 46 +
          _uint16(bytes, offset + 28) + // file name length
          _uint16(bytes, offset + 30) + // extra field length
          _uint16(bytes, offset + 32); // comment length
    }
  }

  /// Central directory header signature ("PK\x01\x02" little-endian).
  static const int _centralHeaderSignature = 0x02014b50;

  /// End Of Central Directory record signature ("PK\x05\x06" little-endian).
  static const int _eocdSignature = 0x06054b50;

  /// Locates the EOCD record in the trailing comment window (22 bytes fixed
  /// + up to 65535 bytes of zip comment); -1 when absent.
  int _findEocd(List<int> bytes) {
    final earliest = bytes.length > 65558 ? bytes.length - 65558 : 0;
    for (var i = bytes.length - 22; i >= earliest; i--) {
      if (_uint32(bytes, i) == _eocdSignature) return i;
    }
    return -1;
  }

  /// Little-endian uint16 at [offset].
  static int _uint16(List<int> b, int offset) =>
      b[offset] | (b[offset + 1] << 8);

  /// Little-endian uint32 at [offset].
  static int _uint32(List<int> b, int offset) =>
      b[offset] |
      (b[offset + 1] << 8) |
      (b[offset + 2] << 16) |
      (b[offset + 3] << 24);

  ArchiveFile? _findEntry(Archive archive, String name) {
    for (final entry in archive.files) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Unpack + verify + cache
  // ------------------------------------------------------------------

  void _unpackAndVerify(
      File zipFile, Map<String, dynamic> manifest, Directory packRoot) {
    if (_isCacheHit(packRoot, manifest)) return;

    // Stage the unpack next to the cache (same filesystem) so the publish
    // rename stays atomic — a Directory.systemTemp staging dir fails with
    // EXDEV whenever /tmp and $HOME are different mounts.
    final staging = _packsRoot.parent..createSync(recursive: true);
    final tmp = staging.createTempSync('.pack-unpack-');
    try {
      final hashes = _manifestHashes(manifest);
      _unzipSafe(zipFile, tmp, hashes);
      packRoot.parent.createSync(recursive: true);
      _deleteWithinPacksRoot(packRoot);
      tmp.renameSync(packRoot.path); // atomic publish
    } on Object {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      rethrow;
    }
  }

  /// Recursive-delete guard: refuses to delete anything that is not inside
  /// the pack cache root, so the re-unpack cleanup can never be aimed at an
  /// existing directory outside it.
  void _deleteWithinPacksRoot(Directory dir) {
    final root = p.normalize(_packsRoot.absolute.path);
    final target = p.normalize(dir.absolute.path);
    if (!p.isWithin(root, target)) {
      throw AgentPackException(
          'Refusing to delete outside the pack cache root: ${dir.path}');
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  bool _isCacheHit(Directory packRoot, Map<String, dynamic> manifest) {
    final cachedManifest = File(p.join(packRoot.path, 'manifest.json'));
    if (!cachedManifest.existsSync()) return false;
    try {
      final cached =
          jsonDecode(cachedManifest.readAsStringSync()) as Map<String, dynamic>;
      if (_stableHash(cached) != _stableHash(manifest)) return false;
      return _cachedFilesIntact(packRoot, manifest);
    } on Object {
      return false;
    }
  }

  /// Re-verifies every manifest-listed cached file (existence + sha256). A
  /// manifest match alone would execute whatever tampered or corrupted bytes
  /// are on disk, so a mismatch falls back to a fresh unpack.
  bool _cachedFilesIntact(Directory packRoot, Map<String, dynamic> manifest) {
    for (final entry in _manifestHashes(manifest).entries) {
      final file = File(p.join(packRoot.path, entry.key));
      if (!file.existsSync()) return false;
      if (sha256.convert(file.readAsBytesSync()).toString() !=
          entry.value.toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  String _stableHash(Map<String, dynamic> manifest) =>
      sha256.convert(utf8.encode(jsonEncode(manifest))).toString();

  Map<String, String> _manifestHashes(Map<String, dynamic> manifest) {
    final hashes = <String, String>{};
    final files = manifest['files'];
    if (files is List) {
      for (final f in files) {
        if (f is Map) hashes[f['path'] as String] = f['sha256'] as String;
      }
    }
    return hashes;
  }

  void _unzipSafe(
      File zipFile, Directory targetDir, Map<String, String> hashes) {
    final targetRoot = p.normalize(targetDir.absolute.path);
    final archive = ZipDecoder().decodeBytes(zipFile.readAsBytesSync());
    final seen = <String>{};
    var totalBytes = 0;
    for (final entry in archive.files) {
      if (entry.isFile) seen.add(entry.name);
      totalBytes =
          _unpackEntry(entry, targetDir, targetRoot, hashes, totalBytes);
    }
    // The manifest is the source of truth in both directions: every listed
    // file must actually be present in the zip.
    final missing = hashes.keys.where((name) => !seen.contains(name)).toList();
    if (missing.isNotEmpty) {
      throw AgentPackException(
          'Manifest files missing from the zip: ${missing.join(', ')}');
    }
  }

  int _unpackEntry(ArchiveFile entry, Directory targetDir, String targetRoot,
      Map<String, String> hashes, int totalBytes) {
    final target = _validateEntryTarget(entry, targetDir, targetRoot);
    if (!entry.isFile) {
      Directory(target.path).createSync(recursive: true);
      return totalBytes;
    }
    target.parent.createSync(recursive: true);
    final data = entry.content as List<int>;
    totalBytes = _verifyEntryData(entry.name, data, hashes, totalBytes);
    target.writeAsBytesSync(data);
    // Java `restoreExecBit` parity: `.sh` entries OR any entry whose unix
    // mode carries the owner-exec bit (0o100), so packed non-.sh
    // executables keep +x.
    if (entry.name.endsWith('.sh') || (entry.mode & 0x40) != 0) {
      _makeExecutable(target);
    }
    return totalBytes;
  }

  /// Validates a zip entry path (AC4) and returns its safe target file.
  File _validateEntryTarget(
      ArchiveFile entry, Directory targetDir, String targetRoot) {
    final name = entry.name;
    if (name.startsWith('/') || name.contains('..') || p.isAbsolute(name)) {
      throw AgentPackException('Zip-slip entry rejected: $name');
    }
    if (entry.isSymbolicLink) {
      throw AgentPackException('Symlink entry rejected: $name');
    }
    final target = File(p.normalize(p.join(targetDir.path, name)));
    if (!p.isWithin(targetRoot, target.path) && target.path != targetRoot) {
      throw AgentPackException('Entry escapes target dir: $name');
    }
    return target;
  }

  /// Verifies entry size caps and the manifest sha256; returns the new total.
  int _verifyEntryData(
      String name, List<int> data, Map<String, String> hashes, int totalBytes) {
    if (data.length > maxFileBytes) {
      throw AgentPackException('Entry too large: $name');
    }
    totalBytes += data.length;
    if (totalBytes > maxTotalBytes) {
      throw const AgentPackException('Pack exceeds total size cap');
    }
    // The manifest inventory is the source of truth: a file entry it does
    // not list is rejected (fail loudly) rather than extracted unverified.
    // `manifest.json` is exempt — it IS the inventory.
    if (name != 'manifest.json' && !hashes.containsKey(name)) {
      throw AgentPackException(
          'Zip entry not listed in manifest inventory: $name');
    }
    final expectedHash = hashes[name];
    if (expectedHash != null &&
        expectedHash.toLowerCase() != sha256.convert(data).toString()) {
      throw AgentPackException('Manifest sha256 mismatch: $name');
    }
    return totalBytes;
  }

  void _makeExecutable(File file) {
    try {
      Process.runSync('chmod', ['0755', file.path]);
    } on Object {
      // best-effort on non-POSIX hosts
    }
  }

  // ------------------------------------------------------------------
  // Path rewriting (path duality, #579 §3)
  // ------------------------------------------------------------------

  /// Rewrites repo-relative path references in [config] to absolute paths
  /// inside [packRoot]. Applies the prefix alias: `agents/js/x.js` and
  /// `js/x.js` both resolve to `<packRoot>/js/x.js`. Only strings that look
  /// like repo-file paths present in the pack are rewritten; URLs, `classpath:`
  /// refs, absolute paths, and literal role strings are left untouched.
  void rewritePathsToPackRoot(Map<String, dynamic> config, Directory packRoot) {
    _rewriteObject(config, packRoot);
  }

  static const _pathKeys = {
    'jsPath',
    'preJSAction',
    'preCliJSAction',
    'postJSAction',
    'timerJSAction',
    'preprocessJSAction',
    'preAction',
    'postAction',
    'descriptionPath',
  };

  void _rewriteObject(Map<String, dynamic> obj, Directory packRoot) {
    for (final key in obj.keys.toList()) {
      final value = obj[key];
      if (value is Map<String, dynamic>) {
        _rewriteObject(value, packRoot);
      } else if (value is List) {
        _rewriteList(value, packRoot);
      } else if (value is String && _pathKeys.contains(key)) {
        final rewritten = _toAbsolutePackPath(value, packRoot);
        if (rewritten != null) obj[key] = rewritten;
      }
    }
  }

  void _rewriteList(List<dynamic> list, Directory packRoot) {
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is String) {
        final rewritten = _toAbsolutePackPath(item, packRoot);
        if (rewritten != null) list[i] = rewritten;
      } else if (item is Map<String, dynamic>) {
        _rewriteObject(item, packRoot);
      } else if (item is List) {
        _rewriteList(item, packRoot);
      }
    }
  }

  /// Maps a config string to an absolute pack-root path when it references a
  /// repo file present in the pack; returns `null` for non-path strings.
  String? _toAbsolutePackPath(String value, Directory packRoot) {
    var ref = value.trim();
    if (_isNonPathRef(ref)) {
      return null;
    }
    while (ref.startsWith('./')) {
      ref = ref.substring(2);
    }
    if (ref.startsWith('agents/')) {
      ref = ref.substring('agents/'.length);
    }
    final candidate = File(p.normalize(p.join(packRoot.path, ref)));
    if (!p.isWithin(packRoot.path, candidate.path) || !candidate.existsSync()) {
      return null;
    }
    return candidate.absolute.path;
  }

  /// True when [ref] is not a repo-relative path (empty, an absolute or
  /// `http(s)`/`classpath:` reference) and must be left untouched.
  static bool _isNonPathRef(String ref) =>
      ref.isEmpty ||
      ref.startsWith('http://') ||
      ref.startsWith('https://') ||
      ref.startsWith('classpath:') ||
      p.isAbsolute(ref);
}
