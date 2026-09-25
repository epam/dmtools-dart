import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
