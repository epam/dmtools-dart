/// Shared helpers for parsing MCP tool arguments.
///
/// Tool executors across integrations reuse these coercion helpers so that
/// JSON values arriving from the MCP protocol (where numbers may arrive as
/// strings) are normalized before reaching the integration client.
library;

/// Parses a required integer argument, accepting int/num/String forms.
///
/// Returns the int value of [args][[key]], coercing `num` via [num.toInt] and
/// `String` via [int.parse]. Throws [ArgumentError] when [key] is absent.
int requiredInt(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.parse(value);
  throw ArgumentError('Missing required parameter: $key');
}
