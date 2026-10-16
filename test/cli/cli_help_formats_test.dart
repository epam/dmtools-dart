import 'package:dmtools/src/cli/help_text.dart';
import 'package:dmtools/src/cli/upgrade_command.dart';
import 'package:test/test.dart';

void main() {
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
  });

  group('UpgradeCommand', () {
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

    test(
      'version selects tagged installer and passes DMTOOLS_VERSION',
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
      },
    );

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
