/// Tracker backend selection — Java `ServerManagedIntegrationsModule
/// .provideTrackerClient` parity (epam/dm.ai#730).
///
/// An explicit `DEFAULT_TRACKER` (`jira` / `ado` / `rally` / `github`,
/// case-insensitive) wins when that integration is configured; otherwise
/// the first configured integration in Java's auto-detect order — Jira,
/// ADO, Rally, then GitHub as the last fallback.
library;

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';

/// Resolved GitHub tracker coordinates (Java `createGitHubTrackerClient`).
typedef GithubTrackerConfig = ({
  String basePath,
  String workspace,
  String repository,
  String branch,
});

bool _set(String? v) => v != null && v.trim().isNotEmpty;

bool _configured(PropertyReader r, String tracker) => switch (tracker) {
      'jira' => _set(r.getJiraBasePath()),
      'ado' => _set(r.getAdoOrganization()) && _set(r.getAdoPatToken()),
      'rally' => _set(r.getRallyPath()) && _set(r.getRallyToken()),
      'github' => _set(r.getGithubToken()),
      _ => false,
    };

/// The tracker type to use, or `null` when none is configured.
String? resolveTrackerType(PropertyReader reader) {
  final wanted = reader.getDefaultTracker()?.trim().toLowerCase() ?? '';
  if (wanted.isNotEmpty && _configured(reader, wanted)) return wanted;
  for (final t in const ['jira', 'ado', 'rally', 'github']) {
    if (_configured(reader, t)) return t;
  }
  return null;
}

/// GitHub tracker config from the resolved integration properties, or
/// `null` without a token (Java returns a null client then). Branch
/// defaults to `main`, base path to `https://api.github.com`.
GithubTrackerConfig? resolveGithubTrackerConfig(PropertyReader reader) {
  if (!_configured(reader, 'github')) return null;
  final branch = reader.getGithubBranch()?.trim() ?? '';
  return (
    basePath: reader.getGithubBasePath(),
    workspace: reader.getGithubWorkspace()?.trim() ?? '',
    repository: reader.getGithubRepository()?.trim() ?? '',
    branch: branch.isEmpty ? 'main' : branch,
  );
}
