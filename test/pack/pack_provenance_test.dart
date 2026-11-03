import 'dart:io';

import 'package:dmtools/src/pack/pack_provenance.dart';
import 'package:test/test.dart';

void main() {
  group('PackProvenance', () {
    test('round-trips through the pack directory file', () {
      final dir = Directory.systemTemp.createTempSync('prov_');
      addTearDown(() => dir.deleteSync(recursive: true));
      const record = PackProvenance(
          name: 'sm_github',
          version: '0.1.36',
          sha256: 'abc',
          sourceUrl: 'https://x/sm_github-0.1.36.zip');
      record.write(dir);
      final read = PackProvenance.read(dir);
      expect(read, isNotNull);
      expect(record.matches(read), isTrue);
      expect(record.describe(), contains('sha256=abc'));
    });

    test('same version, different sha or source is not a match', () {
      const a =
          PackProvenance(name: 'n', version: '1', sha256: 'a', sourceUrl: 'u1');
      const bSha =
          PackProvenance(name: 'n', version: '1', sha256: 'b', sourceUrl: 'u1');
      const bUrl =
          PackProvenance(name: 'n', version: '1', sha256: 'a', sourceUrl: 'u2');
      expect(a.matches(bSha), isFalse);
      expect(a.matches(bUrl), isFalse);
      expect(a.matches(null), isFalse);
    });

    test('missing or malformed record reads as null', () {
      final dir = Directory.systemTemp.createTempSync('prov_');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(PackProvenance.read(dir), isNull);
      File('${dir.path}/$packProvenanceFileName').writeAsStringSync('{"x":1}');
      expect(PackProvenance.read(dir), isNull);
      expect(PackProvenance.fromJson('nope'), isNull);
    });
    test('normalizePackReferencePath respects root-level .js when present', () {
      final dir = Directory.systemTemp.createTempSync('prov_norm_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/restoreDescription.js').writeAsStringSync('// root');
      expect(
        normalizePackReferencePath(
          'agents/restoreDescription.js',
          rootPath: dir.path,
        ),
        'restoreDescription.js',
      );
      expect(
        normalizePackReferencePath(
          'assignForSolutionArchitecture.js',
          rootPath: dir.path,
        ),
        'js/assignForSolutionArchitecture.js',
      );
    });

    test('parseGithubReleaseAssetUrl and extractReleaseAssetDownloadUrl', () {
      final parsed = parseGithubReleaseAssetUrl(
        'https://github.com/IstiN/dmtools-agents/releases/download/t1/a-1.zip',
      );
      expect(parsed?.apiBase, 'https://api.github.com');
      expect(parsed?.asset, 'a-1.zip');
      expect(parseGithubReleaseAssetUrl('https://example.com/a.zip'), isNull);
      expect(
        extractReleaseAssetDownloadUrl(
          '[{"tag_name":"t0","assets":[{"name":"a-1.zip","browser_download_url":"https://dl/a-1.zip"}]}]',
          'a-1.zip',
          origin: 'https://github.com',
          owner: 'IstiN',
          repo: 'dmtools-agents',
        ),
        'https://dl/a-1.zip',
      );
      expect(
        extractReleaseAssetDownloadUrl(
          'not-json',
          'a-1.zip',
          origin: 'https://github.com',
          owner: 'IstiN',
          repo: 'dmtools-agents',
        ),
        isNull,
      );
      expect(
        findReleaseAssetInEarlierReleases(
          'https://github.com/IstiN/dmtools-agents/releases/download/t1/a-1.zip',
          'tok',
          httpGet: (u, h) => (
            statusCode: 200,
            body: '[{"tag_name":"t0","assets":[{"name":"a-1.zip"}]}]',
          ),
        ),
        'https://github.com/IstiN/dmtools-agents/releases/download/t0/a-1.zip',
      );
      expect(
        findReleaseAssetInEarlierReleases(
          'https://example.com/a-1.zip',
          null,
          httpGet: (u, h) => (statusCode: 404, body: ''),
        ),
        isNull,
      );
    });
  });
}
