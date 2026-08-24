/// Phase 3 "CI comparison green" gate — Dart vs. Java MCP tool catalog.
///
/// Compares the Dart catalog from [createDefaultToolRegistry] against the Java
/// reference catalog extracted from the `@MCPTool` annotations in
/// `dm.ai/dmtools-core` (see `test/fixtures/java_mcp_tool_names.txt`). Every
/// Java tool must be accounted for by one of:
///
/// 1. an **exact** name match in the Dart registry, or
/// 2. a **documented naming-convention equivalent** (see below), or
/// 3. an entry in the **frozen gap snapshot** (`java_mcp_tool_gaps.txt`).
///
/// The documented naming conventions the Dart port deliberately diverges on:
///
/// - **AI**: Dart exposes both the unified `ai_chat` family and the
///   per-provider tools Java has (`openai_ai_chat`, `gemini_ai_chat`,
///   `anthropic_ai_chat`, …) — those match exactly. Remaining Java AI
///   variants (`*_ai_chat_with_files`, `*_list_models`,
///   `vertex_ai_gemini_chat`) map onto `ai_chat_with_history` /
///   `ai_list_models`.
/// - **Teams**: Java exposes `teams_*_raw` variants that return unprocessed
///   Graph JSON. Dart drops the `_raw` suffix when the consolidated tool covers
///   the same shape.
///
/// The snapshot test stays green while the gap is unchanged. Port a Java tool
/// and it turns red, prompting the gap to shrink; re-extract the fixture from a
/// newer Java build and it turns red if new unported tools appear.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  final javaNames = _readFixture('java_mcp_tool_names.txt');
  final dartNames =
      createDefaultToolRegistry().allTools.map((t) => t.name).toSet();
  final frozenGaps = _readFixture('java_mcp_tool_gaps.txt');

  fixtureSanityTests(javaNames, dartNames);
  paritySnapshotTests(javaNames, dartNames, frozenGaps);
  equivalentMappingTests(javaNames, dartNames);
}

/// Asserts the fixture files are well-formed and in sync.
void fixtureSanityTests(List<String> javaNames, Set<String> dartNames) {
  group('fixture sanity', () {
    test('Java fixture lists unique snake_case tool names', () {
      expect(javaNames, isNotEmpty);
      expect(javaNames.toSet().length, javaNames.length, reason: 'duplicates');
      for (final n in javaNames) {
        expect(_snakeCase.hasMatch(n), isTrue, reason: 'bad name: $n');
      }
    });

    test('Dart registry is non-empty', () {
      expect(dartNames, isNotEmpty);
    });
  });
}

/// The core gate: the computed parity gap must match the frozen snapshot.
void paritySnapshotTests(
  List<String> javaNames,
  Set<String> dartNames,
  List<String> frozenGaps,
) {
  group('catalog parity snapshot', () {
    test('computed gap equals the frozen snapshot', () {
      final computed = _computeGaps(javaNames, dartNames);
      expect(
        computed,
        unorderedEquals(frozenGaps.toSet()),
        reason: 'The Java↔Dart tool gap changed. Port a tool and shrink\n'
            'test/fixtures/java_mcp_tool_gaps.txt, or re-extract\n'
            'test/fixtures/java_mcp_tool_names.txt from the latest Java build.',
      );
    });

    test('no frozen gap is also a registered Dart tool (snapshot is fresh)',
        () {
      final stale = frozenGaps.where(dartNames.contains).toSet();
      expect(
        stale,
        isEmpty,
        reason: 'Tools now exist in Dart — remove them from the gap '
            'snapshot: $stale',
      );
    });
  });
}

/// The documented naming-convention equivalents must resolve to real Dart tools.
void equivalentMappingTests(List<String> javaNames, Set<String> dartNames) {
  group('documented equivalents', () {
    test('every documented equivalent resolves to a registered tool', () {
      for (final j in javaNames) {
        final equiv = _dartEquivalentFor(j, dartNames);
        if (equiv != null) {
          expect(
            dartNames,
            contains(equiv),
            reason: '$j maps to unregistered $equiv',
          );
        }
      }
    });
  });
}

/// Reads a newline-delimited fixture under `test/fixtures`, sorted, no blanks.
List<String> _readFixture(String name) {
  final lines = File('test/fixtures/$name')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList()
    ..sort();
  return lines;
}

/// Computes the Java tools with no exact Dart match and no documented
/// equivalent — the genuine not-yet-ported gap.
Set<String> _computeGaps(List<String> javaNames, Set<String> dartNames) {
  final gaps = <String>{};
  for (final j in javaNames) {
    if (dartNames.contains(j)) continue;
    final equiv = _dartEquivalentFor(j, dartNames);
    if (equiv == null || !dartNames.contains(equiv)) gaps.add(j);
  }
  return gaps;
}

/// Resolves a Java tool name to its Dart equivalent under the documented
/// naming conventions, or `null` when there is no documented mapping.
String? _dartEquivalentFor(String javaName, Set<String> dartNames) =>
    _aiEquivalent(javaName) ?? _teamsRawEquivalent(javaName, dartNames);

/// Maps Java per-provider AI tools onto Dart's unified `ai_*` family.
String? _aiEquivalent(String javaName) {
  if (javaName == 'vertex_ai_gemini_chat') return 'ai_chat';
  if (javaName == 'vertex_ai_gemini_chat_with_files') {
    return 'ai_chat_with_history';
  }
  for (final p in _aiProviders) {
    if (javaName == '${p}_ai_chat') return 'ai_chat';
    if (javaName == '${p}_ai_chat_with_files') return 'ai_chat_with_history';
    if (javaName == '${p}_list_models') return 'ai_list_models';
  }
  return null;
}

/// Maps Java `teams_*_raw` tools to their `_raw`-stripped Dart counterpart.
String? _teamsRawEquivalent(String javaName, Set<String> dartNames) {
  if (!javaName.endsWith('_raw')) return null;
  final stripped = javaName.substring(0, javaName.length - 4);
  return dartNames.contains(stripped) ? stripped : null;
}

/// Java AI integrations whose remaining variant tools Dart collapses into the
/// unified catalog (the per-provider `*_ai_chat` tools match exactly).
const _aiProviders = [
  'openai',
  'gemini',
  'anthropic',
  'ollama',
  'dial',
  'bedrock',
];

/// snake_case identifier pattern used by every MCP tool name.
final RegExp _snakeCase = RegExp(r'^[a-z][a-z0-9_]*$');
