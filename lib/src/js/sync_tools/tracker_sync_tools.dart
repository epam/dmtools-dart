/// Synchronous tracker-generic tool executors for the JS tool bridge.
///
/// Routes the `tracker_*` tool family to the backend selected by
/// `TRACKER_TYPE` (`jira` | `github` | `ado`, default `jira` — the Java DI
/// module analog: `JiraModule` vs `AdoModule`). Jira calls forward to
/// [JiraSyncTools] with mapped argument names; ADO forwards the work-item
/// subset [AdoSyncTools] already implements; GitHub issues get first-class
/// executors here (the issues REST API is shared by PRs, so URL shapes
/// mirror `github_sync_tools.dart`).
///
/// All HTTP goes through [SyncHttpClient] (curl subprocess) — safe inside
/// QuickJS `NativeCallable` callbacks where the Dart event loop is frozen.
/// Failures return `{"error": …}` JSON, never throw.
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../sync_http_client.dart';
import 'ado_sync_tools.dart';
import 'jira_sync_tools.dart';
import 'sync_request_helpers.dart';

/// One tracker tool executor: arguments map in, JSON string out.
typedef TrackerHandler = String Function(Map<String, dynamic> args);

/// Connection config for one GitHub sync call.
typedef _GhConfig = ({String baseUrl, Map<String, String> headers});

/// Routes `tracker_*` calls to the configured tracker backend.
class TrackerSyncTools {
  /// Creates tracker tooling.
  ///
  /// [trackerType] pins the backend (tests, multi-tracker hosts); when null
  /// the type is resolved per dispatch via `PropertyReader.getTrackerType()`
  /// (`TRACKER_TYPE`, default `jira`).
  TrackerSyncTools({String? trackerType}) : _trackerType = trackerType;

  final String? _trackerType;

  /// `tracker_*` executors, keyed by the generic tool name.
  Map<String, TrackerHandler> get handlers => {
        for (final op in _jiraToolNames.keys) 'tracker_$op': _bound(op),
      };

  /// Binds one op to this instance's routing chain.
  TrackerHandler _bound(String op) => (args) => _route(op, args);

  /// Resolves the backend type and forwards the op.
  String _route(String op, Map<String, dynamic> args) {
    // A fresh reader per call — the same per-call pattern the sync tools
    // use, so `set_env_variable` stays effective mid-script. [_trackerType]
    // pins the backend when set (tests, multi-tracker hosts).
    final type = _trackerType ?? PropertyReader().getTrackerType();
    switch (type) {
      case 'jira':
        return _toJira(op, args);
      case 'github':
        return _toGithub(op, args);
      case 'ado':
        return _toAdo(op, args);
      default:
        return syncErr('Unknown TRACKER_TYPE: $type');
    }
  }

  // ------------------------------------------------------------------
  // Jira backend — forwards to JiraSyncTools with mapped argument names.
  // ------------------------------------------------------------------

  static const _jiraToolNames = {
    'get_ticket': 'jira_get_ticket',
    'post_comment': 'jira_post_comment',
    'get_comments': 'jira_get_comments',
    'add_label': 'jira_add_label',
    'remove_label': 'jira_remove_label',
    'move_to_status': 'jira_move_to_status',
    'search': 'jira_search_by_jql',
    'assign_to': 'jira_assign_ticket_to',
    'create_ticket': 'jira_create_ticket_basic',
  };

  String _toJira(String op, Map<String, dynamic> args) {
    final fn = const JiraSyncTools().handlers[_jiraToolNames[op]];
    if (fn == null) return syncErr('Jira does not support tracker_$op');
    return fn(_mapJiraArgs(op, args));
  }

  /// Maps generic arguments onto the Jira tool argument names.
  static Map<String, dynamic> _mapJiraArgs(
    String op,
    Map<String, dynamic> args,
  ) {
    switch (op) {
      case 'search':
        return {'jql': args['query'], 'fields': args['fields']};
      case 'assign_to':
        return {'key': args['key'], 'accountId': args['user']};
      case 'create_ticket':
        return {
          'project': args['project'],
          'issueType': args['type'],
          'summary': args['title'],
          'description': args['description'],
        };
      default:
        return args; // key/comment/label/status already match 1:1.
    }
  }

  // ------------------------------------------------------------------
  // ADO backend — work-item subset over the existing executors.
  // ------------------------------------------------------------------

  static String _toAdo(String op, Map<String, dynamic> args) {
    const names = {
      'get_ticket': 'ado_get_work_item',
      'search': 'ado_list_work_items',
    };
    final name = names[op];
    if (name == null) {
      return syncErr('tracker_$op is not yet supported for ADO');
    }
    final fn = const AdoSyncTools().handlers[name];
    if (fn == null) return syncErr('Unsupported ADO tool: $name');
    switch (op) {
      case 'get_ticket':
        return fn({'id': args['key']});
      case 'search':
        return fn({'wiql': args['query']});
    }
    return syncErr('tracker_$op: unmapped ADO arguments');
  }

  // ------------------------------------------------------------------
  // GitHub backend — issues REST API (shared with PRs).
  // ------------------------------------------------------------------

  static String _toGithub(String op, Map<String, dynamic> args) {
    final c = _ghConfig();
    if (c == null) return syncErr('GitHub not configured');
    final issueFn = _ghIssueOps[op];
    if (issueFn != null) {
      return _ghIssue(c, op, args, issueFn);
    }
    final repoFn = _ghRepoOps[op];
    if (repoFn != null) return repoFn(c, args);
    return syncErr('tracker_$op is not supported for GitHub');
  }

  /// Runs an issue-addressed op: resolves the repo segment and issue number,
  /// then delegates to the op's URL builder.
  static String _ghIssue(
    _GhConfig c,
    String op,
    Map<String, dynamic> args,
    String Function(_GhConfig c, String issuePath, Map<String, dynamic> args)
        issueFn,
  ) {
    final repo = _repoSeg(args);
    if (repo == null) {
      return syncErr(
        'tracker_$op: pass "owner/repo#123" or set GITHUB_REPOSITORY',
      );
    }
    return issueFn(c, '$repo/issues/${_issueNumber(args)}', args);
  }

  /// Issue-addressed ops: `(config, "repos/o/r/issues/N", args) → result`.
  static final Map<
          String,
          String Function(
              _GhConfig c, String issuePath, Map<String, dynamic> args)>
      _ghIssueOps = {
    'get_ticket': (c, p, _) => _ghGet(c, p),
    'post_comment': (c, p, a) =>
        _ghPost(c, '$p/comments', {'body': syncAsStr(a['comment'])}),
    'get_comments': (c, p, _) => _ghGet(c, '$p/comments?per_page=100'),
    'add_label': (c, p, a) => _ghPost(c, '$p/labels', [syncAsStr(a['label'])]),
    'remove_label': (c, p, a) => syncBodyOrError(SyncHttpClient.delete(
          '${c.baseUrl}/$p'
          '/labels/${Uri.encodeComponent(syncAsStr(a['label']))}',
          headers: c.headers,
        )),
    'move_to_status': _ghMoveToStatus,
    'assign_to': (c, p, a) => _ghPost(
          c,
          '$p/assignees',
          {
            'assignees': [syncAsStr(a['user'])]
          },
        ),
  };

  /// Repo-scoped ops (`search` over all issues, `create_ticket`).
  static final Map<String, String Function(_GhConfig c, Map<String, dynamic>)>
      _ghRepoOps = {
    'search': (c, a) {
      final q = Uri.encodeQueryComponent(syncAsStr(a['query']));
      return _ghGet(c, 'search/issues?q=$q&per_page=100');
    },
    'create_ticket': (c, a) {
      final repo = _repoSeg(a);
      if (repo == null) {
        return syncErr(
          'tracker_create_ticket: pass project "owner/repo" or set '
          'GITHUB_REPOSITORY',
        );
      }
      return _ghPost(c, '$repo/issues', {
        'title': syncAsStr(a['title']),
        if (a['description'] != null) 'body': syncAsStr(a['description']),
      });
    },
  };

  static String _ghMoveToStatus(
    _GhConfig c,
    String issuePath,
    Map<String, dynamic> args,
  ) {
    final state = _githubState(syncAsStr(args['status']));
    if (state == null) {
      return syncErr(
        'Cannot map GitHub status "${args['status']}": use Done/Closed or '
        'Open/Reopened',
      );
    }
    return _ghPatch(c, issuePath, {'state': state});
  }

  /// Maps a generic status name onto the GitHub issue state.
  static String? _githubState(String status) {
    final s = status.toLowerCase().trim();
    const closed = {'done', 'closed', 'completed', 'fixed', 'resolved'};
    const open = {'open', 'reopened', 'in progress', 'todo', 'backlog'};
    if (closed.contains(s)) return 'closed';
    if (open.contains(s)) return 'open';
    return null;
  }

  /// `owner/repo` URL segment: parsed from `key` (`owner/repo#123`) or the
  /// `project` argument (`owner/repo`), defaulting to `GITHUB_REPOSITORY`.
  static String? _repoSeg(Map<String, dynamic> args) {
    final fromKey = _splitKey(syncAsStr(args['key']));
    if (fromKey != null) return 'repos/${fromKey.$1}/${fromKey.$2}';
    final project = syncAsStr(args['project']).trim();
    if (project.contains('/')) return 'repos/$project';
    final env = PropertyReader().getValue('GITHUB_REPOSITORY')?.trim();
    if (env != null && env.isNotEmpty && env.contains('/')) {
      return 'repos/$env';
    }
    return null;
  }

  /// Splits `"owner/repo#123"` (or `"owner/repo"`); null when not key-shaped.
  static (String, String)? _splitKey(String key) {
    final m = RegExp(r'^([\w.-]+)/([\w.-]+)#\d+$').firstMatch(key.trim());
    if (m != null) return (m.group(1)!, m.group(2)!);
    return null;
  }

  /// The issue number: the `#N` suffix of `key`, or `N` itself.
  static String _issueNumber(Map<String, dynamic> args) {
    final key = syncAsStr(args['key']).trim();
    final hash = key.indexOf('#');
    return hash >= 0 ? key.substring(hash + 1) : key;
  }

  /// GitHub connection config, or null when the token is missing.
  static _GhConfig? _ghConfig() {
    final token = PropertyReader().getGithubToken();
    if (token == null || token.isEmpty) return null;
    return (
      baseUrl: PropertyReader().getGithubBasePath(),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
  }

  static String _ghGet(_GhConfig c, String path) => syncBodyOrError(
      SyncHttpClient.get('${c.baseUrl}/$path', headers: c.headers));

  static String _ghPost(_GhConfig c, String path, Object body) =>
      syncBodyOrError(SyncHttpClient.post('${c.baseUrl}/$path',
          headers: c.headers, body: jsonEncode(body)));

  static String _ghPatch(_GhConfig c, String path, Object body) =>
      syncBodyOrError(SyncHttpClient.patch('${c.baseUrl}/$path',
          headers: c.headers, body: jsonEncode(body)));
}
