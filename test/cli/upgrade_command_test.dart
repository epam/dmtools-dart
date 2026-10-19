/// Unit tests for [UpgradeCommand] (gh-395, dm.ai #701 parity).
///
/// Written against the main-line implementation (gh-384/#414): the runtime
/// reachability (`mcp upgrade`) is gh-395's add-on — covered by the
/// dispatcher routing test below.
library;

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  late List<String> out;
  late List<String> downloads;
  late List<Map<String, String>> installs;

  setUp(() {
    out = [];
    downloads = [];
    installs = [];
  });

  UpgradeCommand cmd({
    bool dryRun = false,
    Future<String?> Function(String url)? fetch,
    int installerCode = 0,
  }) =>
      UpgradeCommand(
        writer: out.add,
        environment: {
          if (dryRun) 'DMTOOLS_UPGRADE_DRY_RUN': 'true',
        },
        fetchScript: (url) async {
          downloads.add(url);
          return fetch == null ? '/tmp/install.sh' : fetch(url);
        },
        runScript: (path, env) async {
          installs.add(env);
          return installerCode;
        },
      );

  group('version validation', () {
    test('rejects invalid version before any download or install', () async {
      expect(await cmd().run(['1.2']), 2);
      expect(await cmd().run(['1.2.3;echo']), 2);
      expect(downloads, isEmpty);
      expect(installs, isEmpty);
      expect(
        out.where((l) => l.contains('Invalid version')).length,
        2,
      );
    });

    test('accepts 1.2.3 and v1.2.3 and pins the tag', () async {
      expect(await cmd().run(['1.2.3']), 0);
      expect(await cmd().run(['v1.2.3']), 0);
      expect(installs, [
        containsPair('DMTOOLS_VERSION', '1.2.3'),
        containsPair('DMTOOLS_VERSION', 'v1.2.3'),
      ]);
      expect(
        downloads.first,
        'https://github.com/epam/dmtools-dart/releases/download/v1.2.3/install.sh',
      );
    });

    test('no version uses latest release installer', () async {
      expect(await cmd().run([]), 0);
      expect(
        downloads.single,
        'https://github.com/epam/dmtools-dart/releases/latest/download/install.sh',
      );
      expect(installs.single, isNot(contains('DMTOOLS_VERSION')));
    });
  });

  test('dry run changes nothing', () async {
    expect(await cmd(dryRun: true).run(['1.2.3']), 0);
    expect(downloads, isEmpty);
    expect(installs, isEmpty);
    expect(out, anyElement(contains('Dry run')));
  });

  test('failed download runs nothing and returns 1', () async {
    final code = await cmd(fetch: (_) async => null).run(['1.2.3']);
    expect(code, 1);
    expect(installs, isEmpty);
    expect(out, anyElement(contains('could not download')));
  });

  test('failing installer returns its exit code', () async {
    expect(await cmd(installerCode: 7).run(['1.2.3']), 7);
    expect(out, anyElement(contains('code 7')));
  });

  test(
    'dispatcher routes upgrade, update and mcp upgrade to the same command',
    () async {
      final lines = <String>[];
      final dispatcher = CliDispatcher(
        writer: lines.add,
        errorWriter: lines.add,
        isTty: () => false,
      );
      // Invalid version keeps the test offline: rejected before any download.
      expect(await dispatcher.dispatch(['upgrade', 'bad']), 2);
      expect(await dispatcher.dispatch(['update', 'bad']), 2);
      expect(await dispatcher.dispatch(['mcp', 'upgrade', 'bad']), 2);
      expect(await dispatcher.dispatch(['mcp', 'update', 'bad']), 2);
      expect(lines.where((l) => l.contains('Invalid version')).length, 4);
    },
  );
}
