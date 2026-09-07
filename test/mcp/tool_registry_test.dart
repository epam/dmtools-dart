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
  applyParamAliasesTests();
  registryLookupTests();
  registryFilteringTests();
  toolsListResponseTests();
  registryEdgeCaseTests();
  registryAliasResolutionTests();
  registryAliasDefaultRoutingTests();
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

/// [ToolDefinition.applyParamAliases] Java parameter-alias bridging.
void applyParamAliasesTests() {
  group('ToolDefinition.applyParamAliases', () {
    ToolDefinition toolWithAliases() => ToolDefinition(
          name: 'jira_search_by_jql',
          description: 'Search',
          integration: 'jira',
          params: [
            const ToolParam(
              name: 'jql',
              description: 'JQL',
              aliases: ['searchQueryJQL', 'query'],
            ),
            ToolParam(name: 'limit', description: 'Limit'),
          ],
        );

    test('maps an alias value onto the canonical param name', () {
      final out = toolWithAliases().applyParamAliases({'query': 'project = X'});
      expect(out['jql'], 'project = X');
      expect(out.containsKey('query'), isTrue,
          reason: 'alias keys are preserved, handlers read canonical keys');
    });

    test('prefers the canonical key when both are present', () {
      final out = toolWithAliases()
          .applyParamAliases({'jql': 'canonical', 'searchQueryJQL': 'alias'});
      expect(out['jql'], 'canonical');
    });

    test('leaves args untouched when no alias matches', () {
      final args = {'jql': 'a', 'limit': 5};
      final out = toolWithAliases().applyParamAliases(args);
      expect(out, same(args));
    });

    test('first declared alias wins when several are present', () {
      final out = toolWithAliases()
          .applyParamAliases({'query': 'second', 'searchQueryJQL': 'first'});
      expect(out['jql'], 'first');
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

/// Builds an ado tool, for multi-candidate alias resolution tests.
ToolDefinition adoTool({List<String> aliases = const []}) => ToolDefinition(
      name: 'ado_get_work_item',
      description: 'Fetch an ADO work item by id',
      integration: 'ado',
      category: 'issues',
      aliases: aliases,
    );

/// [ToolRegistry.resolveToolAlias] — Java `McpCliHandler.resolveToolAlias`.
void registryAliasResolutionTests() {
  group('alias resolution', () {
    test('a canonical tool name resolves to itself unchanged', () {
      final registry = populatedRegistry(jiraAliases: ['tracker_get_ticket']);
      expect(registry.resolveToolAlias('jira_get_ticket'), 'jira_get_ticket');
    });

    test('an unknown name resolves to null', () {
      final registry = populatedRegistry();
      expect(registry.resolveToolAlias('nope_tool'), isNull);
    });

    test('a single-candidate alias resolves to its canonical tool', () {
      final registry = populatedRegistry(jiraAliases: ['tracker_get_ticket']);
      expect(
          registry.resolveToolAlias('tracker_get_ticket'), 'jira_get_ticket');
    });

    test('DEFAULT_TRACKER picks the carrier by integration name', () {
      final registry = ToolRegistry()
        ..register(jiraTool(aliases: ['tracker_get_ticket']))
        ..register(adoTool(aliases: ['tracker_get_ticket']));
      expect(
        registry.resolveToolAlias('tracker_get_ticket',
            defaultTracker: ' ADO '),
        'ado_get_work_item',
        reason: 'env values are trimmed and lowercased like Java',
      );
    });
  });
}

/// [ToolRegistry.resolveToolAlias] default-integration routing
/// (DEFAULT_TRACKER / DEFAULT_SOURCE_CODE).
void registryAliasDefaultRoutingTests() {
  group('alias resolution (default routing)', () {
    test('unset DEFAULT_TRACKER falls back to the first candidate', () {
      final registry = ToolRegistry()
        ..register(jiraTool(aliases: ['tracker_get_ticket']))
        ..register(adoTool(aliases: ['tracker_get_ticket']));
      expect(
        registry.resolveToolAlias('tracker_get_ticket'),
        'jira_get_ticket',
      );
    });

    test('an unconfigured default falls back to the first candidate', () {
      final registry = ToolRegistry()
        ..register(jiraTool(aliases: ['tracker_get_ticket']))
        ..register(adoTool(aliases: ['tracker_get_ticket']));
      expect(
        registry.resolveToolAlias('tracker_get_ticket',
            defaultTracker: 'rally'),
        'jira_get_ticket',
      );
    });

    test('source_code_* aliases honor DEFAULT_SOURCE_CODE', () {
      final registry = ToolRegistry()
        ..register(githubTool(aliases: ['source_code_get_pr']))
        ..register(
          ToolDefinition(
            name: 'gitlab_get_mr',
            description: 'Fetch a GitLab MR',
            integration: 'gitlab',
            aliases: ['source_code_get_pr'],
          ),
        );
      expect(
        registry.resolveToolAlias(
          'source_code_get_pr',
          defaultSourceCode: 'gitlab',
        ),
        'gitlab_get_mr',
      );
      expect(
        registry.resolveToolAlias('source_code_get_pr'),
        'github_create_issue',
        reason: 'first candidate when the env var is unset',
      );
    });

    test('other prefixes ignore both defaults', () {
      final registry = ToolRegistry()
        ..register(jiraTool(aliases: ['shared_op']))
        ..register(adoTool(aliases: ['shared_op']));
      expect(
        registry.resolveToolAlias('shared_op', defaultTracker: 'ado'),
        'jira_get_ticket',
        reason: 'only tracker_*/source_code_* read the default-integration env',
      );
    });
  });
}
