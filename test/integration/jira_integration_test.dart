/// L3 live integration test — Jira smoke path via CLI tool dispatch.
///
/// Exercises the `dmtools <tool> '<json>'` surface in-process through
/// [ToolBridge.execute] — the exact function the CLI's `_toolDispatch` calls
/// for a direct tool invocation — which routes HTTP tools through
/// [SyncToolDispatcher]. Auth (base path + token) is built from [PropertyReader]
/// using the standard resolution chain (real env → `dmtools.env` →
/// `dmtools-local.env`), the same path production uses. No test-specific config,
/// no hardcoded values.
///
/// Gated on `DMTOOLS_IT_JIRA_PROJECT` (the sandbox project to target) and
/// `DMTOOLS_IT_JIRA_ISSUE_TYPE` (issue type for the throwaway ticket, default
/// `Task`). Missing project skips locally; `DMTOOLS_IT_REQUIRE_CREDS=true`
/// turns that skip into a failure in the CI integration job so a rotting
/// secret cannot hide.
///
/// Fixture lifecycle: each run creates a single throwaway ticket
/// `it-<runId>-smoke` in [setUpAll], exercises every smoke tool against it,
/// and deletes it in [tearDownAll]. Leaked `it-*` tickets are swept by
/// `bin/it_sweep.dart` (see test/integration/README.md).
///
/// Smoke path (GOAL.md → Integration testing strategy): auth → search →
/// read → write (labels, comment) → workflow transition → cleanup. The auth
/// step reuses `jira_get_ticket` (a 401 surfaces as Jira `errorMessages`),
/// since neither `jira_test` nor `jira_get_my_profile` is wired through both
/// the tool registry and the sync dispatcher.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Sandbox Jira project the tests target (e.g. `SANDBOX`). Absent → skip.
const String gateVar = 'DMTOOLS_IT_JIRA_PROJECT';

/// Issue type used when creating the throwaway ticket (default `Task`).
const String issueTypeVar = 'DMTOOLS_IT_JIRA_ISSUE_TYPE';

/// When `true`, a missing gate fails the suite instead of skipping it.
const String requireCredsVar = 'DMTOOLS_IT_REQUIRE_CREDS';

void main() {
  final project = Platform.environment[gateVar] ?? '';
  final issueType = Platform.environment[issueTypeVar] ?? 'Task';
  final requireCreds =
      (Platform.environment[requireCredsVar] ?? '').toLowerCase() == 'true';

  if (requireCreds && project.isEmpty) {
    throw StateError(
      '$requireCredsVar=true but $gateVar is unset: the CI integration job '
      'must fail loud rather than silently skip a missing sandbox target.',
    );
  }

  final runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  _jiraSmokeGroup(project, issueType, runId);
}

/// Registers the smoke-path group, skipped when [project] is empty.
void _jiraSmokeGroup(String project, String issueType, String runId) {
  group(
    'Jira live smoke path (CLI tool dispatch)',
    () {
      late final ToolBridge bridge;
      var ticketKey = '';

      setUpAll(() {
        bridge = ToolBridge(registry: createDefaultToolRegistry());
        ticketKey = _createTicket(bridge, project, issueType, runId);
      });

      tearDownAll(() {
        if (ticketKey.isEmpty) return;
        try {
          bridge.execute('jira_delete_ticket', {'key': ticketKey});
        } catch (_) {
          // Best-effort: leaked `it-*` tickets are swept by bin/it_sweep.dart.
        }
      });

      _registerReadTests(() => bridge, project, () => ticketKey);
      _registerWriteTests(() => bridge, () => ticketKey, runId);
    },
    skip: project.isEmpty
        ? 'Set $gateVar to a sandbox Jira project to run.'
        : null,
  );
}

/// Auth + search + read tests, sharing the group's bridge and ticket key.
void _registerReadTests(
  ToolBridge Function() bridge,
  String project,
  String Function() ticketKey,
) {
  test('auth: jira_get_ticket authenticates and reads the created ticket', () {
    final result =
        _decode(bridge().execute('jira_get_ticket', {'key': ticketKey()}));
    _expectNoError(result, context: 'get_ticket (auth)');
    expect(result['key'], ticketKey());
  });

  test('search: jira_search_by_jql returns issues in the sandbox project', () {
    final result = _decode(bridge().execute('jira_search_by_jql', {
      'jql': 'project = $project',
      'fields': ['summary'],
    }));
    _expectNoError(result, context: 'search_by_jql');
    final issues = result['issues'] as List? ?? const [];
    expect(issues, isNotEmpty, reason: 'sandbox project has no issues');
  });
}

/// Label, comment, and workflow-transition write tests.
void _registerWriteTests(
  ToolBridge Function() bridge,
  String Function() ticketKey,
  String runId,
) {
  test('labels: jira_add_label / jira_remove_label round-trip', () {
    final key = ticketKey();
    final label = 'it-$runId-label';
    bridge().execute('jira_add_label', {'key': key, 'label': label});
    expect(_labelsOf(_ticket(bridge(), key)), contains(label));
    bridge().execute('jira_remove_label', {'key': key, 'label': label});
    expect(_labelsOf(_ticket(bridge(), key)), isNot(contains(label)));
  });

  test('comment: jira_post_comment adds a comment', () {
    final result = _decode(bridge().execute('jira_post_comment', {
      'key': ticketKey(),
      'comment': 'it-$runId-comment',
    }));
    _expectNoError(result, context: 'post_comment');
    expect(result['self'] ?? result['id'], isNotNull,
        reason: 'comment response missing self/id');
  });

  test('workflow: jira_move_to_status transitions the ticket', () {
    final key = ticketKey();
    final target = _pickTransitionTarget(bridge(), key);
    // A freshly created ticket always has an outgoing transition; if the
    // sandbox workflow has none, there is nothing to assert, so return early.
    if (target == null) return;
    final result = _decode(
      bridge().execute('jira_move_to_status', {'key': key, 'status': target}),
    );
    _expectNoError(result, context: 'move_to_status');
  });
}

/// Creates a throwaway ticket `it-<runId>-smoke` and returns its key.
///
/// Throws a [StateError] with a hint to set [issueTypeVar] when the response
/// carries no `key` (typically an invalid issue type for [project]).
String _createTicket(
  ToolBridge bridge,
  String project,
  String issueType,
  String runId,
) {
  final result = _decode(bridge.execute('jira_create_ticket', {
    'project': project,
    'issueType': issueType,
    'summary': 'it-$runId-smoke',
    'description': 'L3 smoke fixture — auto-deleted in tearDownAll.',
  }));
  _expectNoError(result, context: 'create_ticket');
  final key = result['key'] as String?;
  if (key == null) {
    throw StateError(
      'create_ticket returned no key — is issue type "$issueType" valid for '
      'project "$project"? Set $issueTypeVar to a valid type.',
    );
  }
  return key;
}

/// Decodes a tool result JSON string into a map (empty map on empty body).
Map<String, dynamic> _decode(String json) {
  if (json.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(json);
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}

/// Asserts [result] carries no dispatcher `error` or Jira `errorMessages`.
void _expectNoError(Map<String, dynamic> result, {String context = ''}) {
  expect(
    result.containsKey('error'),
    isFalse,
    reason: '$context dispatcher error: ${result['error']}',
  );
  expect(
    result['errorMessages'],
    isNull,
    reason: '$context Jira errorMessages: ${result['errorMessages']}',
  );
}

/// Fetches a ticket as a decoded map.
Map<String, dynamic> _ticket(ToolBridge bridge, String key) =>
    _decode(bridge.execute('jira_get_ticket', {'key': key}));

/// Extracts the labels list from a get-ticket result.
List<String> _labelsOf(Map<String, dynamic> ticket) {
  final fields = ticket['fields'] as Map<String, dynamic>? ?? {};
  return List<String>.from(fields['labels'] as List? ?? const []);
}

/// Extracts the current status name from a get-ticket result.
String _statusOf(Map<String, dynamic> ticket) =>
    ((ticket['fields'] as Map?)?['status'] as Map?)?['name'] as String? ?? '';

/// Returns a destination status differing from the current one, or `null`.
///
/// Inspects the ticket's available transitions and picks the first whose
/// target status is not the current one — a safe target for
/// `jira_move_to_status` on a ticket the test owns.
String? _pickTransitionTarget(ToolBridge bridge, String key) {
  final current = _statusOf(_ticket(bridge, key));
  final transitions =
      _decode(bridge.execute('jira_get_transitions', {'key': key}))[
              'transitions'] as List? ??
          const [];
  for (final t in transitions) {
    final dest = ((t as Map)['to'] as Map?)?['name'] as String?;
    if (dest != null && dest != current) return dest;
  }
  return null;
}
