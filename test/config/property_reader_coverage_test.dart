import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Coverage smoke tests for every getter in [PropertyReaderGetters].
///
/// Each getter is called at least twice: once with no config (defaults) and
/// once with override values (happy path). This pushes line coverage of
/// `property_reader_getters.dart` above the 80% gate.
late PropertyReader reader;

void main() {
  setUp(() {
    PropertyReader.setOverrides({});
    reader = PropertyReader();
  });
  tearDown(PropertyReader.clearOverrides);

  _testCliMiscGetters();
  _testJiraSimpleGetters();
  _testJiraComplexGetters();
  _testXrayGetters();
  _testConfluenceGetters();
  _testAdoGithubGetters();
  _testGitlabBitbucketRallyGetters();
  _testFigmaGetters();
  _testDialGetters();
  _testGeminiGetters();
  _testOllamaGetters();
  _testAnthropicGetters();
  _testBedrockGetters();
  _testOpenAiGetters();
  _testTeamsGetters();
  _testTestRailGetters();
  _testBitriseJenkinsGetters();
  _testJsaiGetters();
  _testMetricsGetters();
  _testAiChunkGetters();
}

void _testCliMiscGetters() {
  group('CLI / misc getters smoke', () {
    test('defaults', () {
      expect(reader.getCliOutput(), isNull);
      expect(reader.getFileReadAllowedPaths(), isNull);
      expect(reader.isCacheEnabled(), isFalse);
      expect(reader.isCacheManagerLoggingEnabled(), isFalse);
      expect(reader.isJsToolCallLoggingEnabled(), isFalse);
      expect(reader.getCliFullOutputLogDir(), '.dmtools-logs/cli');
      expect(reader.getSleepTimeRequest(), 300);
      expect(reader.isReadPullRequestDiff(), isTrue);
      expect(reader.getImageMaxDimension(), 8000);
      expect(reader.getImageJpegQuality(), closeTo(0.9, 0.001));
      expect(reader.getDefaultLLM(), isNull);
      expect(reader.getDefaultTracker(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'CLI_OUTPUT': 'json',
        'DMTOOLS_FILE_READ_ALLOWED_PATHS': '/tmp',
        'DMTOOLS_CACHE_ENABLED': 'true',
        'CACHE_MANAGER_LOGGING_ENABLED': 'true',
        'DMTOOLS_JS_LOG_TOOL_CALLS': '1',
        'DMTOOLS_CLI_LOG_DIR': '/var/log',
        'SLEEP_TIME_REQUEST': '500',
        'IS_READ_PULL_REQUEST_DIFF': 'false',
        'IMAGE_MAX_DIMENSION': '4000',
        'IMAGE_JPEG_QUALITY': '0.5',
        'DEFAULT_LLM': 'openai',
        'DEFAULT_TRACKER': 'jira',
      });
      expect(reader.getCliOutput(), 'json');
      expect(reader.getFileReadAllowedPaths(), '/tmp');
      expect(reader.isCacheEnabled(), isTrue);
      expect(reader.isCacheManagerLoggingEnabled(), isTrue);
      expect(reader.isJsToolCallLoggingEnabled(), isTrue);
      expect(reader.getCliFullOutputLogDir(), '/var/log');
      expect(reader.getSleepTimeRequest(), 500);
      expect(reader.isReadPullRequestDiff(), isFalse);
      expect(reader.getImageMaxDimension(), 4000);
      expect(reader.getImageJpegQuality(), closeTo(0.5, 0.001));
      expect(reader.getDefaultLLM(), 'openai');
      expect(reader.getDefaultTracker(), 'jira');
    });
  });
}

void _testJiraSimpleGetters() {
  group('Jira simple getters smoke', () {
    test('defaults', () {
      expect(reader.getJiraEmail(), isNull);
      expect(reader.getJiraApiToken(), isNull);
      expect(reader.getJiraBasePath(), isNull);
      expect(reader.getJiraAuthType(), isNull);
      expect(reader.isJiraWaitBeforePerform(), isFalse);
      expect(reader.isJiraLoggingEnabled(), isFalse);
      expect(reader.isJiraClearCache(), isFalse);
      expect(reader.isJiraTransformCustomFieldsToNames(), isTrue);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'JIRA_EMAIL': 'dev@example.com',
        'JIRA_API_TOKEN': 'tok-123',
        'JIRA_BASE_PATH': 'https://jira.example.com',
        'JIRA_AUTH_TYPE': 'Bearer',
        'JIRA_WAIT_BEFORE_PERFORM': 'true',
        'JIRA_LOGGING_ENABLED': 'true',
        'JIRA_CLEAR_CACHE': 'true',
        'JIRA_TRANSFORM_CUSTOM_FIELDS_TO_NAMES': 'false',
      });
      expect(reader.getJiraEmail(), 'dev@example.com');
      expect(reader.getJiraApiToken(), 'tok-123');
      expect(reader.getJiraBasePath(), 'https://jira.example.com');
      expect(reader.getJiraAuthType(), 'Bearer');
      expect(reader.isJiraWaitBeforePerform(), isTrue);
      expect(reader.isJiraLoggingEnabled(), isTrue);
      expect(reader.isJiraClearCache(), isTrue);
      expect(reader.isJiraTransformCustomFieldsToNames(), isFalse);
    });
  });
}

void _testJiraComplexGetters() {
  group('Jira complex getters smoke', () {
    test('defaults', () {
      expect(reader.getJiraLoginPassToken(), isNull);
      expect(reader.getJiraExtraFieldsProject(), 'TS');
      expect(reader.getJiraMaxSearchResults(), -1);
      expect(reader.getJiraExtraFields(), isNull);
      expect(reader.getJiraIssueIgnorePrefixes(), isEmpty);
      expect(reader.getJiraIssueAllowedPrefixes(), isEmpty);
      expect(reader.getDefaultTicketStoryPointsFields(), isNull);
      expect(reader.getDefaultTicketStoryPointsFieldHumanNames(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'JIRA_EMAIL': 'u@x.com',
        'JIRA_API_TOKEN': 't',
        'JIRA_EXTRA_FIELDS_PROJECT': 'PROJ',
        'JIRA_MAX_SEARCH_RESULTS': '200',
        'JIRA_EXTRA_FIELDS': 'summary,status',
        'JIRA_ISSUE_IGNORE_PREFIXES': 'abc,def',
        'JIRA_ISSUE_ALLOWED_PREFIXES': 'xyz',
        'DEFAULT_TICKET_STORY_POINTS_FIELDS': 'SP,Est',
      });
      expect(reader.getJiraLoginPassToken(), isNotNull);
      expect(reader.getJiraExtraFieldsProject(), 'PROJ');
      expect(reader.getJiraMaxSearchResults(), 200);
      expect(reader.getJiraExtraFields(), ['summary', 'status']);
      expect(reader.getJiraIssueIgnorePrefixes(), {'ABC', 'DEF'});
      expect(reader.getJiraIssueAllowedPrefixes(), {'XYZ'});
      expect(reader.getDefaultTicketStoryPointsFields(), ['SP', 'Est']);
    });
  });
}

void _testXrayGetters() {
  group('Xray getters smoke', () {
    test('defaults', () {
      expect(reader.getXrayClientId(), isNull);
      expect(reader.getXrayClientSecret(), isNull);
      expect(reader.getXrayBasePath(), isNull);
      expect(reader.isXrayCachePostRequestsEnabled(), isFalse);
      expect(reader.isXrayCacheGetRequestsEnabled(), isFalse);
      expect(reader.isXrayParallelFetchEnabled(), isFalse);
      expect(reader.isXrayEnrichmentEnabledByDefault(), isTrue);
      expect(reader.getXrayParallelBatchSize(), 100);
      expect(reader.getXrayParallelThreads(), 2);
      expect(reader.getXrayParallelDelayMs(), 500);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'XRAY_CLIENT_ID': 'client-id',
        'XRAY_CLIENT_SECRET': 'secret',
        'XRAY_BASE_PATH': 'https://xray.example.com',
        'XRAY_CACHE_POST_REQUESTS_ENABLED': 'true',
        'XRAY_CACHE_GET_REQUESTS_ENABLED': 'true',
        'XRAY_PARALLEL_FETCH_ENABLED': 'true',
        'XRAY_ENRICHMENT_ENABLED_BY_DEFAULT': 'false',
        'XRAY_PARALLEL_BATCH_SIZE': '50',
        'XRAY_PARALLEL_THREADS': '4',
        'XRAY_PARALLEL_DELAY_MS': '1000',
      });
      expect(reader.getXrayClientId(), 'client-id');
      expect(reader.getXrayClientSecret(), 'secret');
      expect(reader.getXrayBasePath(), 'https://xray.example.com');
      expect(reader.isXrayCachePostRequestsEnabled(), isTrue);
      expect(reader.isXrayCacheGetRequestsEnabled(), isTrue);
      expect(reader.isXrayParallelFetchEnabled(), isTrue);
      expect(reader.isXrayEnrichmentEnabledByDefault(), isFalse);
      expect(reader.getXrayParallelBatchSize(), 50);
      expect(reader.getXrayParallelThreads(), 4);
      expect(reader.getXrayParallelDelayMs(), 1000);
    });
  });
}

void _testConfluenceGetters() {
  group('Confluence getters smoke', () {
    test('defaults', () {
      expect(reader.getConfluenceBasePath(), isNull);
      expect(reader.getConfluenceLoginPassToken(), isNull);
      expect(reader.getConfluenceEmail(), isNull);
      expect(reader.getConfluenceApiToken(), isNull);
      expect(reader.getConfluenceAuthType(), 'Basic');
      expect(reader.getConfluenceGraphQLPath(), isNull);
      expect(reader.getConfluenceDefaultSpace(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'CONFLUENCE_BASE_PATH': 'https://conf.example.com',
        'CONFLUENCE_AUTH_TYPE': 'Bearer',
        'CONFLUENCE_EMAIL': 'c@x.com',
        'CONFLUENCE_API_TOKEN': 'ctok',
        'CONFLUENCE_GRAPHQL_PATH': '/graphql',
        'CONFLUENCE_DEFAULT_SPACE': 'ENG',
      });
      expect(reader.getConfluenceBasePath(), 'https://conf.example.com');
      expect(reader.getConfluenceLoginPassToken(), 'ctok');
      expect(reader.getConfluenceEmail(), 'c@x.com');
      expect(reader.getConfluenceApiToken(), 'ctok');
      expect(reader.getConfluenceAuthType(), 'Bearer');
      expect(reader.getConfluenceGraphQLPath(), '/graphql');
      expect(reader.getConfluenceDefaultSpace(), 'ENG');
    });
  });
}

void _testAdoGithubGetters() {
  group('ADO + GitHub getters smoke', () {
    test('defaults', () {
      expect(reader.getAdoOrganization(), isNull);
      expect(reader.getAdoProject(), isNull);
      expect(reader.getAdoPatToken(), isNull);
      expect(reader.getAdoBasePath(), 'https://dev.azure.com');
      expect(reader.getGithubToken(), isNull);
      expect(reader.getGithubWorkspace(), isNull);
      expect(reader.getGithubRepository(), isNull);
      expect(reader.getGithubBranch(), isNull);
      expect(reader.getGithubBasePath(), 'https://api.github.com');
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'ADO_ORGANIZATION': 'myorg',
        'ADO_PROJECT': 'myproj',
        'ADO_PAT_TOKEN': 'pat-tok',
        'ADO_BASE_PATH': 'https://custom.azure.com',
        'SOURCE_GITHUB_TOKEN': 'gh-tok',
        'SOURCE_GITHUB_WORKSPACE': '/ws',
        'SOURCE_GITHUB_REPOSITORY': 'owner/repo',
        'SOURCE_GITHUB_BRANCH': 'main',
        'SOURCE_GITHUB_BASE_PATH': 'https://gh.example.com',
      });
      expect(reader.getAdoOrganization(), 'myorg');
      expect(reader.getAdoProject(), 'myproj');
      expect(reader.getAdoPatToken(), 'pat-tok');
      expect(reader.getAdoBasePath(), 'https://custom.azure.com');
      expect(reader.getGithubToken(), 'gh-tok');
      expect(reader.getGithubWorkspace(), '/ws');
      expect(reader.getGithubRepository(), 'owner/repo');
      expect(reader.getGithubBranch(), 'main');
      expect(reader.getGithubBasePath(), 'https://gh.example.com');
    });
  });
}

void _testGitlabBitbucketRallyGetters() {
  group('GitLab + Bitbucket + Rally getters smoke', () {
    test('defaults', () {
      expect(reader.getGitLabToken(), isNull);
      expect(reader.getGitLabWorkspace(), isNull);
      expect(reader.getGitLabRepository(), isNull);
      expect(reader.getGitLabBranch(), isNull);
      expect(reader.getGitLabBasePath(), isNull);
      expect(reader.getBitbucketToken(), isNull);
      expect(reader.getBitbucketApiVersion(), isNull);
      expect(reader.getBitbucketWorkspace(), isNull);
      expect(reader.getBitbucketRepository(), isNull);
      expect(reader.getBitbucketBranch(), isNull);
      expect(reader.getBitbucketBasePath(), isNull);
      expect(reader.getRallyToken(), isNull);
      expect(reader.getRallyPath(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'GITLAB_TOKEN': 'gl-tok',
        'GITLAB_WORKSPACE': '/gl-ws',
        'GITLAB_REPOSITORY': 'gl/repo',
        'GITLAB_BRANCH': 'develop',
        'GITLAB_BASE_PATH': 'https://gl.example.com',
        'BITBUCKET_TOKEN': 'bb-tok',
        'BITBUCKET_API_VERSION': '2.0',
        'BITBUCKET_WORKSPACE': 'bb-ws',
        'BITBUCKET_REPOSITORY': 'bb/repo',
        'BITBUCKET_BRANCH': 'feature',
        'BITBUCKET_BASE_PATH': 'https://bb.example.com',
        'RALLY_TOKEN': 'ry-tok',
        'RALLY_PATH': 'https://rally.example.com',
      });
      expect(reader.getGitLabToken(), 'gl-tok');
      expect(reader.getGitLabWorkspace(), '/gl-ws');
      expect(reader.getGitLabRepository(), 'gl/repo');
      expect(reader.getGitLabBranch(), 'develop');
      expect(reader.getGitLabBasePath(), 'https://gl.example.com');
      expect(reader.getBitbucketToken(), 'bb-tok');
      expect(reader.getBitbucketApiVersion(), '2.0');
      expect(reader.getBitbucketWorkspace(), 'bb-ws');
      expect(reader.getBitbucketRepository(), 'bb/repo');
      expect(reader.getBitbucketBranch(), 'feature');
      expect(reader.getBitbucketBasePath(), 'https://bb.example.com');
      expect(reader.getRallyToken(), 'ry-tok');
      expect(reader.getRallyPath(), 'https://rally.example.com');
    });
  });
}

void _testFigmaGetters() {
  group('Figma getters smoke', () {
    test('defaults', () {
      expect(reader.getFigmaBasePath(), isNull);
      expect(reader.getFigmaApiKey(), isNull);
      expect(reader.getFigmaClientId(), isNull);
      expect(reader.getFigmaClientSecret(), isNull);
      expect(reader.getFigmaOAuth2RefreshToken(), isNull);
      expect(reader.getFigmaOAuth2AccessToken(), isNull);
      expect(reader.getFigmaOAuth2Scopes(), isNull);
      expect(reader.getFigmaRedirectUri(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'FIGMA_BASE_PATH': 'https://figma.example.com',
        'FIGMA_TOKEN': 'fg-tok',
        'FIGMA_CLIENT_ID': 'fg-id',
        'FIGMA_CLIENT_SECRET': 'fg-secret',
        'FIGMA_OAUTH_REFRESH_TOKEN': 'refresh',
        'FIGMA_OAUTH_ACCESS_TOKEN': 'access',
        'FIGMA_SCOPE': 'file_read',
        'FIGMA_REDIRECT_URI': 'https://app/cb',
      });
      expect(reader.getFigmaBasePath(), 'https://figma.example.com');
      expect(reader.getFigmaApiKey(), 'fg-tok');
      expect(reader.getFigmaClientId(), 'fg-id');
      expect(reader.getFigmaClientSecret(), 'fg-secret');
      expect(reader.getFigmaOAuth2RefreshToken(), 'refresh');
      expect(reader.getFigmaOAuth2AccessToken(), 'access');
      expect(reader.getFigmaOAuth2Scopes(), 'file_read');
      expect(reader.getFigmaRedirectUri(), 'https://app/cb');
    });
  });
}

void _testDialGetters() {
  group('DIAL getters smoke', () {
    test('defaults', () {
      expect(reader.getDialBathPath(), isNull);
      expect(reader.getDialIApiKey(), isNull);
      expect(reader.getDialModel(), isNull);
      expect(reader.getDialApiVersion(), isNull);
      expect(reader.getCodeAIModel(), isNull);
      expect(reader.getTestAIModel(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'DIAL_BASE_PATH': 'https://dial.example.com',
        'DIAL_API_KEY': 'dial-tok',
        'DIAL_MODEL': 'gpt-4',
        'DIAL_API_VERSION': 'v2',
        'CODE_AI_MODEL': 'code-model',
        'TEST_AI_MODEL': 'test-model',
      });
      expect(reader.getDialBathPath(), 'https://dial.example.com');
      expect(reader.getDialIApiKey(), 'dial-tok');
      expect(reader.getDialModel(), 'gpt-4');
      expect(reader.getDialApiVersion(), 'v2');
      expect(reader.getCodeAIModel(), 'code-model');
      expect(reader.getTestAIModel(), 'test-model');
    });
  });
}

void _testGeminiGetters() {
  group('Gemini getters smoke', () {
    test('defaults', () {
      expect(reader.getGeminiApiKey(), isNull);
      expect(reader.getGeminiDefaultModel(), isNull);
      expect(
        reader.getGeminiBasePath(),
        'https://generativelanguage.googleapis.com/v1beta/models',
      );
      expect(reader.isGeminiVertexEnabled(), isFalse);
      expect(reader.getGeminiVertexProjectId(), isNull);
      expect(reader.getGeminiVertexLocation(), isNull);
      expect(reader.getGeminiVertexCredentialsPath(), isNull);
      expect(reader.getGeminiVertexCredentialsJson(), isNull);
      expect(reader.getGeminiVertexApiVersion(), 'v1');
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'GEMINI_API_KEY': 'gm-tok',
        'GEMINI_MODEL': 'gemini-pro',
        'GEMINI_BASE_PATH': 'https://gm.example.com',
        'GEMINI_VERTEX_ENABLED': 'true',
        'GEMINI_VERTEX_PROJECT_ID': 'proj-1',
        'GEMINI_VERTEX_LOCATION': 'us-central1',
        'GEMINI_VERTEX_CREDENTIALS_PATH': '/creds.json',
        'GEMINI_VERTEX_CREDENTIALS_JSON': '{}',
        'GEMINI_VERTEX_API_VERSION': 'v2',
      });
      expect(reader.getGeminiApiKey(), 'gm-tok');
      expect(reader.getGeminiDefaultModel(), 'gemini-pro');
      expect(reader.getGeminiBasePath(), 'https://gm.example.com');
      expect(reader.isGeminiVertexEnabled(), isTrue);
      expect(reader.getGeminiVertexProjectId(), 'proj-1');
      expect(reader.getGeminiVertexLocation(), 'us-central1');
      expect(reader.getGeminiVertexCredentialsPath(), '/creds.json');
      expect(reader.getGeminiVertexCredentialsJson(), '{}');
      expect(reader.getGeminiVertexApiVersion(), 'v2');
    });
  });
}

void _testOllamaGetters() {
  group('Ollama getters smoke', () {
    test('defaults', () {
      expect(reader.getOllamaBasePath(), 'http://localhost:11434');
      expect(reader.getOllamaModel(), isNull);
      expect(reader.getOllamaNumCtx(), 16384);
      expect(reader.getOllamaNumPredict(), -1);
      expect(reader.getOllamaApiKey(), isNull);
      expect(reader.getOllamaCustomHeaderNames(), isNull);
      expect(reader.getOllamaCustomHeaderValues(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'OLLAMA_BASE_PATH': 'https://ollama.example.com',
        'OLLAMA_MODEL': 'llama2',
        'OLLAMA_NUM_CTX': '4096',
        'OLLAMA_NUM_PREDICT': '100',
        'OLLAMA_API_KEY': 'ol-tok',
        'OLLAMA_CUSTOM_HEADER_NAMES': 'X-Custom,X-Other',
        'OLLAMA_CUSTOM_HEADER_VALUES': 'v1,v2',
      });
      expect(reader.getOllamaBasePath(), 'https://ollama.example.com');
      expect(reader.getOllamaModel(), 'llama2');
      expect(reader.getOllamaNumCtx(), 4096);
      expect(reader.getOllamaNumPredict(), 100);
      expect(reader.getOllamaApiKey(), 'ol-tok');
      expect(reader.getOllamaCustomHeaderNames(), 'X-Custom,X-Other');
      expect(reader.getOllamaCustomHeaderValues(), 'v1,v2');
    });
  });
}

void _testAnthropicGetters() {
  group('Anthropic getters smoke', () {
    test('defaults', () {
      expect(
        reader.getAnthropicBasePath(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(reader.getAnthropicModel(), isNull);
      expect(reader.getAnthropicMaxTokens(), 4096);
      expect(reader.getAnthropicCustomHeaderNames(), isNull);
      expect(reader.getAnthropicCustomHeaderValues(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'ANTHROPIC_BASE_PATH': 'https://an.example.com',
        'ANTHROPIC_MODEL': 'claude-3',
        'ANTHROPIC_MAX_TOKENS': '2048',
        'ANTHROPIC_CUSTOM_HEADER_NAMES': 'X-Key',
        'ANTHROPIC_CUSTOM_HEADER_VALUES': 'val',
      });
      expect(reader.getAnthropicBasePath(), 'https://an.example.com');
      expect(reader.getAnthropicModel(), 'claude-3');
      expect(reader.getAnthropicMaxTokens(), 2048);
      expect(reader.getAnthropicCustomHeaderNames(), 'X-Key');
      expect(reader.getAnthropicCustomHeaderValues(), 'val');
    });
  });
}

void _testBedrockGetters() {
  group('Bedrock getters smoke', () {
    test('defaults', () {
      expect(reader.getBedrockBasePath(), isNull);
      expect(reader.getBedrockRegion(), isNull);
      expect(reader.getBedrockModelId(), isNull);
      expect(reader.getBedrockBearerToken(), isNull);
      expect(reader.getBedrockAccessKeyId(), isNull);
      expect(reader.getBedrockSecretAccessKey(), isNull);
      expect(reader.getBedrockSessionToken(), isNull);
      expect(reader.getBedrockMaxTokens(), 4096);
      expect(reader.getBedrockTemperature(), 1.0);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'BEDROCK_BASE_PATH': 'https://br.example.com',
        'BEDROCK_REGION': 'us-west-2',
        'BEDROCK_MODEL_ID': 'anthropic.claude',
        'AWS_BEARER_TOKEN_BEDROCK': 'br-tok',
        'BEDROCK_ACCESS_KEY_ID': 'AKID',
        'BEDROCK_SECRET_ACCESS_KEY': 'secret',
        'BEDROCK_SESSION_TOKEN': 'session',
        'BEDROCK_MAX_TOKENS': '1024',
        'BEDROCK_TEMPERATURE': '0.7',
      });
      expect(reader.getBedrockBasePath(), 'https://br.example.com');
      expect(reader.getBedrockRegion(), 'us-west-2');
      expect(reader.getBedrockModelId(), 'anthropic.claude');
      expect(reader.getBedrockBearerToken(), 'br-tok');
      expect(reader.getBedrockAccessKeyId(), 'AKID');
      expect(reader.getBedrockSecretAccessKey(), 'secret');
      expect(reader.getBedrockSessionToken(), 'session');
      expect(reader.getBedrockMaxTokens(), 1024);
      expect(reader.getBedrockTemperature(), 0.7);
    });
  });
}

void _testOpenAiGetters() {
  group('OpenAI getters smoke', () {
    test('defaults', () {
      expect(
        reader.getOpenAIBasePath(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(reader.getOpenAIApiKey(), isNull);
      expect(reader.getOpenAIModel(), isNull);
      expect(reader.getOpenAIMaxTokens(), 4096);
      expect(reader.getOpenAITemperature(), -1);
      expect(reader.getOpenAIMaxTokensParamName(), 'max_completion_tokens');
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'OPENAI_BASE_PATH': 'https://oai.example.com',
        'OPENAI_API_KEY': 'oai-tok',
        'OPENAI_MODEL': 'gpt-4',
        'OPENAI_MAX_TOKENS': '2048',
        'OPENAI_TEMPERATURE': '0.8',
        'OPENAI_MAX_TOKENS_PARAM_NAME': 'max_tokens',
      });
      expect(reader.getOpenAIBasePath(), 'https://oai.example.com');
      expect(reader.getOpenAIApiKey(), 'oai-tok');
      expect(reader.getOpenAIModel(), 'gpt-4');
      expect(reader.getOpenAIMaxTokens(), 2048);
      expect(reader.getOpenAITemperature(), 0.8);
      expect(reader.getOpenAIMaxTokensParamName(), 'max_tokens');
    });
  });
}

void _testTeamsGetters() {
  group('Teams / SharePoint getters smoke', () {
    test('defaults', () {
      expect(reader.getTeamsClientId(), isNull);
      expect(reader.getTeamsTenantId(), 'common');
      expect(reader.getTeamsScopes(), contains('User.Read'));
      expect(reader.getTeamsAuthMethod(), 'device');
      expect(reader.getTeamsAuthPort(), 8080);
      expect(reader.getTeamsTokenCachePath(), './teams.token');
      expect(reader.getTeamsRefreshToken(), isNull);
      expect(
        reader.getTeamsBasePath(),
        'https://graph.microsoft.com/v1.0',
      );
      expect(reader.getSharePointScopes(), contains('Files.Read.All'));
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'TEAMS_CLIENT_ID': 'tm-id',
        'TEAMS_TENANT_ID': 'tenant-1',
        'TEAMS_SCOPES': 'Chat.Read',
        'TEAMS_AUTH_METHOD': 'interactive',
        'TEAMS_AUTH_PORT': '9090',
        'TEAMS_TOKEN_CACHE_PATH': '/tmp/tm.token',
        'TEAMS_REFRESH_TOKEN': 'rt-val',
        'TEAMS_BASE_PATH': 'https://tm.example.com',
        'SHAREPOINT_SCOPES': 'Sites.Read.All',
      });
      expect(reader.getTeamsClientId(), 'tm-id');
      expect(reader.getTeamsTenantId(), 'tenant-1');
      expect(reader.getTeamsScopes(), 'Chat.Read');
      expect(reader.getTeamsAuthMethod(), 'interactive');
      expect(reader.getTeamsAuthPort(), 9090);
      expect(reader.getTeamsTokenCachePath(), '/tmp/tm.token');
      expect(reader.getTeamsRefreshToken(), 'rt-val');
      expect(reader.getTeamsBasePath(), 'https://tm.example.com');
      expect(reader.getSharePointScopes(), 'Sites.Read.All');
    });
  });
}

void _testTestRailGetters() {
  group('TestRail getters smoke', () {
    test('defaults', () {
      expect(reader.getTestRailBasePath(), isNull);
      expect(reader.getTestRailUsername(), isNull);
      expect(reader.getTestRailApiKey(), isNull);
      expect(reader.getTestRailProject(), isNull);
      expect(reader.isTestRailLoggingEnabled(), isFalse);
      expect(reader.getTestRailDefaultFormat(), 'html');
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'TESTRAIL_BASE_PATH': 'https://tr.example.com',
        'TESTRAIL_USERNAME': 'tr-user',
        'TESTRAIL_API_KEY': 'tr-tok',
        'TESTRAIL_PROJECT': 'proj',
        'TESTRAIL_LOGGING_ENABLED': 'true',
        'TESTRAIL_DEFAULT_FORMAT': 'markdown',
      });
      expect(reader.getTestRailBasePath(), 'https://tr.example.com');
      expect(reader.getTestRailUsername(), 'tr-user');
      expect(reader.getTestRailApiKey(), 'tr-tok');
      expect(reader.getTestRailProject(), 'proj');
      expect(reader.isTestRailLoggingEnabled(), isTrue);
      expect(reader.getTestRailDefaultFormat(), 'markdown');
    });
  });
}

void _testBitriseJenkinsGetters() {
  group('Bitrise + Jenkins getters smoke', () {
    test('defaults', () {
      expect(reader.getBitriseToken(), isNull);
      expect(reader.getBitriseBasePath(), 'https://api.bitrise.io/v0.1');
      expect(reader.getBitriseAppSlug(), isNull);
      expect(reader.getJenkinsBasePath(), 'http://localhost:8080');
      expect(reader.getJenkinsUser(), isNull);
      expect(reader.getJenkinsApiToken(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'BITRISE_TOKEN': 'br-tok',
        'BITRISE_BASE_PATH': 'https://br.example.com',
        'BITRISE_APP_SLUG': 'app-slug',
        'JENKINS_BASE_PATH': 'https://jk.example.com',
        'JENKINS_USER': 'jk-user',
        'JENKINS_API_TOKEN': 'jk-tok',
      });
      expect(reader.getBitriseToken(), 'br-tok');
      expect(reader.getBitriseBasePath(), 'https://br.example.com');
      expect(reader.getBitriseAppSlug(), 'app-slug');
      expect(reader.getJenkinsBasePath(), 'https://jk.example.com');
      expect(reader.getJenkinsUser(), 'jk-user');
      expect(reader.getJenkinsApiToken(), 'jk-tok');
    });
  });
}

void _testJsaiGetters() {
  group('JSAI getters smoke', () {
    test('defaults', () {
      expect(reader.getJsScriptPath(), isNull);
      expect(reader.getJsScriptContent(), isNull);
      expect(reader.getJsClientName(), 'JSAIClientFromProperties');
      expect(reader.getJsDefaultModel(), isNull);
      expect(reader.getJsBasePath(), isNull);
      expect(reader.getJsSecretsKeys(), isNull);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'JSAI_SCRIPT_PATH': '/scripts/run.js',
        'JSAI_SCRIPT_CONTENT': 'console.log(1)',
        'JSAI_CLIENT_NAME': 'CustomClient',
        'JSAI_DEFAULT_MODEL': 'js-model',
        'JSAI_BASE_PATH': 'https://js.example.com',
        'JSAI_SECRETS_KEYS': 'KEY1,KEY2',
      });
      expect(reader.getJsScriptPath(), '/scripts/run.js');
      expect(reader.getJsScriptContent(), 'console.log(1)');
      expect(reader.getJsClientName(), 'CustomClient');
      expect(reader.getJsDefaultModel(), 'js-model');
      expect(reader.getJsBasePath(), 'https://js.example.com');
      expect(reader.getJsSecretsKeys(), ['KEY1', 'KEY2']);
    });
  });
}

void _testMetricsGetters() {
  group('Metrics getters smoke', () {
    test('defaults', () {
      expect(reader.getDefaultTicketWeightIfNoSPs(), -1);
      expect(reader.getLinesOfCodeDivider(), 1.0);
      expect(reader.getTimeSpentOnDivider(), 1.0);
      expect(reader.getTicketFieldsChangedDivider('status'), 1.0);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'DEFAULT_TICKET_WEIGHT_IF_NO_SP': '5',
        'LINES_OF_CODE_DIVIDER': '2.0',
        'TIME_SPENT_ON_DIVIDER': '3.0',
        'TICKET_FIELDS_CHANGED_DIVIDER_STATUS': '4.0',
        'TICKET_FIELDS_CHANGED_DIVIDER_DEFAULT': '5.0',
      });
      expect(reader.getDefaultTicketWeightIfNoSPs(), 5);
      expect(reader.getLinesOfCodeDivider(), 2.0);
      expect(reader.getTimeSpentOnDivider(), 3.0);
      expect(reader.getTicketFieldsChangedDivider('status'), 4.0);
      expect(reader.getTicketFieldsChangedDivider('other'), 5.0);
    });
  });
}

void _testAiChunkGetters() {
  group('AI retry / prompt chunk / attachment getters smoke', () {
    test('defaults', () {
      expect(reader.getAiRetryAmount(), 3);
      expect(reader.getAiRetryDelayStep(), 20000);
      expect(reader.getPromptChunkTokenLimit(), 50000);
      expect(reader.getPromptChunkMaxSingleFileSize(), 4 * 1024 * 1024);
      expect(reader.getPromptChunkMaxTotalFilesSize(), 4 * 1024 * 1024);
      expect(reader.getPromptChunkMaxFiles(), 10);
      expect(reader.getAIAttachmentMaxSizeBytes(), 0);
      expect(reader.getAIAttachmentAllowedExtensions(), isEmpty);
    });

    test('with overrides', () {
      PropertyReader.setOverrides({
        'AI_RETRY_AMOUNT': '7',
        'AI_RETRY_DELAY_STEP': '5000',
        'PROMPT_CHUNK_TOKEN_LIMIT': '10000',
        'PROMPT_CHUNK_MAX_SINGLE_FILE_SIZE_MB': '2',
        'PROMPT_CHUNK_MAX_TOTAL_FILES_SIZE_MB': '8',
        'PROMPT_CHUNK_MAX_FILES': '5',
        'AI_ATTACHMENT_MAX_SIZE_MB': '10',
        'AI_ATTACHMENT_ALLOWED_EXTENSIONS': 'pdf,docx',
      });
      expect(reader.getAiRetryAmount(), 7);
      expect(reader.getAiRetryDelayStep(), 5000);
      expect(reader.getPromptChunkTokenLimit(), 10000);
      expect(reader.getPromptChunkMaxSingleFileSize(), 2 * 1024 * 1024);
      expect(reader.getPromptChunkMaxTotalFilesSize(), 8 * 1024 * 1024);
      expect(reader.getPromptChunkMaxFiles(), 5);
      expect(reader.getAIAttachmentMaxSizeBytes(), 10 * 1024 * 1024);
      expect(
        reader.getAIAttachmentAllowedExtensions(),
        {'pdf', 'docx'},
      );
    });
  });
}
