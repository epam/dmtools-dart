import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dmtools/src/compile/agent_pack_compiler.dart'
    hide AgentPackException;
import 'package:dmtools/src/pack/agent_pack_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Tests for [AgentPackResolver] (dm.ai #579): pack detection, zip-slip
/// rejection, manifest verification, entry override, cache hit, and the
/// agents/→pack-root path duality. Java parity: `AgentPackResolverTest`.
void main() {
  setUp(() {
    agentRoot = Directory.systemTemp.createTempSync('agents_');
    packsRoot = Directory.systemTemp.createTempSync('packs_');
    resolver = AgentPackResolver(packsRoot: packsRoot);
  });

  tearDown(() {
    agentRoot.deleteSync(recursive: true);
    packsRoot.deleteSync(recursive: true);
  });

  isPackDetectionTests();
  localResolutionTests();
  entryOverrideTests();
  zipSlipTests();
  manifestTests();
  manifestIdentityTests();
  entryContainmentTests();
  manifestInventoryTests();
  stagingTests();
  remoteDownloadTests();
  pathRewriteTests();
}

late Directory agentRoot;
late Directory packsRoot;
late AgentPackResolver resolver;

/// Writes [content] to [relativePath] under the agent root; returns the file.
File write(String relativePath, String content) {
  final file = File('${agentRoot.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// Builds a real pack zip via [AgentPackCompiler]; returns the zip file.
File buildPack(String agentName, String version) {
  write('js/common/util.js', '// util\n');
  write('js/main.js', "var u = require('./common/util.js');\n");
  write('instructions/common/guide.md', '# Guide\n');
  final entry = write(
      '$agentName.json',
      jsonEncode({
        'name': 'TestAgent',
        'params': {
          'jsPath': 'agents/js/main.js',
          'cliPrompts': ['agents/instructions/common/guide.md'],
        },
      }));
  final outDir = Directory.systemTemp.createTempSync('dist_');
  return AgentPackCompiler(agentRoot.path)
      .compile(entry, version, 'abc123', outDir)
      .zipFile;
}

/// SHA-256 hex digest of [content] (manifest inventory helper).
String sha256Of(String content) =>
    sha256.convert(utf8.encode(content)).toString();

/// Builds a zip with a hostile entry for zip-slip tests.
File buildMalicious(String evilEntry) {
  final manifest = {
    'agent': 'evil',
    'version': '1.0.0',
    'defaultEntry': 'evil.json',
    'files': <dynamic>[],
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile(evilEntry, 3, utf8.encode('bad')));
  final zip =
      File('${Directory.systemTemp.createTempSync('evil_').path}/evil.zip');
  zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
  return zip;
}

/// Pack-input detection.
void isPackDetectionTests() {
  group('AgentPackResolver.isPack', () {
    test('true for a local .zip that exists', () {
      expect(resolver.isPack(buildPack('my_agent', '1.0.0').path), isTrue);
    });

    test('true for an https .zip URL and #entry form', () {
      expect(resolver.isPack('https://example.com/packs/x-1.0.0.zip'), isTrue);
      expect(resolver.isPack('https://example.com/x.zip#custom.json'), isTrue);
    });

    test('false for non-zip, missing file, null, non-zip URL', () {
      expect(resolver.isPack('story.json'), isFalse);
      expect(resolver.isPack('/nonexistent/pack.zip'), isFalse);
      expect(resolver.isPack(null), isFalse);
      expect(resolver.isPack('https://example.com/file.json'), isFalse);
    });
  });
}

/// Local-file resolution + path duality (AC1, AC5).
void localResolutionTests() {
  group('AgentPackResolver local resolution', () {
    test('unpacks a local pack into the cache with prefix stripped', () {
      final pack = resolver.resolve(buildPack('my_agent', '1.0.0').path);

      expect(pack.agent, 'my_agent');
      expect(pack.version, '1.0.0');
      expect(pack.entryFile.existsSync(), isTrue);
      expect(pack.entryFile.path, endsWith('my_agent.json'));
      expect(
          File(p.join(pack.packRoot.path, 'js/main.js')).existsSync(), isTrue);
      expect(File(p.join(pack.packRoot.path, 'js/common/util.js')).existsSync(),
          isTrue);
      expect(File(p.join(pack.packRoot.path, 'agents/js/main.js')).existsSync(),
          isFalse);
    });

    test('second resolve of the same version is a cache hit', () {
      final zip = buildPack('my_agent', '1.0.0');
      final first = resolver.resolve(zip.path);
      final marker = File(p.join(first.packRoot.path, 'MARKER.txt'))
        ..writeAsStringSync('cached');
      final second = resolver.resolve(zip.path);
      expect(marker.existsSync(), isTrue, reason: 'cache hit keeps the dir');
      expect(second.packRoot.path, first.packRoot.path);
    });
  });
}

/// The `#entry.json` override (AC7).
void entryOverrideTests() {
  group('AgentPackResolver entry override', () {
    test('#entry override resolves an in-pack config', () {
      // custom.json is the parent of my_agent.json, so it lands in the closure.
      write('js/main.js', '// main\n');
      write(
          'custom.json',
          jsonEncode({
            'name': 'X',
            'params': {'jsPath': 'agents/js/main.js'}
          }));
      final entry = write(
          'my_agent.json',
          jsonEncode({
            'name': 'X',
            'parent': {'path': 'agents/custom.json'},
            'params': <String, dynamic>{},
          }));
      final outDir = Directory.systemTemp.createTempSync('dist_');
      final zip = AgentPackCompiler(agentRoot.path)
          .compile(entry, '1.0.0', 'abc', outDir)
          .zipFile;

      final pack = resolver.resolve('${zip.path}#custom.json');
      expect(pack.entryFile.path, endsWith('custom.json'));
    });

    test('missing #entry override fails listing the default entry', () {
      final zip = buildPack('my_agent', '1.0.0');
      expect(
        () => resolver.resolve('${zip.path}#missing.json'),
        throwsA(isA<AgentPackException>()
            .having((e) => e.message, 'message', contains('missing.json'))
            .having((e) => e.message, 'message', contains('defaultEntry'))),
      );
    });
  });
}

/// Zip-slip protection (AC4).
void zipSlipTests() {
  group('AgentPackResolver zip-slip', () {
    test('rejects ../ escape entries before unpacking', () {
      final zip = buildMalicious('../evil.sh');
      expect(
          () => resolver.resolve(zip.path), throwsA(isA<AgentPackException>()));
      expect(Directory(p.join(packsRoot.path, 'evil-1.0.0')).existsSync(),
          isFalse);
    });

    test('rejects absolute-path entries before unpacking', () {
      final zip = buildMalicious('/abs/evil.sh');
      expect(
          () => resolver.resolve(zip.path), throwsA(isA<AgentPackException>()));
      expect(Directory(p.join(packsRoot.path, 'evil-1.0.0')).existsSync(),
          isFalse);
    });
  });
}

/// Manifest integrity (E3).
void manifestTests() {
  group('AgentPackResolver manifest', () {
    test('fails when the pack has no manifest.json', () {
      final archive = Archive()
        ..addFile(ArchiveFile('x.txt', 2, utf8.encode('hi')));
      final zip =
          File('${Directory.systemTemp.createTempSync('nomani_').path}/n.zip')
            ..writeAsBytesSync(ZipEncoder().encode(archive)!);
      expect(
          () => resolver.resolve(zip.path),
          throwsA(isA<AgentPackException>()
              .having((e) => e.message, 'message', contains('manifest.json'))));
    });
  });
}

/// Builds a zip from [manifest] plus [extraFiles] (name → bytes).
File buildZipWithManifest(
    Map<String, dynamic> manifest, Map<String, List<int>> extraFiles) {
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  for (final entry in extraFiles.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final zip =
      File('${Directory.systemTemp.createTempSync('zip_').path}/pack.zip');
  zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
  return zip;
}

/// Manifest `agent`/`version` validation (PR #249 review: cache-path
/// traversal + recursive-delete hazard).
void manifestIdentityTests() {
  group('AgentPackResolver manifest identity', () {
    Map<String, dynamic> manifest(String agent, String version) => {
          'agent': agent,
          'version': version,
          'defaultEntry': 'a.json',
          'files': [
            {'path': 'a.json', 'sha256': sha256Of('{}')},
          ],
        };

    test('rejects an agent with a path separator', () {
      final zip = buildZipWithManifest(
          manifest('../evil', '1.0.0'), {'a.json': utf8.encode('{}')});
      expect(
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>().having(
            (e) => e.message, 'message', contains('Unsafe manifest agent'))),
      );
    });

    test('rejects a dots-only version (..)', () {
      final zip = buildZipWithManifest(
          manifest('ok_agent', '..'), {'a.json': utf8.encode('{}')});
      expect(
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>().having(
            (e) => e.message, 'message', contains('Unsafe manifest version'))),
      );
    });

    test('rejects an empty agent and illegal characters', () {
      for (final bad in ['', 'a/b', 'a\\b', 'a b', r'a$b']) {
        final zip = buildZipWithManifest(
            manifest(bad, '1.0.0'), {'a.json': utf8.encode('{}')});
        expect(() => resolver.resolve(zip.path),
            throwsA(isA<AgentPackException>()),
            reason: 'agent "$bad" must be rejected');
      }
    });
  });
}

/// Containment of the entry config (`#entry` override / `defaultEntry`)
/// against the pack root (PR #249 review).
void entryContainmentTests() {
  group('AgentPackResolver entry containment', () {
    test('rejects a defaultEntry that escapes the pack root', () {
      final zip = buildZipWithManifest({
        'agent': 'ok_agent',
        'version': '1.0.0',
        'defaultEntry': '../escape.json',
        'files': <dynamic>[],
      }, {});
      expect(
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>().having(
            (e) => e.message, 'message', contains('escapes the pack root'))),
      );
    });

    test('rejects a #entry override that escapes the pack root', () {
      final zip = buildPack('my_agent', '1.0.0');
      expect(
        () => resolver.resolve('${zip.path}#../escape.json'),
        throwsA(isA<AgentPackException>().having(
            (e) => e.message, 'message', contains('escapes the pack root'))),
      );
    });
  });
}

/// The manifest inventory as source of truth, both directions (PR #249
/// review: unlisted zip entries were extracted unverified).
void manifestInventoryTests() {
  group('AgentPackResolver manifest inventory', () {
    test('rejects a zip entry not listed in the manifest', () {
      final zip = buildZipWithManifest({
        'agent': 'ok_agent',
        'version': '1.0.0',
        'defaultEntry': 'a.json',
        'files': <dynamic>[],
      }, {
        'a.json': utf8.encode('{}'),
        'sneaky.sh': utf8.encode('echo hi'),
      });
      expect(
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>().having((e) => e.message, 'message',
            contains('not listed in manifest inventory'))),
      );
    });

    test('rejects a manifest-listed file missing from the zip', () {
      final zip = buildZipWithManifest({
        'agent': 'ok_agent',
        'version': '1.0.0',
        'defaultEntry': 'a.json',
        'files': [
          {'path': 'a.json', 'sha256': sha256Of('{}')},
          {'path': 'ghost.js', 'sha256': sha256Of('x')},
        ],
      }, {
        'a.json': utf8.encode('{}'),
      });
      expect(
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>().having(
            (e) => e.message, 'message', contains('missing from the zip'))),
      );
    });
  });
}

/// Same-filesystem staging for the atomic publish (PR #249 review: EXDEV).
void stagingTests() {
  group('AgentPackResolver unpack staging', () {
    test('stages next to the packs root and leaves no temp dir behind', () {
      final parent = Directory.systemTemp.createTempSync('staging_parent_');
      try {
        final local = AgentPackResolver(
            packsRoot: Directory(p.join(parent.path, 'packs')));
        final pack = local.resolve(buildPack('my_agent', '3.0.0').path);
        expect(pack.packRoot.path, startsWith(parent.path));
        expect(
            Directory(p.join(parent.path, 'packs', 'my_agent-3.0.0'))
                .existsSync(),
            isTrue);
        final leftovers = parent
            .listSync()
            .where((e) => p.basename(e.path).startsWith('.pack-unpack-'));
        expect(leftovers, isEmpty, reason: 'staging dir renamed away');
      } finally {
        parent.deleteSync(recursive: true);
      }
    });

    test('cleans up the staging dir when the unpack fails', () {
      final parent = Directory.systemTemp.createTempSync('staging_parent_');
      try {
        final local = AgentPackResolver(
            packsRoot: Directory(p.join(parent.path, 'packs')));
        expect(() => local.resolve(buildMalicious('../evil.sh').path),
            throwsA(isA<AgentPackException>()));
        final leftovers = parent
            .listSync(recursive: true)
            .where((e) => p.basename(e.path).startsWith('.pack-unpack-'));
        expect(leftovers, isEmpty, reason: 'failed unpack cleans staging');
      } finally {
        parent.deleteSync(recursive: true);
      }
    });
  });
}

/// Loopback pack server entry point. Runs in its own isolate because
/// [SyncHttpClient] blocks the caller isolate (curl subprocess) — an
/// in-isolate server could never answer. Serves 404 for `.sha256`, the pack
/// bytes otherwise, and reports the zip request's Authorization header.
void _packServerEntry(List<Object?> init) {
  final readyPort = init[0] as SendPort;
  final authPort = init[1] as SendPort;
  final zipBytes = init[2] as List<int>;
  HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    readyPort.send(server.port);
    server.listen((request) {
      if (request.uri.path.endsWith('.sha256')) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        authPort.send(request.headers.value('authorization'));
        request.response.add(zipBytes);
      }
      request.response.close();
    });
  });
}

/// Remote download behavior (PR #249 review: missing `.sha256` handling,
/// token scoping). Served by a loopback [HttpServer] in a separate isolate.
void remoteDownloadTests() {
  group('AgentPackResolver remote download', () {
    test('missing .sha256 sidecar skips verification and still resolves',
        () async {
      final zipBytes = buildPack('remote_agent', '2.0.0').readAsBytesSync();
      final readyInbox = ReceivePort();
      final authInbox = ReceivePort();
      final server = await Isolate.spawn(_packServerEntry,
          [readyInbox.sendPort, authInbox.sendPort, zipBytes]);
      try {
        final port = await readyInbox.first as int;
        final pack = resolver.resolve('http://127.0.0.1:$port/pack.zip',
            githubToken: 'secret-token');
        expect(pack.agent, 'remote_agent');
        expect(pack.entryFile.existsSync(), isTrue);
        final auth = await authInbox.first;
        expect(auth, isNull,
            reason: 'the bearer token is only sent to github.com');
      } finally {
        readyInbox.close();
        authInbox.close();
        server.kill();
      }
    });
  });
}

/// Path rewriting (path duality, AC5).
void pathRewriteTests() {
  group('AgentPackResolver.rewritePathsToPackRoot', () {
    test('rewrites agents/ and plain paths to absolute pack paths', () {
      final pack = resolver.resolve(buildPack('my_agent', '1.0.0').path);
      final config = <String, dynamic>{
        'params': {
          'jsPath': 'agents/js/main.js',
          'cliPrompts': [
            'agents/instructions/common/guide.md',
            'Senior Developer Engineer', // literal role — not a path
          ],
        },
      };
      resolver.rewritePathsToPackRoot(config, pack.packRoot);
      final params = config['params'] as Map<String, dynamic>;
      expect(params['jsPath'],
          File(p.join(pack.packRoot.path, 'js/main.js')).absolute.path);
      final prompts = params['cliPrompts'] as List;
      expect(
          prompts[0],
          File(p.join(pack.packRoot.path, 'instructions/common/guide.md'))
              .absolute
              .path);
      expect(prompts[1], 'Senior Developer Engineer'); // untouched literal
    });

    test('leaves URLs and classpath refs untouched', () {
      final pack = resolver.resolve(buildPack('my_agent', '1.0.0').path);
      final config = <String, dynamic>{
        'params': {
          'postJSAction': 'https://github.com/u/r/blob/main/x.js',
          'timerJSAction': 'classpath:js/timer.js',
        },
      };
      resolver.rewritePathsToPackRoot(config, pack.packRoot);
      final params = config['params'] as Map<String, dynamic>;
      expect(params['postJSAction'], 'https://github.com/u/r/blob/main/x.js');
      expect(params['timerJSAction'], 'classpath:js/timer.js');
    });
  });
}
