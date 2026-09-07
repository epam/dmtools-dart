/// Deep-merge logic for JSON-like configs — Dart port of Java
/// `ConfigurationMerger`.
///
/// Provides [deepMerge] for recursive map merging and [mergeEncodedConfig]
/// for merging a decoded override onto a base JSON config string.
library;

import 'dart:convert';

import 'encoding_detector.dart';

/// Deep-merges [override] into [base], returning a new map.
///
/// Rules (identical to Java `ConfigurationMerger`):
/// - Nested maps → recursive merge.
/// - Arrays/lists → complete replacement (NOT concatenation).
/// - Scalars → override wins.
///
/// Neither [base] nor [override] is mutated.
Map<String, dynamic> deepMerge(
  Map<String, dynamic> base,
  Map<String, dynamic> override,
) {
  final result = Map<String, dynamic>.from(base);
  for (final entry in override.entries) {
    final key = entry.key;
    final overrideValue = entry.value;
    final baseValue = result[key];
    if (baseValue is Map<String, dynamic> &&
        overrideValue is Map<String, dynamic>) {
      result[key] = deepMerge(baseValue, overrideValue);
    } else {
      result[key] = overrideValue;
    }
  }
  return result;
}

/// Merges an encoded override config onto a base JSON config string.
///
/// Steps:
/// 1. If [encodedConfig] is null or empty, returns [baseJson] unchanged.
/// 2. Auto-detects the encoding (base64 or URL-encoding) via
///    [autoDetectAndDecode].
/// 3. Parses the decoded string as a JSON object.
/// 4. Deep-merges it onto the base config (parsed from [baseJson]).
/// 5. Returns the merged result as a compact JSON string.
///
/// Throws [FormatException] if either JSON string is invalid, or
/// [ArgumentError] if the encoded config cannot be decoded.
///
/// Java `ConfigurationMerger.mergeConfigurations` parity (#525): parse
/// failures embed the offending JSON content in the error message
/// (`... File JSON content: …` / `... Encoded JSON content: …`) so a
/// malformed payload is debuggable from CI logs alone, and a blank base
/// config is rejected with `File JSON cannot be null or empty`.
String mergeEncodedConfig(String baseJson, String? encodedConfig) {
  if (baseJson.trim().isEmpty) {
    throw ArgumentError('File JSON cannot be null or empty');
  }
  if (encodedConfig == null || encodedConfig.isEmpty) {
    return baseJson;
  }
  final decoded = autoDetectAndDecode(encodedConfig);
  Map<String, dynamic> baseConfig;
  try {
    baseConfig = jsonDecode(baseJson) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw FormatException(
        'Invalid JSON format: ${e.message}. File JSON content: $baseJson',
        baseJson,
        e.offset);
  }
  Map<String, dynamic> overrideConfig;
  try {
    overrideConfig = jsonDecode(decoded) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw FormatException(
        'Invalid JSON format: ${e.message}. Encoded JSON content: $decoded',
        decoded,
        e.offset);
  }
  final merged = deepMerge(baseConfig, overrideConfig);
  return jsonEncode(merged);
}
