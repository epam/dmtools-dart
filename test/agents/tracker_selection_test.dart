import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Java `ServerManagedIntegrationsModule.provideTrackerClient` parity
/// (epam/dm.ai#730): DEFAULT_TRACKER=github + GitHub auto-detect fallback.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  const github = {
    'SOURCE_GITHUB_TOKEN': 'ghp_x',
    'SOURCE_GITHUB_WORKSPACE': 'TestOrg',
    'SOURCE_GITHUB_REPOSITORY': 'test-repo',
  };
  const jira = {'JIRA_BASE_PATH': 'https://jira.example.com'};

  test('DEFAULT_TRACKER=github wins over configured Jira', () {
    PropertyReader.setOverrides(
        {...jira, ...github, 'DEFAULT_TRACKER': 'GitHub'});
    expect(resolveTrackerType(PropertyReader()), 'github');
  });

  test('Jira auto-detects first without DEFAULT_TRACKER', () {
    PropertyReader.setOverrides({...jira, ...github});
    expect(resolveTrackerType(PropertyReader()), 'jira');
  });

  test('GitHub-only config auto-detects GitHub as last fallback', () {
    PropertyReader.setOverrides(github);
    expect(resolveTrackerType(PropertyReader()), 'github');
  });

  test('nothing configured resolves to null', () {
    PropertyReader.setOverrides({'DEFAULT_TRACKER': 'github'});
    expect(resolveTrackerType(PropertyReader()), isNull);
    expect(resolveGithubTrackerConfig(PropertyReader()), isNull);
  });

  test('GitHub config carries workspace/repository/branch defaults', () {
    PropertyReader.setOverrides(github);
    final c = resolveGithubTrackerConfig(PropertyReader())!;
    expect(c.workspace, 'TestOrg');
    expect(c.repository, 'test-repo');
    expect(c.branch, 'main');
    expect(c.basePath, 'https://api.github.com');
  });
}
