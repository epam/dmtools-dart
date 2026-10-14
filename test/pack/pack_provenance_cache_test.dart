import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dmtools/src/pack/agent_pack_resolver.dart';
import 'package:dmtools/src/pack/pack_provenance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'pack_fixtures.dart';

void main() {
  late AgentPackResolver resolver;
  late Directory packsRoot;

  setUp(() {
    agentRoot = Directory.systemTemp.createTempSync('agents_');
    packsRoot = Directory.systemTemp.createTempSync('packs_');
    resolver = AgentPackResolver(packsRoot: packsRoot);
  });

  tearDown(() {
    agentRoot.deleteSync(recursive: true);
    packsRoot.deleteSync(recursive: true);
  });

  provenanceCacheTests(() => resolver);
}

/// gh-375: the cache key includes the zip sha256 and the source URL, so a
/// different source (e.g. a re-pinned registry base) or a stale recorded
/// sha re-unpacks instead of reusing the cached directory.
void provenanceCacheTests(AgentPackResolver Function() r) {
  AgentPackResolver resolver() => r();
  group('AgentPackResolver provenance cache key', () {
    test('a different source path invalidates the cache', () {
      final zip = buildPack('my_agent', '1.0.0');
      final first = resolver().resolve(zip.path);
      File(p.join(first.packRoot.path, 'MARKER.txt')).writeAsStringSync('x');
      final copy = File('${zip.parent.path}/copy-my_agent-1.0.0.zip')
        ..writeAsBytesSync(zip.readAsBytesSync());
      final second = resolver().resolve(copy.path);
      expect(File(p.join(second.packRoot.path, 'MARKER.txt')).existsSync(),
          isFalse);
      expect(PackProvenance.read(second.packRoot)?.sourceUrl, copy.path);
    });

    test('a recorded sha256 that no longer matches invalidates the cache', () {
      final zip = buildPack('my_agent', '1.0.0');
      final first = resolver().resolve(zip.path);
      File(p.join(first.packRoot.path, 'MARKER.txt')).writeAsStringSync('x');
      File(p.join(first.packRoot.path, packProvenanceFileName))
          .writeAsStringSync(
              '{"name":"my_agent","version":"1.0.0","sha256":"0000",'
              '"sourceUrl":"${zip.path}"}');
      final second = resolver().resolve(zip.path);
      expect(File(p.join(second.packRoot.path, 'MARKER.txt')).existsSync(),
          isFalse);
      expect(PackProvenance.read(second.packRoot)?.sha256,
          sha256.convert(zip.readAsBytesSync()).toString());
    });

    test('unpacked pack records name, version, sha256 and source', () {
      final zip = buildPack('my_agent', '1.0.0');
      final pack = resolver().resolve(zip.path);
      final prov = PackProvenance.read(pack.packRoot);
      expect(prov?.name, 'my_agent');
      expect(prov?.version, '1.0.0');
      expect(prov?.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(prov?.sourceUrl, zip.path);
    });
  });
}
