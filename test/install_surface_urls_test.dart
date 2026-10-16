import 'dart:io';

import 'package:test/test.dart';

/// Parity with dm.ai#720 (gh-398): every GitHub URL on the install surface
/// (installers, README, `--help`) must point at this repository or at a
/// known external project — never at an abandoned or foreign distribution repo.
void main() {
  const ownRepo = 'epam/dmtools-dart';

  // External projects legitimately referenced from the install surface.
  const externalRepos = {
    'IstiN/dmtools-agents',
    'IstiN/flutter_agent_harness',
    'IstiN/crap4dart',
    'epam/dm.ai', // Java sibling distribution
    'IstiN/flutter_js_widget_runtime',
  };

  final surfaceFiles = [
    'install.sh',
    'install.ps1',
    'install.bat',
    'README.md',
    'lib/src/cli/help_text.dart',
  ];

  final urlPattern = RegExp(
    r'https?://(?:github\.com|raw\.githubusercontent\.com)/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)',
  );

  group('install surface GitHub URLs', () {
    for (final path in surfaceFiles) {
      test('$path only names this repository or an allowed external one', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        final offending = <String>[];
        for (final match in urlPattern.allMatches(file.readAsStringSync())) {
          var repo = '${match.group(1)}/${match.group(2)}';
          if (repo.endsWith('.git')) repo = repo.substring(0, repo.length - 4);
          if (repo == ownRepo || externalRepos.contains(repo)) continue;
          offending.add(match.group(0)!);
        }
        expect(offending, isEmpty,
            reason: 'Install-surface URLs must point at $ownRepo '
                '(stale/foreign repos cause mixed installs).');
      });
    }

    test('no install-surface file references the abandoned IstiN/dmtools repo',
        () {
      for (final path in surfaceFiles) {
        final text = File(path).readAsStringSync();
        expect(RegExp(r'IstiN/dmtools(?![-\w])').hasMatch(text), isFalse,
            reason: '$path references the old IstiN/dmtools repository');
      }
    });
  });
}
