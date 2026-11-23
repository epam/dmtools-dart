import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

const _github = {
  'SOURCE_GITHUB_TOKEN': 'ghp_x',
  'SOURCE_GITHUB_WORKSPACE': 'TestOrg',
  'SOURCE_GITHUB_REPOSITORY': 'test-repo',
};
const _jira = {'JIRA_BASE_PATH': 'https://jira.example.com'};
const _gitlab = {
  'GITLAB_TOKEN': 'glpat_x',
  'GITLAB_WORKSPACE': 'my-group',
  'GITLAB_REPOSITORY': 'my-repo',
};

/// Java `ServerManagedIntegrationsModule.provideTrackerClient` parity
/// (epam/dm.ai#730 + #876): DEFAULT_TRACKER=github/gitlab + auto-detect.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  _testGithubTrackerSelection();
  _testGitlabTrackerSelection();
}

void _testGithubTrackerSelection() {
  test('DEFAULT_TRACKER=github wins over configured Jira', () {
    PropertyReader.setOverrides(
        {..._jira, ..._github, 'DEFAULT_TRACKER': 'GitHub'});
    expect(resolveTrackerType(PropertyReader()), 'github');
  });

  test('Jira auto-detects first without DEFAULT_TRACKER', () {
    PropertyReader.setOverrides({..._jira, ..._github});
    expect(resolveTrackerType(PropertyReader()), 'jira');
  });

  test('GitHub-only config auto-detects GitHub as fallback', () {
    PropertyReader.setOverrides(_github);
    expect(resolveTrackerType(PropertyReader()), 'github');
  });

  test('nothing configured resolves to null', () {
    PropertyReader.setOverrides({'DEFAULT_TRACKER': 'github'});
    expect(resolveTrackerType(PropertyReader()), isNull);
    expect(resolveGithubTrackerConfig(PropertyReader()), isNull);
  });

  test('GitHub config carries workspace/repository/branch defaults', () {
    PropertyReader.setOverrides(_github);
    final c = resolveGithubTrackerConfig(PropertyReader())!;
    expect(c.workspace, 'TestOrg');
    expect(c.repository, 'test-repo');
    expect(c.branch, 'main');
    expect(c.basePath, 'https://api.github.com');
  });
}

void _testGitlabTrackerSelection() {
  test('DEFAULT_TRACKER=gitlab wins over configured Jira and GitHub', () {
    PropertyReader.setOverrides({
      ..._jira,
      ..._github,
      ..._gitlab,
      'DEFAULT_TRACKER': 'GitLab',
    });
    expect(resolveTrackerType(PropertyReader()), 'gitlab');
  });

  test('GitLab-only config auto-detects GitLab as fallback', () {
    PropertyReader.setOverrides(_gitlab);
    expect(resolveTrackerType(PropertyReader()), 'gitlab');
    final c = resolveGitlabTrackerConfig(PropertyReader())!;
    expect(c.workspace, 'my-group');
    expect(c.repository, 'my-repo');
    expect(c.branch, 'main');
    expect(c.basePath, 'https://gitlab.com');
  });
}
