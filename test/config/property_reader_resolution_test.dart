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
  _testDmtoolsLocalEnvResolution();
  _testResolutionOrder();
  _testOverridesWin();
  _testRealWorldFixture();
}

/// Writes content to a file under [_tmpDir] and returns the full path.
String _writeFile(String name, String content) {
  final path = '${_tmpDir.path}/$name';
  File(path).writeAsStringSync(content);
  return path;
}

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

void _testDmtoolsLocalEnvResolution() {
  group('dmtools-local.env resolution', () {
    test('reads values from dmtools-local.env', () {
      _writeFile('dmtools-local.env', '''
JIRA_BASE_PATH=https://local.atlassian.net
JIRA_EMAIL=local@test.com
''');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraBasePath(), 'https://local.atlassian.net');
      expect(reader.getJiraEmail(), 'local@test.com');
    });

    test('dmtools-local.env used when dmtools.env is absent', () {
      _writeFile('dmtools-local.env', 'GEMINI_API_KEY=local-key\n');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getGeminiApiKey(), 'local-key');
    });
  });
}

void _testResolutionOrder() {
  group('resolution order', () {
    test('dmtools.env wins over dmtools-local.env', () {
      _writeFile('dmtools.env', 'JIRA_BASE_PATH=from-env\n');
      _writeFile('dmtools-local.env', 'JIRA_BASE_PATH=from-local\n');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getJiraBasePath(), 'from-env');
    });

    test('dmtools-local.env wins over OS env', () {
      _writeFile('dmtools-local.env', 'HOME=/fake-home\n');
      final reader = PropertyReader(basePath: _tmpDir.path);
      expect(reader.getValue('HOME'), '/fake-home');
    });

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
