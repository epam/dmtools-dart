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
String mergeEncodedConfig(String baseJson, String? encodedConfig) {
  if (encodedConfig == null || encodedConfig.isEmpty) {
    return baseJson;
  }
  final decoded = autoDetectAndDecode(encodedConfig);
  final overrideConfig = jsonDecode(decoded) as Map<String, dynamic>;
  final baseConfig = jsonDecode(baseJson) as Map<String, dynamic>;
  final merged = deepMerge(baseConfig, overrideConfig);
  return jsonEncode(merged);
}
