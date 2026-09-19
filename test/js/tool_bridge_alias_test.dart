import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/tool_bridge.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

/// [ToolBridge.execute] alias routing — Java
/// `JobJavaScriptBridge.executeToolFromJS` parity (dm.ai #577):
/// vendor-agnostic `tracker_*` aliases resolve on every call with a key
/// hint extracted from the args. The dispatched carrier's
/// unconfigured-integration error envelope proves the routing without
/// touching the network.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() => PropertyReader.setOverrides({}));
  tearDown(() => PropertyReader.clearOverrides());

  test('tracker_get_ticket with a gh-N key routes to github_get_issue', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result =
        jsonDecode(bridge.execute('tracker_get_ticket', {'key': 'gh-42'}));
    expect(result, containsPair('error', 'GitHub not configured'));
  });

  test('tracker_get_ticket with a PROJ-123 key routes to jira_get_ticket', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result =
        jsonDecode(bridge.execute('tracker_get_ticket', {'key': 'PROJ-123'}));
    expect(result, containsPair('error', 'Jira not configured'));
  });

  test('DEFAULT_TRACKER routes when the key gives no vendor signal', () {
    PropertyReader.setOverrides({'DEFAULT_TRACKER': 'github'});
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result =
        jsonDecode(bridge.execute('tracker_get_ticket', {'key': 'X'}));
    expect(result, containsPair('error', 'GitHub not configured'));
  });

  test('a bare-integer key routes to the ADO carrier', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result =
        jsonDecode(bridge.execute('tracker_get_ticket', {'key': '12345'}));
    expect(result, containsPair('error', contains('ADO')));
  });

  test('a canonical tool name dispatches unchanged', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());
    final result =
        jsonDecode(bridge.execute('jira_get_ticket', {'key': 'PROJ-1'}));
    expect(result, containsPair('error', 'Jira not configured'));
  });
}
