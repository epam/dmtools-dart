/// Parser for `.env` files (KEY=VALUE format).
///
/// Mirrors the Java `CommandLineUtils.loadEnvironmentFromFile` semantics:
/// lines starting with `#` are comments, lines without `=` are skipped,
/// the value is everything after the first `=`, both key and value are
/// trimmed. No `export` prefix support, no quote stripping — identical to
/// the Java implementation.
library;

import 'dart:io';

/// Parses an `.env` file into a [Map].
///
/// Returns an empty map if the file does not exist or cannot be read.
Map<String, String> parseEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return {};
  }
  final result = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#') || !trimmed.contains('=')) {
      continue;
    }
    final eqIndex = trimmed.indexOf('=');
    final key = trimmed.substring(0, eqIndex).trim();
    final value = trimmed.substring(eqIndex + 1).trim();
    if (key.isNotEmpty) {
      result[key] = value;
    }
  }
  return result;
}
