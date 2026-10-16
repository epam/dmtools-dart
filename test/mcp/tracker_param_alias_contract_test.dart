import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Parity contract for the `tracker_*` argument names (gh-389, dm.ai #695/#696).
///
/// Each operation lists the neutral names every backend must accept, mapped
/// to the canonical Dart parameter. A neutral name must normalize onto the
/// canonical key through [ToolDefinition.applyParamAliases], so a rename of
/// an alias cannot silently reopen the cross-backend gap.
void main() {
  const contract = <String, Map<String, List<String>>>{
    'jira_move_to_status': {
      'statusName': ['statusName', 'state', 'status'],
    },
    'jira_post_comment': {
      'comment': ['comment', 'text', 'body'],
    },
    'jira_search_by_jql': {
      'jql': ['jql', 'wiql', 'query', 'searchQueryJQL'],
    },
    'jira_create_ticket_basic': {
      'issueType': ['issueType', 'workItemType'],
      'summary': ['summary', 'title'],
    },
    'jira_assign_ticket_to': {
      'accountId': ['accountId', 'userEmail', 'assignee'],
    },
    'jira_link_issues': {
      'sourceKey': ['sourceKey', 'sourceId'],
      'anotherKey': ['anotherKey', 'targetId'],
    },
    'jira_attach_file_to_ticket': {
      'key': ['key', 'ticketKey', 'id'],
    },
    'ado_add_work_item_comment': {
      'comment': ['comment', 'text', 'body'],
    },
    'ado_list_work_items': {
      'wiql': ['wiql', 'jql', 'query', 'searchQueryJQL'],
    },
    'ado_move_to_state': {
      'state': ['state', 'statusName', 'status'],
    },
    'ado_create_work_item': {
      'workItemType': ['workItemType', 'issueType', 'type'],
      'title': ['title', 'summary'],
      'description': ['description', 'body'],
    },
    'github_create_comment': {
      'body': ['body', 'text', 'comment'],
      'pullRequestId': ['pullRequestId', 'number', 'issueNumber'],
    },
  };

  final registry = createDefaultToolRegistry();

  for (final entry in contract.entries) {
    group(entry.key, () {
      final tool = registry.getTool(entry.key);

      test('is registered', () {
        expect(tool, isNotNull);
      });

      for (final param in entry.value.entries) {
        test('accepts every neutral name for ${param.key}', () {
          for (final neutral in param.value) {
            final out = tool!.applyParamAliases({neutral: 'v'});
            expect(
              out[param.key],
              'v',
              reason: '$neutral should map onto ${param.key}',
            );
          }
        });
      }
    });
  }
}
