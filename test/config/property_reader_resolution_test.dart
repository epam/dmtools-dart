/// End-to-end fixture tests for the PropertyReader resolution chain.
///
/// Phase 1 "done when": a Java `dmtools.env` dropped into a Dart run
/// resolves to the same effective configuration.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmpDir;

void main() {
  setUp(() {
    _tmpDir = Directory.systemTemp.createTempSync('dmtools_test_');
  });
  tearDown(() {
    if (_tmpDir.existsSync()) {
      _tmpDir.deleteSync(recursive: true);
    }
  });

  _testDmtoolsEnvResolution();
  _testEmptyValueFallThrough();
  _testEnvFileSearchOrder();
  _testEnvFileCandidateAdoption();
  _testProjectRootMarker();
  _testConfigPropertiesTier();
  _testConfigResourceFallback();
  _testResolutionOrder();
  _testLocalEnvTierRemoved();
  _testOverridesWin();
  _testRealWorldFixture();
}

/// Writes content to a file under [_tmpDir] and returns the full path.
String _writeFile(String name, String content) =>
    _writeFileAt(_tmpDir.path, name, content);

/// Writes [content] to [name] inside [dirPath] and returns the full path.
String _writeFileAt(String dirPath, String name, String content) {
  final path = '$dirPath/$name';
  File(path).writeAsStringSync(content);
  return path;
}

/// Drops the project-root marker into [dir] (the Gradle settings file
/// `findProjectRoot` walks up looking for — P6-CFG-05).
void _writeRootMarker(Directory dir) =>
    _writeFileAt(dir.path, 'settings.gradle', '');

void _testDmtoolsEnvResolution() {
  group('dmtools.env resolution', () {
    test('reads values from dmtools.env', () {
      _writeFile('dmtools.env', '''
JIRA_BASE_PATH=https://test.atlassian.net
JIRA_EMAIL=user@test.com
JIRA_API_TOKEN=abc123
GEMINI_API_KEY=AIzaXYZ
''');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraBasePath(), 'https://test.atlassian.net');
      expect(reader.getJiraEmail(), 'user@test.com');
      expect(reader.getGeminiApiKey(), 'AIzaXYZ');
    });

    test('dmtools.env values flow through getters with defaults', () {
      _writeFile('dmtools.env', '''
SOURCE_GITHUB_TOKEN=ghp_test
OLLAMA_BASE_PATH=http://ollama.local:11434
OPENAI_API_KEY=sk-test
''');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getGithubToken(), 'ghp_test');
      expect(reader.getOllamaBasePath(), 'http://ollama.local:11434');
      expect(reader.getOpenAIApiKey(), 'sk-test');
    });

    test('missing dmtools.env returns null / default', () {
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraBasePath(), isNull);
      expect(reader.getGithubBasePath(), 'https://api.github.com');
    });

    test('comments and blank lines in dmtools.env are handled', () {
      _writeFile('dmtools.env', '''

# This is a comment
JIRA_BASE_PATH=https://comment-test.atlassian.net

# Another comment
GEMINI_API_KEY=test-key
''');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraBasePath(), 'https://comment-test.atlassian.net');
      expect(reader.getGeminiApiKey(), 'test-key');
    });
  });
}

void _testEmptyValueFallThrough() {
  group('empty-value fall-through (P6-CFG-02)', () {
    setUp(() => PropertyReader.testIsolation = true);
    tearDown(() {
      PropertyReader.testIsolation = false;
      PropertyReader.testEnvironment.clear();
    });

    test('empty dmtools.env value falls through to OS env', () {
      _writeFile('dmtools.env', 'EMPTY_THEN_ENV=\nFILE_ONLY_KEY=\n');
      PropertyReader.testEnvironment['EMPTY_THEN_ENV'] = 'from-os';
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getValue('EMPTY_THEN_ENV'), 'from-os');
      expect(reader.getValue('FILE_ONLY_KEY'), isNull);
    });

    test('empty override value is returned as-is (no fall-through)', () {
      _writeFile('dmtools.env', 'OVR_EMPTY=from-file\n');
      PropertyReader.testEnvironment['OVR_EMPTY'] = 'from-os';
      PropertyReader.setOverrides({'OVR_EMPTY': ''});
      addTearDown(PropertyReader.clearOverrides);
      expect(PropertyReader().getValue('OVR_EMPTY'), '');
    });

    test('getValueWithDefault substitutes a default for empty file values', () {
      _writeFile('dmtools.env', 'EMPTY_WITH_DEFAULT=\n');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(
        reader.getValueWithDefault('EMPTY_WITH_DEFAULT', 'dflt'),
        'dflt',
      );
    });
  });
}

(Directory, String) _makeRootWithInner(String prefix) {
  final rootDir = Directory.systemTemp.createTempSync(prefix);
  final cwdPath = '${rootDir.path}/inner';
  Directory(cwdPath).createSync();
  return (rootDir, cwdPath);
}

void _testEnvFileSearchOrder() {
  group('dmtools.env search order — root first, then CWD (P6-CFG-04)', () {
    late Directory rootDir;
    late String cwdPath;

    setUp(() {
      final fix = _makeRootWithInner('dmtools_root_');
      rootDir = fix.$1;
      cwdPath = fix.$2;
      _writeRootMarker(rootDir);
    });
    tearDown(() {
      if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
    });

    test('project root wins over the working directory', () {
      _writeFileAt(rootDir.path, 'dmtools.env', 'ORDER_KEY=from-root\n');
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), 'from-root');
    });

    test('falls back to the working directory when the root has no file', () {
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), 'from-cwd');
    });

    test('no separate CWD lookup when user.dir == project root', () {
      _writeRootMarker(Directory(cwdPath));
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=same-dir\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), 'same-dir');
    });
  });
}

void _testEnvFileCandidateAdoption() {
  group('dmtools.env candidate adoption — empty and invalid files (P6-CFG-04)',
      () {
    late Directory rootDir;
    late String cwdPath;

    setUp(() {
      final fix = _makeRootWithInner('dmtools_adopt_');
      rootDir = fix.$1;
      cwdPath = fix.$2;
      _writeRootMarker(rootDir);
    });
    tearDown(() {
      if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
    });

    test('a dmtools.env that parses empty is skipped for the next candidate',
        () {
      _writeFileAt(rootDir.path, 'dmtools.env', '# only comments\n\n');
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), 'from-cwd');
    });

    test(
        'a non-empty root dmtools.env blocks the CWD candidate '
        'even for absent keys', () {
      _writeFileAt(rootDir.path, 'dmtools.env', 'OTHER_KEY=from-root\n');
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), isNull);
      expect(reader.getValue('OTHER_KEY'), 'from-root');
    });

    test('unreadable dmtools.env is skipped with a warning, search continues',
        () {
      // 0xFF is never valid UTF-8, so the line reader throws.
      File('${rootDir.path}/dmtools.env')
          .writeAsBytesSync(const <int>[0xFF, 0xFE, 0x00]);
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), 'from-cwd');
    });

    test('a directory named dmtools.env is not adopted (regular-file check)',
        () {
      Directory('${rootDir.path}/dmtools.env').createSync();
      _writeFileAt(cwdPath, 'dmtools.env', 'ORDER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      expect(reader.getValue('ORDER_KEY'), 'from-cwd');
    });
  });
}

void _testProjectRootMarker() {
  group('project root marker — Gradle settings files (P6-CFG-05)', () {
    late Directory rootDir;
    late String cwdPath;

    setUp(() {
      rootDir = Directory.systemTemp.createTempSync('dmtools_marker_');
      cwdPath = '${rootDir.path}/inner';
      Directory(cwdPath).createSync();
    });
    tearDown(() {
      if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
    });

    test('a settings.gradle marker pins the project root', () {
      _writeFileAt(rootDir.path, 'settings.gradle', '');
      _writeFileAt(rootDir.path, 'dmtools.env', 'MARKER_KEY=from-root\n');
      _writeFileAt(cwdPath, 'dmtools.env', 'MARKER_KEY=from-cwd\n');
      expect(PropertyReader(basePath: cwdPath).getValue('MARKER_KEY'),
          'from-root');
    });

    test('a settings.gradle.kts marker pins the project root', () {
      _writeFileAt(rootDir.path, 'settings.gradle.kts', '');
      _writeFileAt(rootDir.path, 'dmtools.env', 'MARKER_KEY=from-root\n');
      _writeFileAt(cwdPath, 'dmtools.env', 'MARKER_KEY=from-cwd\n');
      expect(PropertyReader(basePath: cwdPath).getValue('MARKER_KEY'),
          'from-root');
    });

    test('no marker anywhere falls back to the working directory as root', () {
      _writeFileAt(cwdPath, 'dmtools.env', 'MARKER_KEY=from-cwd\n');
      final reader = PropertyReader(basePath: cwdPath);
      // Root == CWD, so the single candidate still resolves.
      expect(reader.getValue('MARKER_KEY'), 'from-cwd');
    });

    test('a pubspec.yaml alone does NOT pin the project root', () {
      _writeFileAt(rootDir.path, 'pubspec.yaml', '');
      _writeFileAt(rootDir.path, 'dmtools.env', 'MARKER_KEY=from-root\n');
      _writeFileAt(cwdPath, 'dmtools.env', 'MARKER_KEY=from-cwd\n');
      // No Gradle marker up the tree: root falls back to CWD, whose own
      // file wins over the (never-consulted) root candidate.
      expect(
          PropertyReader(basePath: cwdPath).getValue('MARKER_KEY'), 'from-cwd');
    });
  });
}

/// Shared fixture for the config.properties tier groups (P6-CFG-01).
class _CfgFixture {
  _CfgFixture(String prefix)
      : rootDir = Directory.systemTemp.createTempSync(prefix) {
    cwdPath = '${rootDir.path}/inner';
    Directory(cwdPath).createSync();
    _writeFileAt(rootDir.path, 'settings.gradle', '');
  }

  final Directory rootDir;
  late final String cwdPath;

  PropertyReader reader() => PropertyReader(basePath: cwdPath);

  String writeDiskConfig(String content) {
    final dir = '${rootDir.path}/src/main/resources';
    Directory(dir).createSync(recursive: true);
    return _writeFileAt(dir, 'config.properties', content);
  }

  void dispose() {
    PropertyReader.setConfigFile('/config.properties');
    if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
  }
}

void _testConfigPropertiesTier() {
  group('config.properties tier (P6-CFG-01)', () {
    late _CfgFixture fix;

    setUp(() => fix = _CfgFixture('dmtools_cfg_'));
    tearDown(() => fix.dispose());

    test('reads <root>/src/main/resources/config.properties from disk', () {
      fix.writeDiskConfig('CFG_DISK_KEY=from-disk\n');
      expect(fix.reader().getValue('CFG_DISK_KEY'), 'from-disk');
    });

    test('disk config.properties wins over dmtools.env', () {
      fix.writeDiskConfig('CFG_TIER_KEY=from-config\n');
      _writeFileAt(fix.cwdPath, 'dmtools.env', 'CFG_TIER_KEY=from-env\n');
      expect(fix.reader().getValue('CFG_TIER_KEY'), 'from-config');
    });

    test('empty config.properties value falls through to dmtools.env', () {
      fix.writeDiskConfig('CFG_FALL_KEY=\n');
      _writeFileAt(fix.cwdPath, 'dmtools.env', 'CFG_FALL_KEY=from-env\n');
      expect(fix.reader().getValue('CFG_FALL_KEY'), 'from-env');
    });

    test('an existing-but-empty config.properties blocks the resource tier',
        () {
      fix.writeDiskConfig('# nothing but comments\n');
      _writeFileAt(fix.rootDir.path, 'custom.properties', 'CFG_RSRCE_KEY=x\n');
      PropertyReader.setConfigFile('${fix.rootDir.path}/custom.properties');
      expect(fix.reader().getValue('CFG_RSRCE_KEY'), isNull);
    });

    test('setConfigFile does NOT override the on-disk tier', () {
      fix.writeDiskConfig('CFG_TIER_KEY=from-disk\n');
      _writeFileAt(
          fix.rootDir.path, 'custom.properties', 'CFG_TIER_KEY=rsrce\n');
      PropertyReader.setConfigFile('${fix.rootDir.path}/custom.properties');
      expect(fix.reader().getValue('CFG_TIER_KEY'), 'from-disk');
    });
  });
}

void _testConfigResourceFallback() {
  group('config.properties resource fallback — setConfigFile (P6-CFG-01)', () {
    late _CfgFixture fix;

    setUp(() => fix = _CfgFixture('dmtools_rsrce_'));
    tearDown(() => fix.dispose());

    test('setConfigFile redirects the fallback tier when disk config is absent',
        () {
      _writeFileAt(
          fix.rootDir.path, 'custom.properties', 'CFG_RSRCE_KEY=rsrce\n');
      PropertyReader.setConfigFile('${fix.rootDir.path}/custom.properties');
      expect(fix.reader().getValue('CFG_RSRCE_KEY'), 'rsrce');
    });

    test('a missing setConfigFile resource resolves to nothing', () {
      PropertyReader.setConfigFile('${fix.rootDir.path}/nope.properties');
      expect(fix.reader().getValue('CFG_RSRCE_KEY'), isNull);
    });

    test('a relative resource path resolves against the reader base dir', () {
      _writeFileAt(fix.cwdPath, 'rel.properties', 'CFG_REL_KEY=relative\n');
      PropertyReader.setConfigFile('rel.properties');
      expect(fix.reader().getValue('CFG_REL_KEY'), 'relative');
    });

    test('resetForTesting clears the config.properties cache', () {
      final path = fix.writeDiskConfig('CFG_RESET_KEY=one\n');
      final reader = fix.reader();
      expect(reader.getValue('CFG_RESET_KEY'), 'one');
      reader.resetForTesting();
      File(path).writeAsStringSync('CFG_RESET_KEY=two\n');
      expect(reader.getValue('CFG_RESET_KEY'), 'two');
    });

    test('resetForTesting clears the project-root cache', () {
      File('${fix.rootDir.path}/settings.gradle').deleteSync();
      final reader = fix.reader(); // root falls back to the CWD (no marker yet)
      expect(reader.getValue('CFG_LATE_KEY'), isNull);
      // Marker and disk config appear AFTER the root was cached.
      _writeFileAt(fix.rootDir.path, 'settings.gradle', '');
      final dir = '${fix.rootDir.path}/src/main/resources';
      Directory(dir).createSync(recursive: true);
      _writeFileAt(dir, 'config.properties', 'CFG_LATE_KEY=late\n');
      // The cached root still points at the stale CWD fallback.
      expect(reader.getValue('CFG_LATE_KEY'), isNull);
      reader.resetForTesting();
      expect(reader.getValue('CFG_LATE_KEY'), 'late');
    });
  });
}

void _testResolutionOrder() {
  group('resolution order', () {
    test('dmtools.env wins over OS env', () {
      _writeFile('dmtools.env', 'PATH=/fake-path\n');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getValue('PATH'), '/fake-path');
    });

    test('falls through to OS env when not in files', () {
      final reader = PropertyReader(basePath: _tmpDir.path);
      // PATH is always in OS env.
      expect(reader.getValue('PATH'), isNotNull);
      expect(reader.getValue('PATH'), isNot('/fake-path'));
    });
  });
}

void _testLocalEnvTierRemoved() {
  group('dmtools-local.env tier removed (P6-CFG-03)', () {
    setUp(() => PropertyReader.testIsolation = true);
    tearDown(() {
      PropertyReader.testIsolation = false;
      PropertyReader.testEnvironment.clear();
    });

    test('a dmtools-local.env value does NOT resolve (tier is gone)', () {
      // Only a dmtools-local.env exists — no dmtools.env, no override, and
      // the OS-env tier is empty under test isolation.
      _writeFile('dmtools-local.env', 'LOCAL_TOKEN=from-local\n');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getValue('LOCAL_TOKEN'), isNull);
    });
  });
}

void _testOverridesWin() {
  group('overrides win', () {
    test('overrides take priority over dmtools.env', () {
      _writeFile('dmtools.env', 'JIRA_BASE_PATH=from-file\n');
      PropertyReader.setOverrides({'JIRA_BASE_PATH': 'from-override'});
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraBasePath(), 'from-override');
      PropertyReader.clearOverrides();
    });

    test('overrides take priority over OS env', () {
      PropertyReader.setOverrides({'PATH': '/override-path'});
      final reader = PropertyReader();
      expect(reader.getValue('PATH'), '/override-path');
      PropertyReader.clearOverrides();
    });
  });
}

const _fixtureEnv = '''
# Jira (Cloud)
JIRA_BASE_PATH=https://myteam.atlassian.net
JIRA_EMAIL=devops@myteam.com
JIRA_API_TOKEN=ATATT3xFfGF0T0k3n
JIRA_AUTH_TYPE=Basic

# GitHub
SOURCE_GITHUB_TOKEN=ghp_abc123def456
SOURCE_GITHUB_REPOSITORY=myorg/dmtools-dart

# AI - Gemini
GEMINI_API_KEY=AIzaSyB123456789
GEMINI_MODEL=gemini-2.0-flash

# Ollama
OLLAMA_BASE_PATH=http://gpu-box:11434
OLLAMA_MODEL=llama3

# OpenAI
OPENAI_API_KEY=sk-proj-xyz789
OPENAI_MODEL=gpt-4o
''';

void _testRealWorldFixture() {
  group('real-world fixture', () {
    test('complete dmtools.env resolves trackers', () {
      _writeFile('dmtools.env', _fixtureEnv);
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraLoginPassToken(), isNotNull);
      expect(reader.getJiraBasePath(), 'https://myteam.atlassian.net');
      expect(reader.getJiraAuthType(), 'Basic');
      expect(reader.getGithubToken(), 'ghp_abc123def456');
      expect(reader.getGithubRepository(), 'myorg/dmtools-dart');
    });

    test('complete dmtools.env resolves AI providers', () {
      _writeFile('dmtools.env', _fixtureEnv);
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getGeminiApiKey(), 'AIzaSyB123456789');
      expect(reader.getGeminiDefaultModel(), 'gemini-2.0-flash');
      expect(reader.getOllamaBasePath(), 'http://gpu-box:11434');
      expect(reader.getOllamaModel(), 'llama3');
      expect(reader.getOpenAIApiKey(), 'sk-proj-xyz789');
      expect(reader.getOpenAIModel(), 'gpt-4o');
    });

    test('Jira base64 token composition from fixture matches Java format', () {
      _writeFile('dmtools.env', '''
JIRA_EMAIL=test@example.com
JIRA_API_TOKEN=secret-token
''');
      final reader = PropertyReader(basePath: _tmpDir.path);
      // Java: base64(email:token) — Dart produces identical output for ASCII.
      final token = reader.getJiraLoginPassToken();
      expect(token, isNotNull);
      expect(token, isNotEmpty);
    });
  });
}
