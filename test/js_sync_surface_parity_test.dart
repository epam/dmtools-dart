/// JS sync-surface parity: every canonical MCP tool must either resolve to
/// a [SyncToolDispatcher] handler or be an acknowledged gap in the frozen
/// ratchet list.
///
/// Why: the JS bridge generates a global wrapper for EVERY registry tool
/// (`ToolWrapperGenerator` — agent scripts see all 420 functions), but the
/// call dispatches through the sync layer; a tool without a sync handler
/// dies at runtime with `Unsupported tool` (exactly how
/// `gitlab_get_mr_pipelines` slipped through Java #574 → #159). This test
/// makes that hole impossible to add silently:
///
/// - a NEW tool without a sync executor fails the test (list mismatch);
/// - a CLOSED gap that is not removed from the list fails the test too
///   (the ratchet only shrinks, both directions enforced).
///
/// A "hole" is: `null` from the dispatcher (no handler → `Tool not
/// available` upstream), or an error envelope naming the tool Unsupported/
/// Unknown. An `<integration> not configured` envelope means the handler
/// EXISTS (config is absent in the test env) — that is the healthy answer.
/// Executor argument-validation exceptions likewise prove a handler exists.
library;

import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tool_dispatcher.dart';
import 'package:dmtools/src/mcp/default_tool_registry.dart';
import 'package:test/test.dart';

const _gapsPath = 'test/fixtures/js_sync_surface_gaps.txt';

void main() {
  test(
      'every canonical MCP tool reaches a JS sync handler (ratcheted '
      'gaps only)', () {
    PropertyReader.testIsolation = true;
    addTearDown(() => PropertyReader.testIsolation = false);

    final registry = createDefaultToolRegistry();
    final dispatcher = SyncToolDispatcher(PropertyReader());

    final holes = <String>{};
    for (final tool in registry.allTools) {
      if (_isHole(dispatcher, tool.name)) holes.add(tool.name);
    }

    final frozen = _frozenGaps();
    expect(frozen, isNotEmpty, reason: 'fixture missing: $_gapsPath');

    final newHoles = holes.difference(frozen).toList()..sort();
    final stale = frozen.difference(holes).toList()..sort();

    expect(
      newHoles,
      isEmpty,
      reason: 'New MCP tools without JS sync executors — these names get a '
          'generated JS wrapper but die with "Unsupported tool" at call '
          'time. Implement the sync executor or (if deliberate) append to '
          '$_gapsPath:\n${newHoles.join('\n')}',
    );
    expect(
      stale,
      isEmpty,
      reason: 'Closed gaps still frozen in $_gapsPath — the ratchet only '
          'shrinks; remove the resolved names in the same PR:\n'
          '${stale.join('\n')}',
    );

    // ignore: avoid_print, audit trail on every run
    print(
      'js sync surface: ${registry.allTools.length} canonical tools, '
      '${holes.length} ratcheted gaps, '
      '${registry.allTools.length - holes.length} live handlers',
    );
  });
}

/// Whether [tool] fails to reach a sync executor: `null` (no handler) or
/// an Unsupported/Unknown-tool error envelope. Config-missing envelopes and
/// thrown validation errors both prove a handler exists.
bool _isHole(SyncToolDispatcher dispatcher, String tool) {
  final String? result;
  try {
    result = dispatcher.execute(tool, const {});
  } catch (_) {
    return false; // argument validation fired — handler present.
  }
  if (result == null) return true;
  return result.contains('Unsupported') ||
      result.contains('Tool not available') ||
      result.contains('Unknown tool');
}

/// The frozen gap list (sorted tool names, `#`-comment lines ignored).
Set<String> _frozenGaps() => File(_gapsPath)
    .readAsLinesSync()
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !l.startsWith('#'))
    .toSet();
