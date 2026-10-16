/// Unit tests for [UpgradeCommand] (gh-395, dm.ai #701 parity).
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  late List<String> out;
  late List<String> err;
  late List<Uri> downloads;
  late List<List<String>> installs;

  setUp(() {
    out = [];
    err = [];
    downloads = [];
    installs = [];
  });

  UpgradeCommand cmd({
    bool dryRun = false,
    Future<List<int>> Function(Uri)? download,
    int installerCode = 0,
  }) =>
      UpgradeCommand(
        writer: out.add,
        errorWriter: err.add,
        dryRun: dryRun,
        download: (u) async {
          downloads.add(u);
          return download == null ? [1, 2, 3] : download(u);
        },
        runInstaller: (path, args) async {
          installs.add(args);
          return installerCode;
        },
      );

  group('version validation', () {
    test('rejects invalid version before any download or install', () async {
      expect(await cmd().run(['1.2']), 1);
      expect(await cmd().run(['1.2.3;echo']), 1);
      expect(downloads, isEmpty);
      expect(installs, isEmpty);
      expect(err, hasLength(2));
      expect(err, everyElement(contains('invalid version')));
    });

    test('accepts 1.2.3 and v1.2.3 and pins the tag', () async {
      expect(await cmd().run(['1.2.3']), 0);
      expect(await cmd().run(['v1.2.3']), 0);
      expect(installs, [
        ['v1.2.3'],
        ['v1.2.3'],
      ]);
      expect(
        downloads.first.toString(),
        'https://github.com/epam/dmtools-dart/releases/download/v1.2.3/install.sh',
      );
    });

    test('no version uses latest release installer', () async {
      expect(await cmd().run([]), 0);
      expect(
        downloads.single.toString(),
        'https://github.com/epam/dmtools-dart/releases/latest/download/install.sh',
      );
      expect(installs.single, isEmpty);
    });
  });

  test('dry run changes nothing', () async {
    expect(await cmd(dryRun: true).run(['1.2.3']), 0);
    expect(downloads, isEmpty);
    expect(installs, isEmpty);
    expect(out.single, contains('Dry run'));
  });

  test('failed download runs nothing and returns 1', () async {
    final code = await cmd(
      download: (_) async => throw const HttpException('boom'),
    ).run(['1.2.3']);
    expect(code, 1);
    expect(installs, isEmpty);
    expect(err.single, contains('failed to download'));
  });

  test('failing installer returns its exit code', () async {
    expect(await cmd(installerCode: 7).run(['1.2.3']), 7);
    expect(err.single, contains('code 7'));
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
      expect(await dispatcher.dispatch(['upgrade', 'bad']), 1);
      expect(await dispatcher.dispatch(['update', 'bad']), 1);
      expect(await dispatcher.dispatch(['mcp', 'upgrade', 'bad']), 1);
      expect(await dispatcher.dispatch(['mcp', 'update', 'bad']), 1);
      expect(lines.where((l) => l.contains('invalid version')).length, 4);
    },
  );
}
