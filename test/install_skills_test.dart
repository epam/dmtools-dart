import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Parity tests for dm.ai#675 on `install.sh`: global skill installation,
/// `--skills=...` / `DMTOOLS_SKILLS`, `--no-skills`, `--prune`, and
/// `installed-skills.json` / `dmtools-installer.env` metadata.
void main() {
  if (Platform.isWindows) return;

  late Directory sandbox;
  late String assetName;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('dmtools_install_skills_');
    assetName = _detectBundleAssetName();
    _writeFakeBundle(sandbox, assetName);
    _writeFakeSkillInstallScript(sandbox);
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  _testDefaultAndSelectedSkills(() => sandbox);
  _testNoSkillsAndPruneAndFallback(() => sandbox);
}

void _testDefaultAndSelectedSkills(Directory Function() getSandbox) {
  group('install.sh global skill installation (dm.ai#675 parity)', () {
    test('installs selected skills globally and writes installer metadata', () {
      final sb = getSandbox();
      final res =
          _runInstall(sb, ['--skills=jira,gitlab,confluence', '0.1.92']);
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');

      final envFile =
          File('${sb.path}/home/.dmtools/bin/dmtools-installer.env');
      expect(envFile.existsSync(), isTrue);
      final envText = envFile.readAsStringSync();
      expect(envText, contains('DMTOOLS_SKILLS="jira,gitlab,confluence"'));
      expect(
        envText,
        contains(
            'DMTOOLS_INTEGRATIONS="ai,cli,file,kb,mermaid,jira,gitlab,confluence"'),
      );

      final skillsJson = jsonDecode(
        File('${sb.path}/home/.dmtools/installed-skills.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(skillsJson['version'], equals('v0.1.92'));
      final names = (skillsJson['installed_skills'] as List)
          .map((e) => (e as Map)['name'])
          .toList();
      expect(names, equals(['jira', 'gitlab', 'confluence']));

      final invoked =
          File('${sb.path}/skill_invocations.log').readAsStringSync().trim();
      expect(invoked, equals('--global --skills=jira,gitlab,confluence'));
    });

    test('defaults to all 11 skills when no skill flag or env is provided', () {
      final sb = getSandbox();
      final res = _runInstall(sb, const []);
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');

      final invoked =
          File('${sb.path}/skill_invocations.log').readAsStringSync().trim();
      expect(invoked, equals('--global --all-skills'));

      final envText = File('${sb.path}/home/.dmtools/bin/dmtools-installer.env')
          .readAsStringSync();
      expect(
        envText,
        contains(
          'DMTOOLS_SKILLS="dmtools,jira,confluence,github,gitlab,figma,teams,sharepoint,ado,testrail,xray"',
        ),
      );
    });
  });
}

void _testNoSkillsAndPruneAndFallback(Directory Function() getSandbox) {
  group('install.sh skill flags and non-fatal fallback', () {
    test('--no-skills skips downloading and running skill-install.sh', () {
      final sb = getSandbox();
      final res = _runInstall(sb, ['--no-skills', '--skill', 'jira']);
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');
      expect(File('${sb.path}/skill_invocations.log').existsSync(), isFalse);
      expect(
        File('${sb.path}/home/.dmtools/bin/dmtools').existsSync(),
        isTrue,
      );
    });

    test('forwards --prune and --skip-unknown to skill-install.sh', () {
      final sb = getSandbox();
      final res = _runInstall(
        sb,
        ['--skills=jira,unknown_pkg', '--skip-unknown', '--prune'],
      );
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');
      final invoked =
          File('${sb.path}/skill_invocations.log').readAsStringSync().trim();
      expect(
        invoked,
        equals('--global --skills=jira --skip-unknown --prune'),
      );
    });

    test('rejects unknown CLI skill without --skip-unknown', () {
      final sb = getSandbox();
      final res = _runInstall(sb, ['--skills=jira,not_a_skill']);
      expect(res.exitCode, isNonZero);
      expect(res.stderr.toString(), contains('Unknown skills: not_a_skill'));
    });

    test('missing skill-install.sh warns but CLI installation still succeeds',
        () {
      final sb = getSandbox();
      final res = _runInstall(
        sb,
        ['--skill=jira'],
        skillBaseUrl: 'file://${sb.path}/missing_dir',
      );
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');
      expect(
        res.stderr.toString(),
        contains('Could not download skill-install.sh'),
      );
      expect(
        File('${sb.path}/home/.dmtools/bin/dmtools').existsSync(),
        isTrue,
      );
    });
  });
}

String _detectBundleAssetName() {
  final os = Platform.isMacOS ? 'macos' : 'linux';
  final uname = Process.runSync('uname', ['-m']).stdout.toString().trim();
  final arch = (uname == 'arm64' || uname == 'aarch64') ? 'arm64' : 'x64';
  return 'dmtools-$os-$arch.tar.gz';
}

void _writeFakeBundle(Directory sb, String assetName) {
  final bundleRoot = Directory('${sb.path}/bundle/dmtools/native/quickjs')
    ..createSync(recursive: true);
  File('${bundleRoot.path}/libquickjs_bridge.so').writeAsStringSync('stub-so');
  final bin = File('${sb.path}/bundle/dmtools/dmtools')
    ..writeAsStringSync('#!/bin/sh\necho "dmtools 0.1.92-test"\n');
  Process.runSync('chmod', ['+x', bin.path]);
  final releases = Directory('${sb.path}/releases')..createSync();
  Process.runSync(
    'tar',
    [
      '-czf',
      '${releases.path}/$assetName',
      '-C',
      '${sb.path}/bundle',
      'dmtools'
    ],
  );
}

void _writeFakeSkillInstallScript(Directory sb) {
  final script = File('${sb.path}/releases/skill-install.sh')
    ..writeAsStringSync(
      '#!/usr/bin/env bash\n'
      'printf "%s\\n" "\$*" > "${sb.path}/skill_invocations.log"\n',
    );
  Process.runSync('chmod', ['+x', script.path]);
}

ProcessResult _runInstall(
  Directory sb,
  List<String> args, {
  String? skillBaseUrl,
}) {
  final home = Directory('${sb.path}/home')..createSync(recursive: true);
  final releaseUrl = 'file://${sb.path}/releases';
  return Process.runSync(
    'sh',
    ['install.sh', ...args],
    environment: {
      'HOME': home.path,
      'SHELL': '/bin/zsh',
      'DMTOOLS_INSTALL_DIR': '${home.path}/.dmtools',
      'DMTOOLS_DOWNLOAD_BASE': releaseUrl,
      'DMTOOLS_SKILL_INSTALL_BASE_URL': skillBaseUrl ?? releaseUrl,
    },
  );
}
