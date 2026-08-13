/// Integration-specific property getters for [PropertyReader].
///
/// Ports every env-var getter from the Java `PropertyReader` class, grouped
/// by integration. All key names, default values, and special logic (base64
/// composition, fallback chains, range clamping) are identical to the Java
/// source.
library;

import 'dart:convert';

import 'property_reader.dart';

/// Splits a comma-separated value into an upper-case immutable set.
///
/// Standalone equivalent of `PropertyReader._parseUpperSet` (extensions cannot
/// access private members).
Set<String> _parseUpperSetExt(String? value) {
  if (value == null || value.trim().isEmpty) return const {};
  return Set.unmodifiable(
    value
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet(),
  );
}

/// Getters for [PropertyReader], ported 1:1 from Java.
extension PropertyReaderGetters on PropertyReader {
  // --- CLI / File / Cache ---

  /// CLI output format (json|toon|mini). Key: `CLI_OUTPUT`.
  String? getCliOutput() => getValue('CLI_OUTPUT');

  /// Comma-separated glob patterns for file_read.
  /// Key: `DMTOOLS_FILE_READ_ALLOWED_PATHS`.
  String? getFileReadAllowedPaths() =>
      getValue('DMTOOLS_FILE_READ_ALLOWED_PATHS');

  /// Extra allowed CLI commands (comma-separated, lowercased).
  /// Key: `CLI_ALLOWED_COMMANDS`.
  Set<String> getCliAllowedCommands() {
    final v = getValue('CLI_ALLOWED_COMMANDS');
    if (v == null || v.trim().isEmpty) return const {};
    return v
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  /// Whether caching is enabled. Key: `DMTOOLS_CACHE_ENABLED`, default: false.
  bool isCacheEnabled() {
    final v = getValue('DMTOOLS_CACHE_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether cache manager logging is enabled.
  /// Key: `CACHE_MANAGER_LOGGING_ENABLED`, default: false.
  bool isCacheManagerLoggingEnabled() {
    final v = getValue('CACHE_MANAGER_LOGGING_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether JS tool call logging is enabled.
  /// Key: `DMTOOLS_JS_LOG_TOOL_CALLS`, default: false.
  bool isJsToolCallLoggingEnabled() {
    final v = getValue('DMTOOLS_JS_LOG_TOOL_CALLS');
    return v != null && (v.toLowerCase() == 'true' || v == '1');
  }

  /// CLI full output log directory.
  /// Key: `DMTOOLS_CLI_LOG_DIR`, default: `.dmtools-logs/cli`.
  String getCliFullOutputLogDir() =>
      getValueWithDefault('DMTOOLS_CLI_LOG_DIR', '.dmtools-logs/cli');

  /// Sleep time between requests in ms.
  /// Key: `SLEEP_TIME_REQUEST`, default: 300. THROWS on invalid.
  int getSleepTimeRequest() {
    final v = getValue('SLEEP_TIME_REQUEST');
    if (v == null || v.isEmpty) return 300;
    return int.parse(v);
  }

  /// Whether to read PR diffs.
  /// Key: `IS_READ_PULL_REQUEST_DIFF`, default: true.
  bool isReadPullRequestDiff() {
    final v = getValue('IS_READ_PULL_REQUEST_DIFF');
    return v == null || v.toLowerCase() == 'true';
  }

  /// Max image dimension. Key: `IMAGE_MAX_DIMENSION`, default: 8000.
  /// THROWS on invalid.
  int getImageMaxDimension() =>
      int.parse(getValueWithDefault('IMAGE_MAX_DIMENSION', '8000'));

  /// JPEG quality for image processing.
  /// Key: `IMAGE_JPEG_QUALITY`, default: 0.9. THROWS on invalid.
  double getImageJpegQuality() =>
      double.parse(getValueWithDefault('IMAGE_JPEG_QUALITY', '0.9'));

  /// Default LLM type. Key: `DEFAULT_LLM`.
  String? getDefaultLLM() => getValue('DEFAULT_LLM');

  /// Default tracker type. Key: `DEFAULT_TRACKER`.
  String? getDefaultTracker() => getValue('DEFAULT_TRACKER');

  // --- Jira ---

  /// Base64-encoded Jira credentials from email+token, or pre-built token.
  ///
  /// If `JIRA_EMAIL` and `JIRA_API_TOKEN` are both set, returns
  /// `base64(email:token)`. Otherwise falls back to `JIRA_LOGIN_PASS_TOKEN`.
  String? getJiraLoginPassToken() {
    final email = getJiraEmail();
    final token = getJiraApiToken();
    if (email != null &&
        email.trim().isNotEmpty &&
        token != null &&
        token.trim().isNotEmpty) {
      final creds = '${email.trim()}:${token.trim()}';
      return base64Encode(utf8.encode(creds));
    }
    return getValue('JIRA_LOGIN_PASS_TOKEN');
  }

  /// Jira account email. Key: `JIRA_EMAIL`.
  String? getJiraEmail() => getValue('JIRA_EMAIL');

  /// Jira API token. Key: `JIRA_API_TOKEN`.
  String? getJiraApiToken() => getValue('JIRA_API_TOKEN');

  /// Jira REST API base path. Key: `JIRA_BASE_PATH`.
  String? getJiraBasePath() => getValue('JIRA_BASE_PATH');

  /// Jira auth type (e.g. Basic/Bearer). Key: `JIRA_AUTH_TYPE`.
  String? getJiraAuthType() => getValue('JIRA_AUTH_TYPE');

  /// Whether to wait before performing Jira operations.
  /// Key: `JIRA_WAIT_BEFORE_PERFORM`, default: false.
  bool isJiraWaitBeforePerform() {
    final v = getValue('JIRA_WAIT_BEFORE_PERFORM');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether Jira request logging is enabled.
  /// Key: `JIRA_LOGGING_ENABLED`, default: false.
  bool isJiraLoggingEnabled() {
    final v = getValue('JIRA_LOGGING_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether to clear Jira cache before operations.
  /// Key: `JIRA_CLEAR_CACHE`, default: false.
  bool isJiraClearCache() {
    final v = getValue('JIRA_CLEAR_CACHE');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether to transform custom field IDs to human names.
  /// Key: `JIRA_TRANSFORM_CUSTOM_FIELDS_TO_NAMES`, default: true.
  bool isJiraTransformCustomFieldsToNames() {
    final v = getValueWithDefault(
      'JIRA_TRANSFORM_CUSTOM_FIELDS_TO_NAMES',
      'true',
    );
    return v.toLowerCase() == 'true';
  }

  /// Extra fields project key. Key: `JIRA_EXTRA_FIELDS_PROJECT`, default: `TS`.
  String getJiraExtraFieldsProject() =>
      getValueWithDefault('JIRA_EXTRA_FIELDS_PROJECT', 'TS');

  /// Maximum search results. Key: `JIRA_MAX_SEARCH_RESULTS`, default: -1.
  int getJiraMaxSearchResults() {
    final v = getValue('JIRA_MAX_SEARCH_RESULTS');
    if (v == null || v.trim().isEmpty) return -1;
    return int.tryParse(v.trim()) ?? -1;
  }

  /// Extra Jira fields to fetch. Key: `JIRA_EXTRA_FIELDS`.
  List<String>? getJiraExtraFields() {
    final v = getValue('JIRA_EXTRA_FIELDS');
    return v == null ? null : v.split(',');
  }

  /// Uppercase immutable set from comma-separated `JIRA_ISSUE_IGNORE_PREFIXES`.
  Set<String> getJiraIssueIgnorePrefixes() =>
      _parseUpperSetExt(getValue('JIRA_ISSUE_IGNORE_PREFIXES'));

  /// Uppercase immutable set from comma-separated `JIRA_ISSUE_ALLOWED_PREFIXES`.
  Set<String> getJiraIssueAllowedPrefixes() =>
      _parseUpperSetExt(getValue('JIRA_ISSUE_ALLOWED_PREFIXES'));

  /// Story points field keys. Key: `DEFAULT_TICKET_STORY_POINTS_FIELDS`.
  /// Returns null if not set.
  List<String>? getDefaultTicketStoryPointsFields() {
    final v = getValue('DEFAULT_TICKET_STORY_POINTS_FIELDS');
    return v == null || v.isEmpty ? null : v.split(',');
  }

  /// Auto-detects story point field names from `JIRA_EXTRA_FIELDS` when
  /// `DEFAULT_TICKET_STORY_POINTS_FIELD_NAMES` is not set.
  List<String>? getDefaultTicketStoryPointsFieldHumanNames() {
    final explicit = getValue('DEFAULT_TICKET_STORY_POINTS_FIELD_NAMES');
    if (explicit != null && explicit.isNotEmpty) {
      return explicit.split(',');
    }
    final extraFields = getJiraExtraFields();
    if (extraFields != null) {
      final candidates = <String>[];
      for (final f in extraFields) {
        if (f.trim().toLowerCase().contains('story point')) {
          candidates.add(f.trim());
        }
      }
      if (candidates.isNotEmpty) return candidates;
    }
    return null;
  }

  // --- Xray ---

  /// Xray OAuth client ID. Key: `XRAY_CLIENT_ID`.
  String? getXrayClientId() => getValue('XRAY_CLIENT_ID');

  /// Xray OAuth client secret. Key: `XRAY_CLIENT_SECRET`.
  String? getXrayClientSecret() => getValue('XRAY_CLIENT_SECRET');

  /// Xray REST API base path. Key: `XRAY_BASE_PATH`.
  String? getXrayBasePath() => getValue('XRAY_BASE_PATH');

  /// Whether Xray POST request caching is enabled.
  /// Key: `XRAY_CACHE_POST_REQUESTS_ENABLED`, default: false.
  bool isXrayCachePostRequestsEnabled() {
    final v = getValue('XRAY_CACHE_POST_REQUESTS_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether Xray GET request caching is enabled.
  /// Key: `XRAY_CACHE_GET_REQUESTS_ENABLED`, default: false.
  bool isXrayCacheGetRequestsEnabled() {
    final v = getValue('XRAY_CACHE_GET_REQUESTS_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether Xray parallel fetch is enabled.
  /// Key: `XRAY_PARALLEL_FETCH_ENABLED`, default: false.
  bool isXrayParallelFetchEnabled() {
    final v = getValue('XRAY_PARALLEL_FETCH_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Whether Xray enrichment is enabled by default.
  /// Key: `XRAY_ENRICHMENT_ENABLED_BY_DEFAULT`, default: true.
  bool isXrayEnrichmentEnabledByDefault() {
    final v = getValue('XRAY_ENRICHMENT_ENABLED_BY_DEFAULT');
    return v == null || v.toLowerCase() == 'true';
  }

  /// Parallel batch size for Xray fetch.
  /// Key: `XRAY_PARALLEL_BATCH_SIZE`, default: 100.
  int getXrayParallelBatchSize() {
    final v = getValue('XRAY_PARALLEL_BATCH_SIZE');
    if (v == null || v.isEmpty) return 100;
    return int.tryParse(v) ?? 100;
  }

  /// Thread count for Xray parallel fetch.
  /// Key: `XRAY_PARALLEL_THREADS`, default: 2.
  int getXrayParallelThreads() {
    final v = getValue('XRAY_PARALLEL_THREADS');
    if (v == null || v.isEmpty) return 2;
    return int.tryParse(v) ?? 2;
  }

  /// Delay between parallel batches in ms.
  /// Key: `XRAY_PARALLEL_DELAY_MS`, default: 500.
  int getXrayParallelDelayMs() {
    final v = getValue('XRAY_PARALLEL_DELAY_MS');
    if (v == null || v.isEmpty) return 500;
    return int.tryParse(v) ?? 500;
  }

  // --- Confluence ---

  /// Confluence REST API base path. Key: `CONFLUENCE_BASE_PATH`.
  String? getConfluenceBasePath() => getValue('CONFLUENCE_BASE_PATH');

  /// Confluence credentials.
  ///
  /// If `CONFLUENCE_EMAIL` + `CONFLUENCE_API_TOKEN` are set: Bearer auth
  /// returns the raw token; Basic auth returns `base64(email:token)`.
  /// Otherwise falls back to `CONFLUENCE_LOGIN_PASS_TOKEN`.
  String? getConfluenceLoginPassToken() {
    final email = getConfluenceEmail();
    final token = getConfluenceApiToken();
    final authType = getConfluenceAuthType();
    if (email != null &&
        email.trim().isNotEmpty &&
        token != null &&
        token.trim().isNotEmpty) {
      if (authType.toLowerCase() == 'bearer') {
        return token.trim();
      }
      final creds = '${email.trim()}:${token.trim()}';
      return base64Encode(utf8.encode(creds));
    }
    return getValue('CONFLUENCE_LOGIN_PASS_TOKEN');
  }

  /// Confluence account email. Key: `CONFLUENCE_EMAIL`.
  String? getConfluenceEmail() => getValue('CONFLUENCE_EMAIL');

  /// Confluence API token. Key: `CONFLUENCE_API_TOKEN`.
  String? getConfluenceApiToken() => getValue('CONFLUENCE_API_TOKEN');

  /// Confluence auth type. Key: `CONFLUENCE_AUTH_TYPE`, default: `Basic`.
  String getConfluenceAuthType() {
    final v = getValue('CONFLUENCE_AUTH_TYPE');
    return v ?? 'Basic';
  }

  /// Confluence GraphQL endpoint path. Key: `CONFLUENCE_GRAPHQL_PATH`.
  String? getConfluenceGraphQLPath() => getValue('CONFLUENCE_GRAPHQL_PATH');

  /// Default Confluence space key. Key: `CONFLUENCE_DEFAULT_SPACE`.
  String? getConfluenceDefaultSpace() => getValue('CONFLUENCE_DEFAULT_SPACE');

  // --- ADO ---

  /// Azure DevOps organization. Key: `ADO_ORGANIZATION`.
  String? getAdoOrganization() => getValue('ADO_ORGANIZATION');

  /// Azure DevOps project. Key: `ADO_PROJECT`.
  String? getAdoProject() => getValue('ADO_PROJECT');

  /// Azure DevOps PAT token. Key: `ADO_PAT_TOKEN`.
  String? getAdoPatToken() => getValue('ADO_PAT_TOKEN');

  /// Azure DevOps REST API base path.
  /// Key: `ADO_BASE_PATH`, default: `https://dev.azure.com`.
  String getAdoBasePath() {
    final v = getValue('ADO_BASE_PATH');
    if (v == null || v.isEmpty) return 'https://dev.azure.com';
    return v;
  }

  // --- GitHub ---

  /// GitHub access token. Key: `SOURCE_GITHUB_TOKEN`.
  String? getGithubToken() => getValue('SOURCE_GITHUB_TOKEN');

  /// GitHub workspace path. Key: `SOURCE_GITHUB_WORKSPACE`.
  String? getGithubWorkspace() => getValue('SOURCE_GITHUB_WORKSPACE');

  /// GitHub repository (`owner/repo`). Key: `SOURCE_GITHUB_REPOSITORY`.
  String? getGithubRepository() => getValue('SOURCE_GITHUB_REPOSITORY');

  /// GitHub branch. Key: `SOURCE_GITHUB_BRANCH`.
  String? getGithubBranch() => getValue('SOURCE_GITHUB_BRANCH');

  /// GitHub API base path.
  /// Key: `SOURCE_GITHUB_BASE_PATH`, default: `https://api.github.com`.
  String getGithubBasePath() {
    final v = getValue('SOURCE_GITHUB_BASE_PATH');
    if (v == null || v.isEmpty) return 'https://api.github.com';
    return v;
  }

  // --- GitLab ---

  /// GitLab access token. Key: `GITLAB_TOKEN`.
  String? getGitLabToken() => getValue('GITLAB_TOKEN');

  /// GitLab workspace path. Key: `GITLAB_WORKSPACE`.
  String? getGitLabWorkspace() => getValue('GITLAB_WORKSPACE');

  /// GitLab repository. Key: `GITLAB_REPOSITORY`.
  String? getGitLabRepository() => getValue('GITLAB_REPOSITORY');

  /// GitLab branch. Key: `GITLAB_BRANCH`.
  String? getGitLabBranch() => getValue('GITLAB_BRANCH');

  /// GitLab API base path. Key: `GITLAB_BASE_PATH`.
  String? getGitLabBasePath() => getValue('GITLAB_BASE_PATH');

  // --- Bitbucket ---

  /// Bitbucket access token. Key: `BITBUCKET_TOKEN`.
  String? getBitbucketToken() => getValue('BITBUCKET_TOKEN');

  /// Bitbucket API version. Key: `BITBUCKET_API_VERSION`.
  String? getBitbucketApiVersion() => getValue('BITBUCKET_API_VERSION');

  /// Bitbucket workspace. Key: `BITBUCKET_WORKSPACE`.
  String? getBitbucketWorkspace() => getValue('BITBUCKET_WORKSPACE');

  /// Bitbucket repository. Key: `BITBUCKET_REPOSITORY`.
  String? getBitbucketRepository() => getValue('BITBUCKET_REPOSITORY');

  /// Bitbucket branch. Key: `BITBUCKET_BRANCH`.
  String? getBitbucketBranch() => getValue('BITBUCKET_BRANCH');

  /// Bitbucket API base path. Key: `BITBUCKET_BASE_PATH`.
  String? getBitbucketBasePath() => getValue('BITBUCKET_BASE_PATH');

  // --- Rally ---

  /// Rally API token. Key: `RALLY_TOKEN`.
  String? getRallyToken() => getValue('RALLY_TOKEN');

  /// Rally API path. Key: `RALLY_PATH`.
  String? getRallyPath() => getValue('RALLY_PATH');

  // --- Figma ---

  /// Figma REST API base path. Key: `FIGMA_BASE_PATH`.
  String? getFigmaBasePath() => getValue('FIGMA_BASE_PATH');

  /// Figma API key. Key: `FIGMA_TOKEN`.
  String? getFigmaApiKey() => getValue('FIGMA_TOKEN');

  /// Figma OAuth2 client ID. Key: `FIGMA_CLIENT_ID`.
  String? getFigmaClientId() => getValue('FIGMA_CLIENT_ID');

  /// Figma OAuth2 client secret. Key: `FIGMA_CLIENT_SECRET`.
  String? getFigmaClientSecret() => getValue('FIGMA_CLIENT_SECRET');

  /// Figma OAuth2 refresh token. Key: `FIGMA_OAUTH_REFRESH_TOKEN`.
  String? getFigmaOAuth2RefreshToken() => getValue('FIGMA_OAUTH_REFRESH_TOKEN');

  /// Figma OAuth2 access token. Key: `FIGMA_OAUTH_ACCESS_TOKEN`.
  String? getFigmaOAuth2AccessToken() => getValue('FIGMA_OAUTH_ACCESS_TOKEN');

  /// Figma OAuth2 scopes.
  ///
  /// Tries `FIGMA_SCOPE` first, falls back to `FIGMA_OAUTH_SCOPES`.
  String? getFigmaOAuth2Scopes() {
    final v = getValue('FIGMA_SCOPE');
    if (v != null && v.trim().isNotEmpty) return v;
    return getValue('FIGMA_OAUTH_SCOPES');
  }

  /// Figma OAuth2 redirect URI. Key: `FIGMA_REDIRECT_URI`.
  String? getFigmaRedirectUri() => getValue('FIGMA_REDIRECT_URI');

  // --- Teams / SharePoint ---

  /// Teams (Entra) app client ID. Key: `TEAMS_CLIENT_ID`.
  String? getTeamsClientId() => getValue('TEAMS_CLIENT_ID');

  /// Teams tenant ID. Key: `TEAMS_TENANT_ID`, default: `common`.
  String getTeamsTenantId() => getValueWithDefault('TEAMS_TENANT_ID', 'common');

  /// Teams OAuth scopes. Key: `TEAMS_SCOPES`.
  String getTeamsScopes() => getValueWithDefault(
        'TEAMS_SCOPES',
        'User.Read Chat.Read ChatMessage.Read Mail.Read '
            'Team.ReadBasic.All Channel.ReadBasic.All openid profile email '
            'offline_access',
      );

  /// Teams auth method. Key: `TEAMS_AUTH_METHOD`, default: `device`.
  String getTeamsAuthMethod() =>
      getValueWithDefault('TEAMS_AUTH_METHOD', 'device');

  /// Teams auth callback port. Key: `TEAMS_AUTH_PORT`, default: 8080.
  int getTeamsAuthPort() {
    final v = getValue('TEAMS_AUTH_PORT');
    if (v == null || v.trim().isEmpty) return 8080;
    return int.tryParse(v) ?? 8080;
  }

  /// Teams token cache file path.
  /// Key: `TEAMS_TOKEN_CACHE_PATH`, default: `./teams.token`.
  String getTeamsTokenCachePath() =>
      getValueWithDefault('TEAMS_TOKEN_CACHE_PATH', './teams.token');

  /// Teams refresh token. Key: `TEAMS_REFRESH_TOKEN`.
  String? getTeamsRefreshToken() => getValue('TEAMS_REFRESH_TOKEN');

  /// Microsoft Graph API base path.
  /// Key: `TEAMS_BASE_PATH`, default: `https://graph.microsoft.com/v1.0`.
  String getTeamsBasePath() => getValueWithDefault(
        'TEAMS_BASE_PATH',
        'https://graph.microsoft.com/v1.0',
      );

  /// SharePoint OAuth scopes. Key: `SHAREPOINT_SCOPES`.
  String getSharePointScopes() => getValueWithDefault(
        'SHAREPOINT_SCOPES',
        'User.Read Chat.Read ChatMessage.Read Mail.Read '
            'Team.ReadBasic.All Channel.ReadBasic.All Files.Read.All '
            'Sites.Read.All openid profile email offline_access',
      );

  // --- TestRail ---

  /// TestRail REST API base path. Key: `TESTRAIL_BASE_PATH`.
  String? getTestRailBasePath() => getValue('TESTRAIL_BASE_PATH');

  /// TestRail username. Key: `TESTRAIL_USERNAME`.
  String? getTestRailUsername() => getValue('TESTRAIL_USERNAME');

  /// TestRail API key. Key: `TESTRAIL_API_KEY`.
  String? getTestRailApiKey() => getValue('TESTRAIL_API_KEY');

  /// TestRail project name. Key: `TESTRAIL_PROJECT`.
  String? getTestRailProject() => getValue('TESTRAIL_PROJECT');

  /// Whether TestRail request logging is enabled.
  /// Key: `TESTRAIL_LOGGING_ENABLED`, default: false.
  bool isTestRailLoggingEnabled() {
    final v = getValue('TESTRAIL_LOGGING_ENABLED');
    return v != null && v.toLowerCase() == 'true';
  }

  /// Default TestRail text format.
  /// Key: `TESTRAIL_DEFAULT_FORMAT`, default: `html`.
  String getTestRailDefaultFormat() {
    final v = getValue('TESTRAIL_DEFAULT_FORMAT');
    return (v == null || v.trim().isEmpty) ? 'html' : v;
  }

  // --- Bitrise / Jenkins ---

  /// Bitrise access token. Key: `BITRISE_TOKEN`.
  String? getBitriseToken() => getValue('BITRISE_TOKEN');

  /// Bitrise API base path.
  /// Key: `BITRISE_BASE_PATH`, default: `https://api.bitrise.io/v0.1`.
  String getBitriseBasePath() {
    final v = getValue('BITRISE_BASE_PATH');
    if (v == null || v.isEmpty) return 'https://api.bitrise.io/v0.1';
    return v;
  }

  /// Bitrise app slug. Key: `BITRISE_APP_SLUG`.
  String? getBitriseAppSlug() => getValue('BITRISE_APP_SLUG');

  /// Jenkins base path.
  /// Key: `JENKINS_BASE_PATH`, default: `http://localhost:8080`.
  String getJenkinsBasePath() {
    final v = getValue('JENKINS_BASE_PATH');
    if (v == null || v.isEmpty) return 'http://localhost:8080';
    return v;
  }

  /// Jenkins username. Key: `JENKINS_USER`.
  String? getJenkinsUser() => getValue('JENKINS_USER');

  /// Jenkins API token. Key: `JENKINS_API_TOKEN`.
  String? getJenkinsApiToken() => getValue('JENKINS_API_TOKEN');
}
