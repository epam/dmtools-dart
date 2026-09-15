// Dumps the Dart MCP tool catalog as JSON: {toolName: {params: [names],
// required: [names]}}. Feeds scripts/extract_java_tool_params.py — run from
// the repo root: `dart run scripts/dump_tool_params.dart`.
import 'dart:convert';

import 'package:dmtools/dmtools.dart';

void main() {
  print(const JsonEncoder().convert(<String, dynamic>{
    for (final t in createDefaultToolRegistry().allTools)
      t.name: {
        'params': t.params.map((p) => p.name).toList(),
        'required':
            t.params.where((p) => p.required).map((p) => p.name).toList(),
      },
  }));
}
