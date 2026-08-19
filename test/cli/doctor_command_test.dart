/// Unit tests for [DoctorCommand] (Java `ConfigDoctor.diagnose()` port).
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_doctor_');
    PropertyReader.setOverrides({});
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testEmptyConfiguration();
  _testDefaultConstructor();
  _testJira();
  _testConfluence();
  _testFigma();
  _testSimpleIntegrations();
  _testExtraIntegrations();
  _testAi();
  _testTeams();
}

DoctorCommand _command() =>
    DoctorCommand(reader: PropertyReader(basePath: _tmp.path));

void _writeEnv(String content) =>
    File('${_tmp.path}/dmtools.env').writeAsStringSync(content);

void _testEmptyConfiguration() {
  group('empty configuration', () {
    test('renders the Java header block and note', () {
      final out = _command().run();
      expect(
        out.startsWith(
          'DMTools Configuration Check\n'
          '==========================\n',
        ),
        isTrue,
      );
      expect(
        RegExp(r'^Integrations ready: \d+ / 13$', multiLine: true)
            .hasMatch(out),
        isTrue,
      );
      expect(
        out,
        contains(
          'Note: doctor checks configuration presence. Connectivity tests '
          'require Phase 3 integrations.',
        ),
      );
    });

    test('reports a status line for all 13 integrations', () {
      final out = _command().run();
      expect(RegExp(r'^[✓✗] ', multiLine: true).allMatches(out).length, 13);
    });
  });
}

void _testDefaultConstructor() {
  group('default constructor', () {
    test('loads from the working directory chain and still reports 13 checks',
        () {
      final out = DoctorCommand().run();
      expect(out, startsWith('DMTools Configuration Check'));
      expect(RegExp(r'^[✓✗] ', multiLine: true).allMatches(out).length, 13);
    });
  });
}

void _testJira() {
  group('jira', () {
    test('configured with base path + email + token', () {
      _writeEnv('''
JIRA_BASE_PATH=https://test.atlassian.net
JIRA_EMAIL=user@test.com
JIRA_API_TOKEN=abc123
''');
      expect(
        _command().run(),
        contains('✓ jira - Jira authentication configured'),
      );
    });

    test('configured with base path + prebuilt token', () {
      _writeEnv('''
JIRA_BASE_PATH=https://test.atlassian.net
JIRA_LOGIN_PASS_TOKEN=cHJlYnVpbHQ=
''');
      expect(
        _command().run(),
        contains('✓ jira - Jira authentication configured'),
      );
    });

    test('lists each missing credential variable', () {
      _writeEnv('JIRA_BASE_PATH=https://test.atlassian.net\n');
      final out = _command().run();
      expect(out, contains('✗ jira - Jira authentication incomplete'));
      expect(out, contains('    missing: JIRA_EMAIL'));
      expect(out, contains('    missing: JIRA_API_TOKEN'));
    });

    test('email without token reports only the token', () {
      _writeEnv('''
JIRA_BASE_PATH=https://test.atlassian.net
JIRA_EMAIL=user@test.com
''');
      final out = _command().run();
      expect(out, contains('    missing: JIRA_API_TOKEN'));
      expect(out, isNot(contains('missing: JIRA_EMAIL')));
    });
  });
}

void _testConfluence() {
  group('confluence', () {
    test('matches the Java example output shape', () {
      _writeEnv('CONFLUENCE_EMAIL=user@test.com\n');
      final out = _command().run();
      expect(
        out,
        contains('✗ confluence - Confluence authentication incomplete'),
      );
      expect(out, contains('    missing: CONFLUENCE_BASE_PATH'));
      expect(out, contains('    missing: CONFLUENCE_API_TOKEN'));
      expect(out, isNot(contains('missing: CONFLUENCE_EMAIL')));
    });

    test('configured with base path + email + token', () {
      _writeEnv('''
CONFLUENCE_BASE_PATH=https://test.atlassian.net/wiki
CONFLUENCE_EMAIL=user@test.com
CONFLUENCE_API_TOKEN=abc123
''');
      expect(
        _command().run(),
        contains('✓ confluence - Confluence authentication configured'),
      );
    });

    test('configured with the prebuilt token fallback', () {
      _writeEnv('''
CONFLUENCE_BASE_PATH=https://test.atlassian.net/wiki
CONFLUENCE_LOGIN_PASS_TOKEN=prebuilt
''');
      expect(
        _command().run(),
        contains('✓ confluence - Confluence authentication configured'),
      );
    });
  });
}

void _testFigma() {
  group('figma', () {
    test('configured via FIGMA_TOKEN', () {
      _writeEnv('FIGMA_TOKEN=fig-123\n');
      expect(
        _command().run(),
        contains('✓ figma - Figma authentication configured'),
      );
    });

    test('configured via FIGMA_OAUTH_ACCESS_TOKEN', () {
      _writeEnv('FIGMA_OAUTH_ACCESS_TOKEN=oauth-123\n');
      expect(
        _command().run(),
        contains('✓ figma - Figma authentication configured'),
      );
    });

    test('reports both alternatives when neither is set', () {
      final out = _command().run();
      expect(out, contains('✗ figma - Figma authentication incomplete'));
      expect(
        out,
        contains('    missing: FIGMA_TOKEN or FIGMA_OAUTH_ACCESS_TOKEN'),
      );
    });
  });
}

void _testSimpleIntegrations() {
  group('single-token integrations', () {
    test('github / gitlab / bitbucket / bitrise', () {
      _writeEnv('''
SOURCE_GITHUB_TOKEN=ghp_test
GITLAB_TOKEN=glpat-test
BITBUCKET_TOKEN=bb-test
BITRISE_TOKEN=br-test
''');
      final out = _command().run();
      expect(out, contains('✓ github - GitHub authentication configured'));
      expect(out, contains('✓ gitlab - GitLab authentication configured'));
      expect(
        out,
        contains('✓ bitbucket - Bitbucket authentication configured'),
      );
      expect(out, contains('✓ bitrise - Bitrise authentication configured'));
    });

    test('ado reports only the missing variable', () {
      _writeEnv('''
ADO_ORGANIZATION=my-org
ADO_PAT_TOKEN=pat
''');
      final out = _command().run();
      expect(out, contains('✗ ado - ADO authentication incomplete'));
      expect(out, contains('    missing: ADO_PROJECT'));
      expect(out, isNot(contains('missing: ADO_ORGANIZATION')));
    });
  });
}

void _testExtraIntegrations() {
  group('multi-token integrations', () {
    test('rally configured with token + path', () {
      _writeEnv('''
RALLY_TOKEN=rally-tok
RALLY_PATH=https://rally1.rallydev.com
''');
      expect(
        _command().run(),
        contains('✓ rally - Rally authentication configured'),
      );
    });

    test('testrail reports username and api key when only base path is set',
        () {
      _writeEnv('TESTRAIL_BASE_PATH=https://testrail.example.com\n');
      final out = _command().run();
      expect(out, contains('    missing: TESTRAIL_USERNAME'));
      expect(out, contains('    missing: TESTRAIL_API_KEY'));
    });

    test('xray configured with all three variables', () {
      _writeEnv('''
XRAY_CLIENT_ID=client
XRAY_CLIENT_SECRET=secret
XRAY_BASE_PATH=https://xray.example.com
''');
      expect(
        _command().run(),
        contains('✓ xray - Xray authentication configured'),
      );
    });
  });
}

const _aiVars = [
  'DIAL_API_KEY',
  'GEMINI_API_KEY',
  'OPENAI_API_KEY',
  'ANTHROPIC_MODEL',
  'BEDROCK_MODEL_ID',
  'OLLAMA_MODEL',
];

void _testAi() {
  group('ai', () {
    test('any single provider configures ai', () {
      _writeEnv('GEMINI_API_KEY=AIzaXYZ\n');
      expect(_command().run(), contains('✓ ai - AI authentication configured'));
    });

    test('a model-only provider (ollama) configures ai', () {
      _writeEnv('OLLAMA_MODEL=llama3\n');
      expect(_command().run(), contains('✓ ai - AI authentication configured'));
    });

    test('lists every provider variable when none is configured', () {
      final inOsEnv =
          _aiVars.any((k) => (Platform.environment[k] ?? '').trim().isNotEmpty);
      if (inOsEnv) {
        // Developer machines may export AI keys; the branch under test is
        // only reachable when the OS env has none (CI environments do not).
        return;
      }
      final out = _command().run();
      expect(out, contains('✗ ai - AI authentication incomplete'));
      expect(
        out,
        contains(
          '    missing: DIAL_API_KEY, GEMINI_API_KEY, OPENAI_API_KEY, '
          'ANTHROPIC_MODEL, BEDROCK_MODEL_ID or OLLAMA_MODEL',
        ),
      );
    });
  });
}

void _testTeams() {
  group('teams', () {
    test('configured with client id + tenant id', () {
      _writeEnv('''
TEAMS_CLIENT_ID=client-id
TEAMS_TENANT_ID=tenant-id
''');
      expect(
        _command().run(),
        contains('✓ teams - Teams authentication configured'),
      );
    });

    test('tenant id presence is checked raw (getter defaults to common)', () {
      _writeEnv('TEAMS_CLIENT_ID=client-id\n');
      expect(_command().run(), contains('    missing: TEAMS_TENANT_ID'));
    });
  });
}
