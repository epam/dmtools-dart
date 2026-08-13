import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Builds a jira tool with an optional alias.
ToolDefinition jiraTool({List<String> aliases = const []}) => ToolDefinition(
      name: 'jira_get_ticket',
      description: 'Fetch a Jira ticket by key',
      integration: 'jira',
      category: 'issues',
      aliases: aliases,
      params: [
        ToolParam(
          name: 'ticket_id',
          description: 'The Jira ticket key',
        ),
        ToolParam(
          name: 'expand',
          description: 'Optional field expansions',
          required: false,
          type: 'array',
        ),
      ],
    );

/// Builds a github tool with an optional alias.
ToolDefinition githubTool({List<String> aliases = const []}) => ToolDefinition(
      name: 'github_create_issue',
      description: 'Create a GitHub issue',
      integration: 'github',
      category: 'issues',
      aliases: aliases,
    );

/// Builds the jira tool with a different description, for duplicate tests.
ToolDefinition replacementJiraTool() => ToolDefinition(
      name: 'jira_get_ticket',
      description: 'replaced description',
      integration: 'jira',
    );

/// Builds a registry pre-populated with one jira and one github tool.
ToolRegistry populatedRegistry({List<String> jiraAliases = const []}) {
  final registry = ToolRegistry()
    ..register(jiraTool(aliases: jiraAliases))
    ..register(githubTool());
  return registry;
}

void main() {
  toolParamTests();
  toolDefinitionTests();
  registryLookupTests();
  registryFilteringTests();
  toolsListResponseTests();
  registryEdgeCaseTests();
}

/// [ToolParam.toJson] serializes type and description.
void toolParamTests() {
  group('ToolParam', () {
    test('toJson emits type and description', () {
      final param = ToolParam(
        name: 'ticket_id',
        description: 'The ticket key',
        required: false,
        type: 'number',
      );
      expect(param.toJson(), {
        'type': 'number',
        'description': 'The ticket key',
      });
    });
  });
}

/// [ToolDefinition] serialization and required-param derivation.
void toolDefinitionTests() {
  group('ToolDefinition', () {
    test('requiredParams lists only required names in order', () {
      expect(jiraTool().requiredParams, ['ticket_id']);
    });

    test('toJson matches the MCP protocol format', () {
      final json = jiraTool(aliases: ['tracker_get_ticket']).toJson();
      expect(json['name'], 'jira_get_ticket');
      expect(json['integration'], 'jira');
      expect(json['category'], 'issues');
      expect(json['description'], 'Fetch a Jira ticket by key');
      final schema = json['inputSchema'] as Map<String, dynamic>;
      expect(schema['type'], 'object');
      expect(schema['required'], ['ticket_id']);
      final props = schema['properties'] as Map<String, dynamic>;
      expect(props.keys, unorderedEquals(['ticket_id', 'expand']));
      expect(props['expand'], {
        'type': 'array',
        'description': 'Optional field expansions',
      });
    });
  });
}

/// [ToolRegistry] name and alias lookup.
void registryLookupTests() {
  group('ToolRegistry lookup', () {
    test('registers and retrieves by name', () {
      final registry = populatedRegistry();
      final tool = registry.getTool('github_create_issue');
      expect(tool?.name, 'github_create_issue');
      expect(tool?.integration, 'github');
      expect(registry.hasTool('jira_get_ticket'), isTrue);
    });

    test('resolves aliases to canonical names', () {
      final registry = populatedRegistry(jiraAliases: ['tracker_get_ticket']);
      expect(registry.resolveName('tracker_get_ticket'), 'jira_get_ticket');
      final viaAlias = registry.getTool('tracker_get_ticket');
      expect(viaAlias?.name, 'jira_get_ticket');
      expect(registry.hasTool('tracker_get_ticket'), isTrue);
    });

    test('unknown tool resolves to null', () {
      final registry = populatedRegistry();
      expect(registry.getTool('nope'), isNull);
      expect(registry.resolveName('nope'), isNull);
      expect(registry.hasTool('nope'), isFalse);
    });

    test('duplicate registration replaces the tool', () {
      final registry = populatedRegistry();
      registry.register(replacementJiraTool());
      expect(registry.getTool('jira_get_ticket')?.description,
          'replaced description');
      expect(registry.allTools, hasLength(2));
    });
  });
}

/// [ToolRegistry] integration filtering and ordering.
void registryFilteringTests() {
  group('ToolRegistry filtering', () {
    test('toolsForIntegrations filters by integration', () {
      final registry = populatedRegistry();
      final onlyJira = registry.toolsForIntegrations({'jira'});
      expect(onlyJira, hasLength(1));
      expect(onlyJira.single.name, 'jira_get_ticket');
      expect(registry.toolsForIntegrations(null), hasLength(2));
    });

    test('allTools is sorted alphabetically', () {
      final names = populatedRegistry().allTools.map((t) => t.name).toList();
      expect(names, ['github_create_issue', 'jira_get_ticket']);
    });

    test('availableIntegrations lists non-empty integrations', () {
      expect(populatedRegistry().availableIntegrations, {'jira', 'github'});
      expect(ToolRegistry().availableIntegrations, isEmpty);
    });
  });
}

/// [ToolRegistry] MCP tools/list response generation and filtering.
void toolsListResponseTests() {
  group('tools list response', () {
    test('generateToolsListResponse formats every tool', () {
      final response = populatedRegistry().generateToolsListResponse();
      final tools = response['tools'] as List<Map<String, dynamic>>;
      expect(tools, hasLength(2));
      expect(tools.first['name'], 'github_create_issue');
      expect(tools.first, containsPair('inputSchema', isNotNull));
    });

    test('generateToolsListResponse honors integrations filter', () {
      final response =
          populatedRegistry().generateToolsListResponse({'github'});
      expect((response['tools'] as List), hasLength(1));
    });

    test('filterToolsList matches name and description, case-insensitively',
        () {
      final list = populatedRegistry().generateToolsListResponse();
      expect(
        (ToolRegistry().filterToolsList(list, 'jira')['tools'] as List),
        hasLength(1),
      );
      expect(
        (ToolRegistry().filterToolsList(list, 'TICKET')['tools'] as List),
        hasLength(1),
      );
      expect(
        (ToolRegistry().filterToolsList(list, 'zenhub')['tools'] as List),
        isEmpty,
      );
    });
  });
}

/// [ToolRegistry] empty registry and clear() behavior.
void registryEdgeCaseTests() {
  group('edge cases', () {
    test('empty registry produces an empty tools list', () {
      final response = ToolRegistry().generateToolsListResponse();
      expect(response['tools'], isEmpty);
      expect(ToolRegistry().allTools, isEmpty);
    });

    test('clear removes tools and aliases', () {
      final registry = populatedRegistry(jiraAliases: ['tracker_get_ticket']);
      registry.clear();
      expect(registry.allTools, isEmpty);
      expect(registry.hasTool('tracker_get_ticket'), isFalse);
    });
  });
}
