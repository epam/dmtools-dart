/// Bridge-level routing for the `scm_*`/`ci_*` aliases (gh-339).
///
/// The JS-visible path is `executeToolViaJava('scm_get_pr', …)` →
/// [ToolBridge.execute] → registry → [dispatcher]: with `DEFAULT_SCM`
/// configured the alias dispatches to the provider's concrete handler,
/// and an unconfigured provider degrades to the same unknown-tool
/// envelope the tracker aliases produce (the documented degradation).
library;

import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/tool_bridge.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  test('DEFAULT_SCM=github: scm_get_pr dispatches through the provider '
      'handler (E1: present alias, provider auth error on missing creds)',
      () {
    PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute(
        'scm_get_pr',
        {'workspace': 'o', 'repository': 'r', 'pr': 1},
      ),
    ) as Map<String, dynamic>;
    expect(result['error'], 'GitHub not configured',
        reason: 'the alias is registered and routed — the concrete '
            'provider reports its own config error');
  });

  test('without DEFAULT_SCM the alias is unknown (tool-not-found shape)',
      () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute(
        'scm_get_pr',
        {'workspace': 'o', 'repository': 'r', 'pr': 1},
      ),
    ) as Map<String, dynamic>;
    expect(result['error'], 'Unknown tool: scm_get_pr');
  });

  test('DEFAULT_CI unset: ci_* is unknown even when DEFAULT_SCM is set',
      () {
    PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute('ci_get_verdict', {'workspace': 'o', 'repository': 'r'}),
    ) as Map<String, dynamic>;
    expect(result['error'], 'Unknown tool: ci_get_verdict');
  });

  test('a concrete github tool still dispatches unchanged next to the '
      'aliases (additive-only invariant)', () {
    PropertyReader.setOverrides({'DEFAULT_SCM': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result = jsonDecode(
      bridge.execute(
        'github_get_pr',
        {'workspace': 'o', 'repository': 'r', 'pullRequestId': 1},
      ),
    ) as Map<String, dynamic>;
    expect(result['error'], 'GitHub not configured');
  });
}
