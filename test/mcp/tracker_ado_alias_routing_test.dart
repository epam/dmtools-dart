import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// `tracker_*` routing for the ADO ticket operations (dm.ai #661/#663):
/// each alias resolves to the `ado_*` carrier under DEFAULT_TRACKER=ado and
/// to the `jira_*` carrier otherwise.
void main() {
  const routes = {
    'tracker_update_field': ['jira_update_field', 'ado_update_field'],
    'tracker_set_priority': ['jira_set_priority', 'ado_set_priority'],
    'tracker_get_field_code': [
      'jira_get_field_custom_code',
      'ado_get_field_code'
    ],
    'tracker_attach_file': ['jira_attach_file_to_ticket', 'ado_attach_file'],
    'tracker_update_description': [
      'jira_update_description',
      'ado_update_description'
    ],
    'tracker_link_tickets': ['jira_link_issues', 'ado_link_work_items'],
    'tracker_move_to_status': ['jira_move_to_status', 'ado_move_to_state'],
    'tracker_assign': ['jira_assign_ticket_to', 'ado_assign_work_item'],
    'tracker_assign_ticket': ['jira_assign_ticket_to', 'ado_assign_work_item'],
    'tracker_post_comment': ['jira_post_comment', 'ado_add_work_item_comment'],
    'tracker_create_ticket': [
      'jira_create_ticket_basic',
      'ado_create_work_item'
    ],
  };
  final registry = createDefaultToolRegistry();

  routes.forEach((alias, carriers) {
    test('$alias routes to ${carriers[1]} under ado, ${carriers[0]} under jira',
        () {
      expect(
          registry.resolveToolAlias(alias, defaultTracker: 'ado'), carriers[1]);
      expect(registry.resolveToolAlias(alias, defaultTracker: 'jira'),
          carriers[0]);
    });
  });

  test('ado_search_by_wiql resolves to the WIQL tool', () {
    expect(
        registry.resolveToolAlias('ado_search_by_wiql'), 'ado_list_work_items');
  });

  test('Java param aliases map onto the canonical ADO params', () {
    Map<String, dynamic> apply(String tool, Map<String, dynamic> args) =>
        registry.getTool(tool)!.applyParamAliases(args);
    expect(apply('ado_move_to_state', {'key': '1', 'statusName': 'Done'}),
        containsPair('state', 'Done'));
    expect(apply('ado_assign_work_item', {'key': '1', 'accountId': 'a'}),
        containsPair('userEmail', 'a'));
    expect(apply('ado_add_work_item_comment', {'id': 1, 'text': 'hi'}),
        containsPair('comment', 'hi'));
    expect(apply('ado_link_work_items', {'sourceKey': '1', 'anotherKey': '2'}),
        allOf(containsPair('sourceId', '1'), containsPair('targetId', '2')));
    expect(apply('ado_create_work_item', {'issueType': 'Bug', 'summary': 's'}),
        allOf(containsPair('workItemType', 'Bug'), containsPair('title', 's')));
  });
}
