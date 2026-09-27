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

import 'pack_fixtures.dart';

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
  remoteSha256VerificationTests();
  registryRefTests();
  cacheReverifyTests();
  execBitTests();
  manifestCastTests();
  encryptionScanTests();
  pathRewriteTests();
  pathRewriteNestedTests();
  pathRewriteUntouchedTests();
}

late Directory packsRoot;
late AgentPackResolver resolver;

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
        File(p.join(pack.packRoot.path, 'js/main.js')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(pack.packRoot.path, 'js/common/util.js')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(pack.packRoot.path, 'agents/js/main.js')).existsSync(),
        isFalse,
      );
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
          'params': {'jsPath': 'agents/js/main.js'},
        }),
      );
      final entry = write(
        'my_agent.json',
        jsonEncode({
          'name': 'X',
          'parent': {'path': 'agents/custom.json'},
          'params': <String, dynamic>{},
        }),
      );
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
        throwsA(
          isA<AgentPackException>()
              .having((e) => e.message, 'message', contains('missing.json'))
              .having((e) => e.message, 'message', contains('defaultEntry')),
        ),
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
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>()),
      );
      expect(
        Directory(p.join(packsRoot.path, 'evil-1.0.0')).existsSync(),
        isFalse,
      );
    });

    test('rejects absolute-path entries before unpacking', () {
      final zip = buildMalicious('/abs/evil.sh');
      expect(
        () => resolver.resolve(zip.path),
        throwsA(isA<AgentPackException>()),
      );
      expect(
        Directory(p.join(packsRoot.path, 'evil-1.0.0')).existsSync(),
        isFalse,
      );
    });
  });
}

/// Manifest integrity (E3).
void manifestTests() {
  group('AgentPackResolver manifest', () {
    test('fails when the pack has no manifest.json', () {
      final archive = Archive()
        ..addFile(ArchiveFile('x.txt', 2, utf8.encode('hi')));
      final zip = File(
        '${Directory.systemTemp.createTempSync('nomani_').path}/n.zip',
      )..writeAsBytesSync(ZipEncoder().encode(archive)!);
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('manifest.json'),
          ),
        ),
      );
    });
  });
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
      final zip = buildZipWithManifest(manifest('../evil', '1.0.0'), {
        'a.json': utf8.encode('{}'),
      });
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('Unsafe manifest agent'),
          ),
        ),
      );
    });

    test('rejects a dots-only version (..)', () {
      final zip = buildZipWithManifest(manifest('ok_agent', '..'), {
        'a.json': utf8.encode('{}'),
      });
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('Unsafe manifest version'),
          ),
        ),
      );
    });

    test('rejects an empty agent and illegal characters', () {
      for (final bad in ['', 'a/b', 'a\\b', 'a b', r'a$b']) {
        final zip = buildZipWithManifest(manifest(bad, '1.0.0'), {
          'a.json': utf8.encode('{}'),
        });
        expect(
          () => resolver.resolve(zip.path),
          throwsA(isA<AgentPackException>()),
          reason: 'agent "$bad" must be rejected',
        );
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
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('escapes the pack root'),
          ),
        ),
      );
    });

    test('rejects a #entry override that escapes the pack root', () {
      final zip = buildPack('my_agent', '1.0.0');
      expect(
        () => resolver.resolve('${zip.path}#../escape.json'),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('escapes the pack root'),
          ),
        ),
      );
    });
  });
}

/// The manifest inventory as source of truth, both directions (PR #249
/// review: unlisted zip entries were extracted unverified).
void manifestInventoryTests() {
  group('AgentPackResolver manifest inventory', () {
    test('rejects a zip entry not listed in the manifest', () {
      final zip = buildZipWithManifest(
        {
          'agent': 'ok_agent',
          'version': '1.0.0',
          'defaultEntry': 'a.json',
          'files': <dynamic>[],
        },
        {'a.json': utf8.encode('{}'), 'sneaky.sh': utf8.encode('echo hi')},
      );
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('not listed in manifest inventory'),
          ),
        ),
      );
    });

    test('rejects a manifest-listed file missing from the zip', () {
      final zip = buildZipWithManifest(
        {
          'agent': 'ok_agent',
          'version': '1.0.0',
          'defaultEntry': 'a.json',
          'files': [
            {'path': 'a.json', 'sha256': sha256Of('{}')},
            {'path': 'ghost.js', 'sha256': sha256Of('x')},
          ],
        },
        {'a.json': utf8.encode('{}')},
      );
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('missing from the zip'),
          ),
        ),
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
          packsRoot: Directory(p.join(parent.path, 'packs')),
        );
        final pack = local.resolve(buildPack('my_agent', '3.0.0').path);
        expect(pack.packRoot.path, startsWith(parent.path));
        expect(
          Directory(p.join(parent.path, 'packs', 'my_agent-3.0.0'))
              .existsSync(),
          isTrue,
        );
        final leftovers = parent.listSync().where(
          (e) => p.basename(e.path).startsWith('.pack-unpack-'),
        );
        expect(leftovers, isEmpty, reason: 'staging dir renamed away');
      } finally {
        parent.deleteSync(recursive: true);
      }
    });

    test('cleans up the staging dir when the unpack fails', () {
      final parent = Directory.systemTemp.createTempSync('staging_parent_');
      try {
        final local = AgentPackResolver(
          packsRoot: Directory(p.join(parent.path, 'packs')),
        );
        expect(
          () => local.resolve(buildMalicious('../evil.sh').path),
          throwsA(isA<AgentPackException>()),
        );
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

/// Remote download behavior (PR #249 review: `.sha256`-less downloads and
/// token scoping). Served by a loopback [HttpServer] in a separate isolate.
void remoteDownloadTests() {
  group('AgentPackResolver remote download', () {
    test(
      'missing .sha256 sidecar skips verification and still resolves',
      () async {
        final zipBytes = buildPack('remote_agent', '2.0.0').readAsBytesSync();
        final server = await startPackServer(zipBytes);
        try {
          final pack = resolver.resolve(
            'http://127.0.0.1:${server.port}/pack.zip',
            githubToken: 'secret-token',
          );
          expect(pack.agent, 'remote_agent');
          expect(pack.entryFile.existsSync(), isTrue);
          final auth = await server.authInbox.first;
          expect(
            auth,
            isNull,
            reason: 'the bearer token is only sent to github.com',
          );
        } finally {
          server.authInbox.close();
          server.isolate.kill();
        }
      },
    );
  });
}

/// `.sha256` sidecar verification for URL packs (match/mismatch).
void remoteSha256VerificationTests() {
  group('AgentPackResolver remote .sha256 verification', () {
    test('matching .sha256 sidecar verifies and resolves', () async {
      final zipBytes = buildPack('remote_agent', '2.1.0').readAsBytesSync();
      final sidecar = '${sha256.convert(zipBytes)}  pack.zip';
      final server = await startPackServer(zipBytes, sha256Body: sidecar);
      try {
        final pack = resolver.resolve(
          'http://127.0.0.1:${server.port}/pack.zip',
        );
        expect(pack.agent, 'remote_agent');
        expect(pack.version, '2.1.0');
      } finally {
        server.authInbox.close();
        server.isolate.kill();
      }
    });

    test('mismatching .sha256 sidecar fails with a checksum error', () async {
      final zipBytes = buildPack('remote_agent', '2.2.0').readAsBytesSync();
      final server = await startPackServer(
        zipBytes,
        sha256Body: '${'0' * 64}  pack.zip',
      );
      try {
        expect(
          () => resolver.resolve('http://127.0.0.1:${server.port}/pack.zip'),
          throwsA(
            isA<AgentPackException>().having(
              (e) => e.message,
              'message',
              contains('SHA-256 mismatch'),
            ),
          ),
        );
      } finally {
        server.authInbox.close();
        server.isolate.kill();
      }
    });
  });
}

/// Cache-hit re-verification (PR #249 review suggestion: a manifest match
/// alone must not execute tampered bytes).
void cacheReverifyTests() {
  group('AgentPackResolver cache re-verification', () {
    test('a tampered cached file triggers a fresh unpack', () {
      final zip = buildPack('my_agent', '1.0.0');
      final first = resolver.resolve(zip.path);
      final mainJs = File(p.join(first.packRoot.path, 'js/main.js'))
        ..writeAsStringSync('// tampered\n');
      final second = resolver.resolve(zip.path);
      expect(
        mainJs.readAsStringSync(),
        contains("require('./common/util.js')"),
        reason: 'tampered cache is re-unpacked',
      );
      expect(second.packRoot.path, first.packRoot.path);
    });

    test('a deleted cached file triggers a fresh unpack', () {
      final zip = buildPack('my_agent', '1.0.0');
      final first = resolver.resolve(zip.path);
      File(p.join(first.packRoot.path, 'js/common/util.js')).deleteSync();
      resolver.resolve(zip.path);
      expect(
        File(p.join(first.packRoot.path, 'js/common/util.js')).existsSync(),
        isTrue,
      );
    });
  });
}

/// Exec-bit restore parity with Java `restoreExecBit` (PR #249 review
/// suggestion: not only `.sh`).
void execBitTests() {
  group('AgentPackResolver exec bit', () {
    test('restores +x for a non-.sh entry with an owner-exec mode', () {
      final tool = utf8.encode('#!/bin/sh\necho hi\n');
      final zip = buildZipWithManifest(
        {
          'agent': 'tool_agent',
          'version': '1.0.0',
          'defaultEntry': 'a.json',
          'files': [
            {'path': 'a.json', 'sha256': sha256Of('{}')},
            {'path': 'bin/tool', 'sha256': sha256.convert(tool).toString()},
          ],
        },
        {'a.json': utf8.encode('{}'), 'bin/tool': tool},
        modes: {
          'bin/tool': 0x1ED, // 0755
        },
      );
      final pack = resolver.resolve(zip.path);
      final mode = FileStat.statSync(p.join(pack.packRoot.path, 'bin/tool'))
          .mode;
      expect(mode & 0x40, isNonZero, reason: 'owner-exec bit restored');
    });

    test('does not chmod plain 0644 entries', () {
      final zip = buildZipWithManifest(
        {
          'agent': 'tool_agent',
          'version': '1.0.0',
          'defaultEntry': 'a.json',
          'files': [
            {'path': 'a.json', 'sha256': sha256Of('{}')},
            {'path': 'bin/tool', 'sha256': sha256Of('tool')},
          ],
        },
        {'a.json': utf8.encode('{}'), 'bin/tool': utf8.encode('tool')},
      );
      final pack = resolver.resolve(zip.path);
      final mode = FileStat.statSync(p.join(pack.packRoot.path, 'bin/tool'))
          .mode;
      expect(mode & 0x40, 0, reason: '0644 entries stay non-executable');
    });
  });
}

/// Typed manifest reads (PR #249 review suggestion: no bare TypeError).
void manifestCastTests() {
  group('AgentPackResolver manifest casts', () {
    test('a non-string agent fails with a clean AgentPackException', () {
      final zip = buildZipWithManifest({
        'agent': 123,
        'version': '1.0.0',
        'defaultEntry': 'a.json',
        'files': <dynamic>[],
      }, {});
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('must be a string'),
          ),
        ),
      );
    });

    test('a non-string defaultEntry fails with a clean AgentPackException', () {
      final zip = buildZipWithManifest({
        'agent': 'ok_agent',
        'version': '1.0.0',
        'defaultEntry': 42,
        'files': <dynamic>[],
      }, {});
      expect(
        () => resolver.resolve(zip.path),
        throwsA(
          isA<AgentPackException>().having(
            (e) => e.message,
            'message',
            contains('defaultEntry'),
          ),
        ),
      );
    });
  });
}

/// Encrypted-zip detection accuracy (PR #249 review suggestion: raw
/// signature scan false-positives on stored payloads).
void encryptionScanTests() {
  group('AgentPackResolver encryption scan', () {
    test(
      r'a stored payload containing PK\x01\x02 bytes is not "encrypted"',
      () {
        final payload = [0x50, 0x4B, 0x01, 0x02, ...utf8.encode('data')];
        final zip = buildZipWithManifest(
          {
            'agent': 'data_agent',
            'version': '1.0.0',
            'defaultEntry': 'a.json',
            'files': [
              {'path': 'a.json', 'sha256': sha256Of('{}')},
              {
                'path': 'data.bin',
                'sha256': sha256.convert(payload).toString(),
              },
            ],
          },
          {'a.json': utf8.encode('{}'), 'data.bin': payload},
        );
        final pack = resolver.resolve(zip.path);
        expect(pack.agent, 'data_agent');
        expect(
          File(p.join(pack.packRoot.path, 'data.bin')).readAsBytesSync(),
          payload,
        );
      },
    );
  });
}

/// Path rewriting (path duality, AC5): repo-relative refs become
/// absolute pack-root paths.
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
      expect(
        params['jsPath'],
        File(p.join(pack.packRoot.path, 'js/main.js')).absolute.path,
      );
      final prompts = params['cliPrompts'] as List;
      expect(
        prompts[0],
        File(p.join(pack.packRoot.path, 'instructions/common/guide.md'))
            .absolute
            .path,
      );
      expect(prompts[1], 'Senior Developer Engineer'); // untouched literal
    });
  });
}

/// Path rewriting of `./`-prefixed refs and nested list/map shapes.
void pathRewriteNestedTests() {
  group('AgentPackResolver.rewritePathsToPackRoot nested shapes', () {
    test('normalizes ./-prefixed and nested list shapes to the pack root', () {
      final pack = resolver.resolve(buildPack('my_agent', '1.0.0').path);
      final config = <String, dynamic>{
        'params': {
          'jsPath': './js/main.js',
          'preJSAction': './agents/js/common/util.js',
          // List values recurse: a nested map and a nested list inside a
          // path-key list must be rewritten too (string items stay direct).
          'cliPrompts': [
            'agents/instructions/common/guide.md',
            {'descriptionPath': './instructions/common/guide.md'},
            ['./js/main.js'],
          ],
        },
      };
      resolver.rewritePathsToPackRoot(config, pack.packRoot);
      final params = config['params'] as Map<String, dynamic>;
      expect(
        params['jsPath'],
        File(p.join(pack.packRoot.path, 'js/main.js')).absolute.path,
      );
      expect(
        params['preJSAction'],
        File(p.join(pack.packRoot.path, 'js/common/util.js')).absolute.path,
      );
      final prompts = params['cliPrompts'] as List;
      expect(
        prompts[0],
        File(p.join(pack.packRoot.path, 'instructions/common/guide.md'))
            .absolute
            .path,
      );
      final nestedMap = prompts[1] as Map<String, dynamic>;
      expect(
        nestedMap['descriptionPath'],
        File(p.join(pack.packRoot.path, 'instructions/common/guide.md'))
            .absolute
            .path,
      );
      final nestedList = prompts[2] as List;
      expect(
        nestedList[0],
        File(p.join(pack.packRoot.path, 'js/main.js')).absolute.path,
      );
    });
  });
}

/// Refs that must never be rewritten: URLs, classpath refs, literal
/// strings, absolute paths, and anything escaping the pack root
/// (traversal guard).
void pathRewriteUntouchedTests() {
  group('AgentPackResolver.rewritePathsToPackRoot untouched refs', () {
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

    test(
      'leaves empty, plain-http, absolute, and pack-escaping refs untouched',
      () {
        final pack = resolver.resolve(buildPack('my_agent', '1.0.0').path);
        final outside = File(p.join(Directory.systemTemp.path, 'outside.js'))
            .absolute
            .path;
        final config = <String, dynamic>{
          'params': {
            'jsPath': '', // empty ref
            'postJSAction': 'http://example.com/x.js', // plain http URL
            'preJSAction': outside, // absolute path outside the pack
            // ../ escape: normalizes outside the pack root — traversal guard.
            'timerJSAction': '../outside.js',
          },
        };
        resolver.rewritePathsToPackRoot(config, pack.packRoot);
        final params = config['params'] as Map<String, dynamic>;
        expect(params['jsPath'], '');
        expect(params['postJSAction'], 'http://example.com/x.js');
        expect(params['preJSAction'], outside);
        expect(params['timerJSAction'], '../outside.js');
      },
    );
  });
}

/// Registry refs: `<agent>@<version|latest>` resolved from a flat registry
/// (env `DMTOOLS_PACK_REGISTRY`) serving `catalog.json` plus
/// `<agent>-<version>.zip` (+ `.sha256`).
void registryRefTests() {
  group('AgentPackResolver registry refs', () {
    test('isRegistryRef requires a configured registry and the @ form', () {
      final noRegistry = AgentPackResolver(
        packsRoot: packsRoot,
        registryBaseUrl: '',
      );
      expect(
        noRegistry.isRegistryRef('my_agent@1.0.0'),
        isFalse,
        reason: 'no registry configured',
      );
      expect(noRegistry.isPack('my_agent@1.0.0'), isFalse);

      final withRegistry = AgentPackResolver(
        packsRoot: packsRoot,
        registryBaseUrl: 'http://localhost:1',
      );
      expect(withRegistry.isRegistryRef('my_agent@1.0.0'), isTrue);
      expect(withRegistry.isRegistryRef('my_agent@latest'), isTrue);
      expect(withRegistry.isPack('my_agent@latest'), isTrue);
      // Never a pack: bare names, files, paths.
      expect(withRegistry.isRegistryRef('my_agent'), isFalse);
      expect(withRegistry.isRegistryRef('my_agent.json'), isFalse);
      expect(withRegistry.isRegistryRef('./my_agent@1.0.0'), isFalse);
      expect(withRegistry.isRegistryRef('agents/my_agent@1.0.0'), isFalse);
      expect(withRegistry.isRegistryRef('@latest'), isFalse);
      expect(withRegistry.isRegistryRef('my_agent@'), isFalse);
    });

    test('explicit @version downloads <agent>-<version>.zip', () async {
      final zipBytes = buildPack('my_agent', '1.2.0').readAsBytesSync();
      final server = await startRegistryServer({
        '/my_agent-1.2.0.zip': zipBytes,
        '/my_agent-1.2.0.zip.sha256': utf8.encode(
          '${sha256.convert(zipBytes)}  my_agent-1.2.0.zip',
        ),
        '/catalog.json': utf8.encode(jsonEncode({'my_agent': '1.2.0'})),
      });
      try {
        final r = AgentPackResolver(
          packsRoot: packsRoot,
          registryBaseUrl: 'http://127.0.0.1:${server.port}',
        );
        final pack = r.resolve('my_agent@1.2.0');
        expect(pack.agent, 'my_agent');
        expect(pack.version, '1.2.0');
        expect(
          File(p.join(pack.packRoot.path, 'js/main.js')).existsSync(),
          isTrue,
        );
      } finally {
        server.isolate.kill();
      }
    });

    test('@latest resolves the version from catalog.json', () async {
      final zipBytes = buildPack('latest_agent', '2.0.0').readAsBytesSync();
      final server = await startRegistryServer({
        '/latest_agent-2.0.0.zip': zipBytes,
        '/latest_agent-2.0.0.zip.sha256': utf8.encode(
          '${sha256.convert(zipBytes)}',
        ),
        '/catalog.json': utf8.encode(
          jsonEncode({
            'agents': {'latest_agent': '2.0.0'}, // nested catalog shape
          }),
        ),
      });
      try {
        final r = AgentPackResolver(
          packsRoot: packsRoot,
          registryBaseUrl: 'http://127.0.0.1:${server.port}',
        );
        final pack = r.resolve('latest_agent@latest');
        expect(pack.agent, 'latest_agent');
        expect(pack.version, '2.0.0');
      } finally {
        server.isolate.kill();
      }
    });

    test('@latest with an unknown agent fails naming the agent', () async {
      final server = await startRegistryServer({
        '/catalog.json': utf8.encode(jsonEncode({'other_agent': '1.0.0'})),
      });
      try {
        final r = AgentPackResolver(
          packsRoot: packsRoot,
          registryBaseUrl: 'http://127.0.0.1:${server.port}',
        );
        expect(
          () => r.resolve('unknown_agent@latest'),
          throwsA(
            isA<AgentPackException>().having(
              (e) => e.message,
              'message',
              contains('unknown_agent'),
            ),
          ),
        );
      } finally {
        server.isolate.kill();
      }
    });

    test('@version with a mismatching .sha256 fails the checksum', () async {
      final zipBytes = buildPack('hash_agent', '1.0.0').readAsBytesSync();
      final server = await startRegistryServer({
        '/hash_agent-1.0.0.zip': zipBytes,
        '/hash_agent-1.0.0.zip.sha256': utf8.encode('${'0' * 64}  x.zip'),
      });
      try {
        final r = AgentPackResolver(
          packsRoot: packsRoot,
          registryBaseUrl: 'http://127.0.0.1:${server.port}',
        );
        expect(
          () => r.resolve('hash_agent@1.0.0'),
          throwsA(
            isA<AgentPackException>().having(
              (e) => e.message,
              'message',
              contains('SHA-256 mismatch'),
            ),
          ),
        );
      } finally {
        server.isolate.kill();
      }
    });
  });
}

/// Isolate entry: serves a path→bytes map, 404 for anything else.
void _registryServerEntry(List<Object?> init) {
  final readyPort = init[0] as SendPort;
  final files = init[1] as Map<String, List<int>>;
  HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    readyPort.send(server.port);
    server.listen((request) {
      final body = files[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(body);
      }
      request.response.close();
    });
  });
}

/// Starts the loopback registry server in a separate isolate.
Future<({int port, Isolate isolate})> startRegistryServer(
  Map<String, List<int>> files,
) async {
  final readyInbox = ReceivePort();
  final isolate = await Isolate.spawn(_registryServerEntry, [
    readyInbox.sendPort,
    files,
  ]);
  final port = await readyInbox.first as int;
  readyInbox.close();
  return (port: port, isolate: isolate);
}
