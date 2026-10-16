import 'dart:io';

import 'package:dmtools/src/cli/help_text.dart';
import 'package:dmtools/src/cli/upgrade_command.dart';
import 'package:test/test.dart';

void main() {
  _helpTextTests();
  _upgradeDryRunTests();
  _upgradeInstallerTests();
}

void _helpTextTests() {
  group('help output formats', () {
    test('every supported output format is documented', () {
      for (final f in ['json', 'toon', 'mini', 'short', 'table', 'mermaid']) {
        expect(cliHelpText, contains(f));
      }
      expect(
        cliHelpText,
        contains('--output <json|toon|mini|short|table|mermaid>'),
      );
      expect(cliHelpText, contains('--toon'));
      expect(cliHelpText, contains('--mini'));
      expect(cliHelpText, contains('CLI_OUTPUT'));
    });

    test('documents upgrade command', () {
      expect(cliHelpText, contains('dmtools upgrade [version]'));
    });

    test('upgrade --help prints usage and exits 0 without downloading',
        () async {
      final lines = <String>[];
      var fetched = false;
      final code = await UpgradeCommand(
        writer: lines.add,
        environment: {},
        fetchScript: (_) async {
          fetched = true;
          return null;
        },
      ).run(['--help']);
      expect(code, 0);
      expect(fetched, isFalse);
      expect(lines.join('\n'), contains('Usage: dmtools upgrade [version]'));
    });
  });
}

void _upgradeDryRunTests() {
  group('UpgradeCommand dry-run and download failures', () {
    test('dry run makes no download or install', () async {
      final lines = <String>[];
      var fetched = false;
      final code = await UpgradeCommand(
        writer: lines.add,
        environment: {'DMTOOLS_UPGRADE_DRY_RUN': 'true'},
        fetchScript: (_) async {
          fetched = true;
          return null;
        },
      ).run([]);
      expect(code, 0);
      expect(fetched, isFalse);
      expect(lines.join('\n'), contains('Dry run'));
    });

    test('failed download exits non-zero and does not run installer', () async {
      final lines = <String>[];
      var ran = false;
      final code = await UpgradeCommand(
        writer: lines.add,
        environment: {},
        fetchScript: (_) async => null,
        runScript: (_, __) async {
          ran = true;
          return 0;
        },
      ).run(['0.1.60']);
      expect(code, 1);
      expect(ran, isFalse);
      expect(lines.join('\n'), contains('left untouched'));
    });
  });
}

void _upgradeInstallerTests() {
  group('UpgradeCommand installer selection', () {
    test('version selects tagged installer and passes DMTOOLS_VERSION',
        () async {
      String? url;
      Map<String, String>? seenEnv;
      final code = await UpgradeCommand(
        writer: (_) {},
        environment: {},
        fetchScript: (u) async {
          url = u;
          return '/tmp/x.sh';
        },
        runScript: (_, env) async {
          seenEnv = env;
          return 0;
        },
      ).run(['0.1.60']);
      expect(code, 0);
      expect(
        url,
        'https://github.com/epam/dmtools-dart/releases/download/v0.1.60/install.sh',
      );
      expect(seenEnv?['DMTOOLS_VERSION'], '0.1.60');
    });

    test('real download path: 200 runs, 404 and dead URL fail cleanly',
        () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        if (req.uri.path == '/ok') {
          req.response.write('#!/bin/sh\necho ok\n');
          await req.response.close();
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      addTearDown(server.close);
      final base = 'http://127.0.0.1:${server.port}';

      // 200: the fetched script is staged and executed.
      final ran = <String>[];
      final ok = await UpgradeCommand(
        writer: (_) {},
        environment: {'DMTOOLS_INSTALL_SCRIPT_URL': '$base/ok'},
        runScript: (script, _) async {
          ran.add(script);
          return 0;
        },
      ).run(['0.1.60']);
      expect(ok, 0);
      expect(ran, hasLength(1));
      expect(File(ran.single).readAsStringSync(), contains('echo ok'));

      // 404: download failure, installer never runs.
      var ranFailed = 0;
      final missing = await UpgradeCommand(
        writer: (_) {},
        environment: {'DMTOOLS_INSTALL_SCRIPT_URL': '$base/nope'},
        runScript: (_, __) async {
          ranFailed++;
          return 0;
        },
      ).run(['0.1.60']);
      expect(missing, 1);
      expect(ranFailed, 0);

      // Connection refused: the catch branch, still a clean exit 1.
      final dead = await UpgradeCommand(
        writer: (_) {},
        environment: {'DMTOOLS_INSTALL_SCRIPT_URL': 'http://127.0.0.1:1/x.sh'},
        runScript: (_, __) async => 0,
      ).run(['0.1.60']);
      expect(dead, 1);
    });

    test('installer override URL is honored', () async {
      String? url;
      await UpgradeCommand(
        writer: (_) {},
        environment: {'DMTOOLS_INSTALL_SCRIPT_URL': 'http://mirror/x.sh'},
        fetchScript: (u) async {
          url = u;
          return null;
        },
      ).run([]);
      expect(url, 'http://mirror/x.sh');
    });
  });
}
