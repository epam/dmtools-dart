/// Dispatches MCP tool calls using synchronous HTTP (curl subprocess).
///
/// This is the `executeToolViaJava` implementation for real agent scripts.
/// It builds integration clients on the fly from [PropertyReader] config,
/// makes blocking HTTP calls via [SyncHttpClient], and returns JSON results.
///
/// Supported tools:
/// - Jira: `jira_get_ticket`, `jira_post_comment`, `jira_search_by_jql`,
///   `jira_add_label`, `jira_remove_label`, `jira_move_to_status`,
///   `jira_get_comments`, `jira_update_field`, `jira_update_description`,
///   `jira_get_transitions`, `jira_assign_to` (alias `jira_assign`),
///   `jira_get_my_profile`, `jira_delete_ticket`,
///   `jira_create_ticket_basic` (alias `jira_create_ticket`)
/// - GitHub: `github_get_pr`, `github_create_comment`
/// - GitLab: `gitlab_get_mr`, `gitlab_list_mrs`, `gitlab_create_mr_note`
/// - Confluence: `confluence_search`, `confluence_get_page`,
///   `confluence_create_page`
/// - ADO: `ado_get_work_item`, `ado_list_work_items`
///
/// File-system (`file_*`) and CLI (`cli_*`) tools are not HTTP-based; they
/// delegate to the host bridge's direct dispatch via [nonHttpHandler].
///
/// URL shapes and headers mirror the async [JiraHttpClient],
/// [GithubHttpClient], [GitlabHttpClient], [ConfluenceHttpClient], and
/// [AdoHttpClient] transports (`/rest/api/latest`, `X-Atlassian-Token`,
/// `PRIVATE-TOKEN`, Bearer auth, ADO Basic PAT, …) so both paths hit the same
/// endpoints.
///
/// Each HTTP integration lives in its own private tools class
/// ([_JiraSyncTools], [_GithubSyncTools], [_GitLabSyncTools],
/// [_ConfluenceSyncTools], [_AdoSyncTools]) that owns its config resolver and
/// request builders; the shared request plumbing ([_dispatch], [_postBody],
/// [_asStr], …) lives in top-level helpers.
library;

import 'dart:convert';

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import '../integrations/ado/ado_json.dart';
import '../integrations/jira/jira_utils.dart';
import 'sync_http_client.dart';

/// Connection config for a sync integration: base URL plus auth headers.
typedef SyncIntegrationConfig = ({String baseUrl, Map<String, String> headers});

/// Executor for a sync tool call: receives resolved [config] and [args].
typedef SyncToolFn = String Function(
  SyncIntegrationConfig,
  Map<String, dynamic>,
);

/// Executor for a non-HTTP (file/CLI) tool call: receives the raw [toolName]
/// and [args], returns the JSON result string.
typedef SyncNonHttpHandler = String Function(
  String toolName,
  Map<String, dynamic> args,
);

/// Routes tool calls to integration clients over synchronous HTTP.
///
/// Non-HTTP tools (file-system, CLI) are delegated to [nonHttpHandler] when
/// provided; otherwise `execute` returns `null` for them.
class SyncToolDispatcher {
  final PropertyReader _reader;
  final SyncNonHttpHandler? _nonHttpHandler;

  /// Creates a dispatcher reading integration config from [reader].
  ///
  /// The optional [nonHttpHandler] receives `file_*` and `cli_*` tool calls
  /// so the dispatcher can serve as a single routing entry point.
  SyncToolDispatcher(
    this._reader, {
    SyncNonHttpHandler? nonHttpHandler,
  }) : _nonHttpHandler = nonHttpHandler;

  /// Jira tools; built lazily on the first `jira_*` dispatch.
  late final _JiraSyncTools _jira = _JiraSyncTools(_reader);

  /// GitHub tools; built lazily on the first `github_*` dispatch.
  late final _GithubSyncTools _github = _GithubSyncTools(_reader);

  /// GitLab tools; built lazily on the first `gitlab_*` dispatch.
  late final _GitLabSyncTools _gitlab = _GitLabSyncTools(_reader);

  /// Confluence tools; built lazily on the first `confluence_*` dispatch.
  late final _ConfluenceSyncTools _confluence = _ConfluenceSyncTools(_reader);

  /// ADO tools; built lazily on the first `ado_*` dispatch.
  late final _AdoSyncTools _ado = _AdoSyncTools(_reader);

  /// Executes a tool call. Returns a JSON result string, or `null` when no
  /// integration matches the tool name and no [nonHttpHandler] is set.
  String? execute(String toolName, Map<String, dynamic> args) {
    if (toolName.startsWith('jira_')) {
      return _jira.dispatch(toolName, args);
    }
    if (toolName.startsWith('github_')) {
      return _github.dispatch(toolName, args);
    }
    if (toolName.startsWith('gitlab_')) {
      return _gitlab.dispatch(toolName, args);
    }
    if (toolName.startsWith('confluence_')) {
      return _confluence.dispatch(toolName, args);
    }
    if (toolName.startsWith('ado_')) {
      return _ado.dispatch(toolName, args);
    }
    // File-system and CLI tools delegate to the host bridge.
    final handler = _nonHttpHandler;
    if (handler != null) return handler(toolName, args);
    return null;
  }
}

/// Jira request builders: config resolver plus the `jira_*` executors.
class _JiraSyncTools {
  final PropertyReader _reader;

  /// Creates Jira tooling reading config from [reader].
  _JiraSyncTools(this._reader);

  /// Jira tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _jiraFns = {
    'jira_get_ticket': _jiraGetTicket,
    'jira_post_comment': _jiraPostComment,
    'jira_search_by_jql': _jiraSearchByJql,
    'jira_add_label': _jiraAddLabel,
    'jira_remove_label': _jiraRemoveLabel,
    'jira_move_to_status': _jiraMoveToStatus,
    'jira_get_comments': _jiraGetComments,
    'jira_update_field': _jiraUpdateField,
    'jira_update_description': _jiraUpdateDescription,
    'jira_get_transitions': _jiraGetTransitions,
    'jira_assign_to': _jiraAssignTo,
    'jira_assign': _jiraAssignTo,
    'jira_get_my_profile': _jiraGetMyProfile,
    'jira_delete_ticket': _jiraDeleteTicket,
    'jira_create_ticket_basic': _jiraCreateTicketBasic,
    'jira_create_ticket': _jiraCreateTicketBasic,
  };

  /// Dispatches a Jira tool call against [_jiraFns].
  String dispatch(String toolName, Map<String, dynamic> args) =>
      _dispatch(toolName, args, _jiraFns, _jiraConfig, 'Jira');

  /// Builds Jira config, or `null` when base path / auth is missing.
  SyncIntegrationConfig? _jiraConfig() {
    final basePath = _reader.getJiraBasePath();
    if (basePath == null || basePath.isEmpty) return null;
    final token = _reader.getJiraLoginPassToken();
    if (token == null || token.isEmpty) return null;
    final authType = _reader.getJiraAuthType() ?? 'Basic';
    return (
      baseUrl: '$basePath/rest/api/latest',
      headers: {
        'Authorization': '$authType $token',
        'X-Atlassian-Token': 'nocheck',
        'Content-Type': _jsonContentType,
      },
    );
  }

  /// `jira_get_ticket` — GET `issue/{key}?fields={fields}`.
  String _jiraGetTicket(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    final url = '${config.baseUrl}/issue/${_asStr(args['key'])}'
        '?fields=${Uri.encodeQueryComponent(_joinFields(args['fields']))}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `jira_post_comment` — POST `issue/{key}/comment`.
  String _jiraPostComment(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final body = jsonEncode({'body': _asStr(args['comment'])});
    final url = '${config.baseUrl}/issue/${_asStr(args['key'])}/comment';
    return _postBody(config, url, body);
  }

  /// `jira_search_by_jql` — GET `search/jql?jql={jql}&fields={fields}`.
  ///
  /// Single page (no cursor pagination); the first page covers the common
  /// agent-script case of scanning a bounded result set.
  String _jiraSearchByJql(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final url = '${config.baseUrl}/search/jql'
        '?jql=${Uri.encodeQueryComponent(_asStr(args['jql']))}'
        '&fields=${Uri.encodeQueryComponent(_joinFields(args['fields']))}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `jira_add_label` — fetches labels, appends, PUTs the full set.
  ///
  /// The PUT is skipped when the fetch fails: PUTting a set built from an
  /// empty failure result would wipe every existing label on the ticket.
  String _jiraAddLabel(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    final key = _asStr(args['key']);
    final labels = _fetchLabels(config, key);
    if (labels == null) return _err('Failed to fetch labels for $key');
    final label = _asStr(args['label']);
    if (!labels.contains(label)) labels.add(label);
    return _putLabels(config, key, labels);
  }

  /// `jira_remove_label` — fetches labels, removes, PUTs the full set.
  ///
  /// Same failure contract as [_jiraAddLabel]: no PUT without a confirmed
  /// fetch, or a transient GET error would clear the label set.
  String _jiraRemoveLabel(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final key = _asStr(args['key']);
    final labels = _fetchLabels(config, key);
    if (labels == null) return _err('Failed to fetch labels for $key');
    labels.remove(_asStr(args['label']));
    return _putLabels(config, key, labels);
  }

  /// `jira_move_to_status` — finds the transition, then POSTs it.
  String _jiraMoveToStatus(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final key = _asStr(args['key']);
    final status = _asStr(args['status']);
    final transitions = _fetchTransitions(config, key);
    final id = matchTransitionId(transitions, status);
    if (id == null) return _err('No transition found for status: $status');
    return _postBody(
        config,
        '${config.baseUrl}/issue/$key/transitions',
        jsonEncode({
          'transition': {'id': id},
        }));
  }

  /// `jira_get_comments` — GET `issue/{key}/comment`.
  String _jiraGetComments(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    final url = '${config.baseUrl}/issue/${_asStr(args['key'])}/comment';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `jira_update_field` — PUT `issue/{key}` with `{fields:{field:value}}`.
  String _jiraUpdateField(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    return _putBody(
      config,
      '${config.baseUrl}/issue/${_asStr(args['key'])}',
      jsonEncode({
        'fields': {_asStr(args['field']): args['value']},
      }),
    );
  }

  /// `jira_update_description` — PUT `issue/{key}` with the description.
  String _jiraUpdateDescription(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    return _putBody(
      config,
      '${config.baseUrl}/issue/${_asStr(args['key'])}',
      jsonEncode({
        'fields': {'description': _asStr(args['description'])},
      }),
    );
  }

  /// `jira_get_transitions` — GET `issue/{key}/transitions`.
  String _jiraGetTransitions(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    final url = '${config.baseUrl}/issue/${_asStr(args['key'])}/transitions';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `jira_assign_to` (alias `jira_assign`) — PUT `issue/{key}/assignee`.
  String _jiraAssignTo(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    return _putBody(
      config,
      '${config.baseUrl}/issue/${_asStr(args['key'])}/assignee',
      jsonEncode({'accountId': _asStr(args['accountId'])}),
    );
  }

  /// `jira_get_my_profile` — GET `myself`.
  String _jiraGetMyProfile(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    return _bodyOrError(
      SyncHttpClient.get('${config.baseUrl}/myself', headers: config.headers),
    );
  }

  /// `jira_delete_ticket` — DELETE `issue/{key}`.
  String _jiraDeleteTicket(
      SyncIntegrationConfig config, Map<String, dynamic> args) {
    return _bodyOrError(
      SyncHttpClient.delete(
        '${config.baseUrl}/issue/${_asStr(args['key'])}',
        headers: config.headers,
      ),
    );
  }

  /// `jira_create_ticket_basic` (alias `jira_create_ticket`) — POST `issue`.
  ///
  /// Description is included only when provided (Java `createTicketBasic`).
  String _jiraCreateTicketBasic(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final fields = <String, dynamic>{
      'project': {'key': _asStr(args['project'])},
      'issuetype': {'name': _asStr(args['issueType'])},
      'summary': _asStr(args['summary']),
    };
    final description = _asStr(args['description']);
    if (description.isNotEmpty) fields['description'] = description;
    return _postBody(
        config, '${config.baseUrl}/issue', jsonEncode({'fields': fields}));
  }

  /// Fetches the current labels list for [key]; `null` when the fetch fails
  /// (non-2xx, malformed JSON, curl error). Callers must abort rather than
  /// PUT an empty set — the failure path is what protects existing labels.
  List<String>? _fetchLabels(SyncIntegrationConfig config, String key) {
    final decoded =
        _getJson(config, '${config.baseUrl}/issue/$key?fields=labels');
    if (decoded == null) return null;
    final fields = decoded['fields'] as Map<String, dynamic>? ?? {};
    return List<String>.from(fields['labels'] as List? ?? []);
  }

  /// PUTs the full labels set via `update.labels[].set`.
  String _putLabels(
      SyncIntegrationConfig config, String key, List<String> labels) {
    final body = jsonEncode({
      'update': {
        'labels': [
          {'set': labels},
        ],
      },
    });
    return _putBody(config, '${config.baseUrl}/issue/$key', body);
  }

  /// Fetches the transitions list for [key]; empty list on failure.
  List<Map<String, dynamic>> _fetchTransitions(
    SyncIntegrationConfig config,
    String key,
  ) {
    final decoded =
        _getJson(config, '${config.baseUrl}/issue/$key/transitions');
    if (decoded == null) return [];
    final list = decoded['transitions'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }
}

/// GitHub request builders: config resolver plus the `github_*` executors.
class _GithubSyncTools {
  final PropertyReader _reader;

  /// Creates GitHub tooling reading config from [reader].
  _GithubSyncTools(this._reader);

  /// GitHub tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _githubFns = {
    'github_get_pr': _githubGetPr,
    'github_create_comment': _githubCreateComment,
  };

  /// Dispatches a GitHub tool call against [_githubFns].
  String dispatch(String toolName, Map<String, dynamic> args) =>
      _dispatch(toolName, args, _githubFns, _githubConfig, 'GitHub');

  /// Builds GitHub config, or `null` when the token is missing.
  SyncIntegrationConfig? _githubConfig() {
    final token = _reader.getGithubToken();
    if (token == null || token.isEmpty) return null;
    return (
      baseUrl: _reader.getGithubBasePath(),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': _jsonContentType,
      },
    );
  }

  /// `github_get_pr` — GET `repos/{owner}/{repo}/pulls/{number}`.
  String _githubGetPr(SyncIntegrationConfig config, Map<String, dynamic> args) {
    final url = '${config.baseUrl}/repos/${_asStr(args['owner'])}'
        '/${_asStr(args['repo'])}/pulls/${_asInt(args['number'])}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `github_create_comment` — POST `repos/{o}/{r}/issues/{n}/comments`.
  String _githubCreateComment(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final url = '${config.baseUrl}/repos/${_asStr(args['owner'])}'
        '/${_asStr(args['repo'])}/issues/${_asInt(args['number'])}/comments';
    return _postBody(config, url, jsonEncode({'body': _asStr(args['body'])}));
  }
}

/// GitLab request builders: config resolver plus the `gitlab_*` executors.
class _GitLabSyncTools {
  final PropertyReader _reader;

  /// Creates GitLab tooling reading config from [reader].
  _GitLabSyncTools(this._reader);

  /// GitLab tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _gitlabFns = {
    'gitlab_get_mr': _gitlabGetMr,
    'gitlab_list_mrs': _gitlabListMrs,
    'gitlab_create_mr_note': _gitlabCreateMrNote,
  };

  /// Dispatches a GitLab tool call against [_gitlabFns].
  String dispatch(String toolName, Map<String, dynamic> args) =>
      _dispatch(toolName, args, _gitlabFns, _gitlabConfig, 'GitLab');

  /// Builds GitLab config, or `null` when base path / token is missing.
  ///
  /// Mirrors [GitlabHttpClient]: `PRIVATE-TOKEN` header, `/api/v4` suffix.
  SyncIntegrationConfig? _gitlabConfig() {
    final basePath = _reader.getGitLabBasePath();
    if (basePath == null || basePath.isEmpty) return null;
    final token = _reader.getGitLabToken();
    if (token == null || token.isEmpty) return null;
    return (
      baseUrl: '$basePath/api/v4',
      headers: {
        'PRIVATE-TOKEN': token,
        'Content-Type': _jsonContentType,
      },
    );
  }

  /// URL-encodes a project id or `group/project` path for path segments.
  String _encodeProject(String project) => Uri.encodeComponent(project);

  /// `gitlab_get_mr` — GET `projects/{id}/merge_requests/{iid}`.
  String _gitlabGetMr(SyncIntegrationConfig config, Map<String, dynamic> args) {
    final project = _encodeProject(_asStr(args['project']));
    final url =
        '${config.baseUrl}/projects/$project/merge_requests/${_asInt(args['iid'])}';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `gitlab_list_mrs` — GET `projects/{id}/merge_requests?state=opened`.
  ///
  /// Query mirrors the async [GitlabClient.listMrs]: `state=opened` with
  /// `per_page=20`.
  String _gitlabListMrs(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final project = _encodeProject(_asStr(args['project']));
    final url = '${config.baseUrl}/projects/$project/merge_requests'
        '?state=opened&per_page=20';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `gitlab_create_mr_note` — POST `projects/{id}/merge_requests/{iid}/notes`.
  String _gitlabCreateMrNote(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final project = _encodeProject(_asStr(args['project']));
    final iid = _asInt(args['iid']);
    final url = '${config.baseUrl}/projects/$project/merge_requests/$iid/notes';
    return _postBody(config, url, jsonEncode({'body': _asStr(args['body'])}));
  }
}

/// Confluence request builders: config + the `confluence_*` executors.
class _ConfluenceSyncTools {
  final PropertyReader _reader;

  /// Creates Confluence tooling reading config from [reader].
  _ConfluenceSyncTools(this._reader);

  /// Confluence tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _confluenceFns = {
    'confluence_search': _confluenceSearch,
    'confluence_get_page': _confluenceGetPage,
    'confluence_create_page': _confluenceCreatePage,
  };

  /// Dispatches a Confluence tool call against [_confluenceFns].
  String dispatch(String toolName, Map<String, dynamic> args) => _dispatch(
      toolName, args, _confluenceFns, _confluenceConfig, 'Confluence');

  /// Builds Confluence config, or `null` when base path / auth is missing.
  ///
  /// Mirrors [ConfluenceHttpClient]: `{authType} {token}` Authorization,
  /// `/wiki/rest/api` suffix.
  SyncIntegrationConfig? _confluenceConfig() {
    final basePath = _reader.getConfluenceBasePath();
    if (basePath == null || basePath.isEmpty) return null;
    final token = _reader.getConfluenceLoginPassToken();
    if (token == null || token.isEmpty) return null;
    final authType = _reader.getConfluenceAuthType();
    return (
      baseUrl: '$basePath/wiki/rest/api',
      headers: {
        'Authorization': '$authType $token',
        'Accept': _jsonContentType,
        'Content-Type': _jsonContentType,
      },
    );
  }

  /// `confluence_search` — GET `content/search?cql={cql}`.
  String _confluenceSearch(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final cql = Uri.encodeQueryComponent(_asStr(args['cql']));
    final url = '${config.baseUrl}/content/search?cql=$cql';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `confluence_get_page` — GET `content?spaceKey=&title=&expand=body.storage`.
  String _confluenceGetPage(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final spaceKey = Uri.encodeQueryComponent(_asStr(args['spaceKey']));
    final title = Uri.encodeQueryComponent(_asStr(args['title']));
    final url = '${config.baseUrl}/content'
        '?spaceKey=$spaceKey&title=$title&expand=body.storage';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `confluence_create_page` — POST `content` with the storage-format page.
  String _confluenceCreatePage(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    return _postBody(
      config,
      '${config.baseUrl}/content',
      jsonEncode(_pagePayload(args)),
    );
  }

  /// Builds the Confluence page creation payload (mirrors the Java
  /// `ConfluenceClient.createPage` wire format).
  Map<String, dynamic> _pagePayload(Map<String, dynamic> args) => {
        'type': 'page',
        'title': _asStr(args['title']),
        'space': {'key': _asStr(args['space'])},
        'body': {
          'storage': {
            'value': _asStr(args['body']),
            'representation': 'storage',
          },
        },
      };
}

/// ADO request builders: config resolver plus the `ado_*` executors.
class _AdoSyncTools {
  final PropertyReader _reader;

  /// Creates ADO tooling reading config from [reader].
  _AdoSyncTools(this._reader);

  /// ADO REST API version sent on every request (mirrors Java `API_VERSION`).
  static const _adoApiVersion = '7.0';

  /// ADO tool executors; config is resolved once before dispatch.
  late final Map<String, SyncToolFn> _adoFns = {
    'ado_get_work_item': _adoGetWorkItem,
    'ado_list_work_items': _adoListWorkItems,
  };

  /// Dispatches an ADO tool call against [_adoFns].
  String dispatch(String toolName, Map<String, dynamic> args) =>
      _dispatch(toolName, args, _adoFns, _adoConfig, 'ADO');

  /// Builds ADO config, or `null` when organization / project / PAT is missing.
  ///
  /// Mirrors [AdoHttpClient]: Basic `base64(':' + PAT)` auth, base URL
  /// `{ADO_BASE_PATH}/{org}/{project}/_apis`.
  SyncIntegrationConfig? _adoConfig() {
    final organization = _reader.getAdoOrganization();
    if (organization == null || organization.isEmpty) return null;
    final project = _reader.getAdoProject();
    if (project == null || project.isEmpty) return null;
    final pat = _reader.getAdoPatToken();
    if (pat == null || pat.isEmpty) return null;
    final basic = base64Encode(utf8.encode(':$pat'));
    final basePath = _reader.getAdoBasePath();
    return (
      baseUrl: '$basePath/$organization/$project/_apis',
      headers: {
        'Authorization': 'Basic $basic',
        'Content-Type': _jsonContentType,
      },
    );
  }

  /// `ado_get_work_item` — GET `wit/workitems/{id}?api-version=7.0`.
  String _adoGetWorkItem(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final id = _asInt(args['id']);
    final url = '${config.baseUrl}/wit/workitems/$id'
        '?api-version=$_adoApiVersion';
    return _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
  }

  /// `ado_list_work_items` — POST `wit/wiql`, then batch-fetch full items.
  ///
  /// Mirrors [AdoClient.listWorkItems] / Java `searchAndPerform`: the
  /// WIQL response carries only id/url stubs, so the ids are re-fetched
  /// via `wit/workitems` in batches of 200 (`fields=...` when given,
  /// `$expand=relations` otherwise) and the full items are returned.
  String _adoListWorkItems(
    SyncIntegrationConfig config,
    Map<String, dynamic> args,
  ) {
    final wiqlUrl = '${config.baseUrl}/wit/wiql?api-version=$_adoApiVersion';
    final wiqlBody = _postBody(
      config,
      wiqlUrl,
      jsonEncode({'query': _asStr(args['wiql'])}),
    );
    final wiql = _tryDecode(wiqlBody);
    if (wiql is! Map || wiql['workItems'] is! List) return wiqlBody;
    final ids = wiqlStubIds(wiql['workItems'] as List);
    final fields = (args['fields'] as List?)?.cast<String>();
    final items = <Map<String, dynamic>>[];
    for (final batch in batchIds(ids)) {
      final detail = _adoDetailBatch(config, batch, fields);
      if (detail == null) continue;
      items.addAll(detail);
    }
    return jsonEncode(items);
  }

  /// Fetches one `wit/workitems` id batch, or `null` on an error body.
  List<Map<String, dynamic>>? _adoDetailBatch(
    SyncIntegrationConfig config,
    List<int> ids,
    List<String>? fields,
  ) {
    final extra = fields != null && fields.isNotEmpty
        ? 'fields=${Uri.encodeQueryComponent(fields.join(','))}'
        : r'$expand=relations';
    final url = '${config.baseUrl}/wit/workitems'
        '?ids=${ids.join(',')}&$extra&api-version=$_adoApiVersion';
    final body = _bodyOrError(SyncHttpClient.get(url, headers: config.headers));
    final decoded = _tryDecode(body);
    if (decoded is Map && decoded['error'] != null) return null;
    return unwrapAdoItems(decoded);
  }
}

// ── Shared dispatch + HTTP helpers ───────────────────────────────────────

/// Media type for JSON request/response bodies.
const _jsonContentType = 'application/json';

/// Decodes [body] as JSON, returning it verbatim when it does not parse.
dynamic _tryDecode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return body;
  }
}

/// Resolves [toolName] against [fns], checks config, then dispatches.
String _dispatch(
  String toolName,
  Map<String, dynamic> args,
  Map<String, SyncToolFn> fns,
  SyncIntegrationConfig? Function() configFn,
  String integration,
) {
  final fn = fns[toolName];
  if (fn == null) return _err('Unsupported $integration tool: $toolName');
  final config = configFn();
  if (config == null) return _err('$integration not configured');
  return fn(config, args);
}

/// GETs a JSON object, returning `null` on failure or non-object body.
Map<String, dynamic>? _getJson(SyncIntegrationConfig config, String url) {
  final resp = SyncHttpClient.get(url, headers: config.headers);
  if (!resp.isOk) return null;
  try {
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    // fall through
  }
  return null;
}

/// POSTs [body] to [url] and returns the result string.
String _postBody(SyncIntegrationConfig config, String url, String body) =>
    _bodyOrError(SyncHttpClient.post(url, headers: config.headers, body: body));

/// PUTs [body] to [url] and returns the result string.
String _putBody(SyncIntegrationConfig config, String url, String body) =>
    _bodyOrError(SyncHttpClient.put(url, headers: config.headers, body: body));

/// Returns the response body, or an error JSON when curl failed.
String _bodyOrError(SyncHttpResponse resp) {
  if (resp.statusCode == 0) return _err('HTTP request failed: ${resp.body}');
  return resp.body;
}

/// Joins a `fields` argument (list or comma string) into a query value.
///
/// Defaults to `*navigable` (the Java `JiraClient` default).
String _joinFields(dynamic fields) {
  if (fields == null) return '*navigable';
  if (fields is String) return fields;
  if (fields is List) return fields.cast<String>().join(',');
  return '*navigable';
}

/// Coerces a loosely-typed JS argument to a string.
String _asStr(dynamic value) => value?.toString() ?? '';

/// Coerces a loosely-typed JS argument to an int.
int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Encodes a JSON error result string.
String _err(String message) => jsonEncode({'error': message});
